import ReplayKit
import Foundation
import UIKit

class SampleHandler: RPBroadcastSampleHandler {
    private var transports: [FrameTransportLite] = []
    private var lastFrameTime: CFAbsoluteTime = 0
    private let minFrameInterval: CFAbsoluteTime = 0.1 // 10fps max
    private lazy var ciContext = CIContext()
    private var screenshotRequested = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        let defaults = UserDefaults(suiteName: "group.com.pixyvibe.companion")

        // Read list of desktops (new format)
        var desktopList: [[String: Any]] = []
        if let data = defaults?.data(forKey: "desktop_list"),
           let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            desktopList = list
        }

        // Fallback to legacy single-desktop keys
        if desktopList.isEmpty {
            if let host = defaults?.string(forKey: "desktop_host"),
               let port = defaults?.integer(forKey: "desktop_port"), port > 0 {
                desktopList = [["host": host, "port": port, "name": "Desktop"]]
            }
        }

        guard !desktopList.isEmpty else {
            finishBroadcastWithError(NSError(domain: "com.pixyvibe", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No desktop connection configured. Open the PixyVibe Companion app first."]))
            return
        }

        // Connect to all desktops
        for desktop in desktopList {
            guard let host = desktop["host"] as? String,
                  let port = desktop["port"] as? Int, port > 0 else { continue }

            let transport = FrameTransportLite(host: host, port: port)
            transport.onScreenshotRequested = { [weak self] in
                self?.screenshotRequested = true
            }
            transport.connect()
            transports.append(transport)
        }

        defaults?.set(true, forKey: "broadcast_active")
        defaults?.synchronize()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }

        // If a screenshot was requested, capture this frame as full-quality PNG
        if screenshotRequested {
            screenshotRequested = false

            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

            let ciImage = CIImage(cvPixelBuffer: imageBuffer)
            guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

            let uiImage = UIImage(cgImage: cgImage)
            guard let pngData = uiImage.pngData() else { return }

            // Send screenshot result to ALL connected desktops
            for transport in transports {
                transport.sendScreenshotResult(pngData)
            }
            return
        }

        // Normal frame streaming (rate-limited)
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFrameTime >= minFrameInterval else { return }
        lastFrameTime = now

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.5) else { return }

        // Send frame to ALL connected desktops
        for transport in transports {
            transport.sendFrame(jpegData)
        }
    }

    override func broadcastFinished() {
        for transport in transports {
            transport.disconnect()
        }
        transports.removeAll()

        let defaults = UserDefaults(suiteName: "group.com.pixyvibe.companion")
        defaults?.set(false, forKey: "broadcast_active")
        defaults?.synchronize()
    }
}

/// Lightweight WebSocket transport for the broadcast extension.
/// Minimal memory footprint to stay within ReplayKit's 50MB limit.
/// Auto-reconnects when connection drops (e.g. phone sleep/wake).
class FrameTransportLite {
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var shouldReconnect = true
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 100

    var onScreenshotRequested: (() -> Void)?

    private var host: String
    private var port: Int
    private var deviceId: String
    private var deviceName: String

    init(host: String, port: Int) {
        self.host = host
        self.port = port

        let defaults = UserDefaults(suiteName: "group.com.pixyvibe.companion")
        self.deviceId = defaults?.string(forKey: "device_id")
            ?? UIDevice.current.identifierForVendor?.uuidString
            ?? UUID().uuidString
        self.deviceName = defaults?.string(forKey: "device_name_display")
            ?? UIDevice.current.name

        self.session = URLSession(configuration: .default)
    }

    func connect() {
        reconnectAttempts = 0
        doConnect()
    }

    private func doConnect() {
        // Re-read connection info in case main app updated it
        let defaults = UserDefaults(suiteName: "group.com.pixyvibe.companion")
        if let h = defaults?.string(forKey: "desktop_host") {
            // Only update if this transport's host matches the legacy key
            // (for multi-desktop, each transport keeps its own host/port)
        }

        guard let url = URL(string: "ws://\(host):\(port)") else { return }
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()
        receiveMessages()
    }

    func sendFrame(_ jpegData: Data) {
        let base64 = jpegData.base64EncodedString()
        let json = "{\"type\":\"frame\",\"data\":\"\(base64)\",\"timestamp\":\(Int(Date().timeIntervalSince1970))}"
        webSocket?.send(.string(json)) { _ in }
    }

    func sendScreenshotResult(_ pngData: Data) {
        let base64 = pngData.base64EncodedString()
        let json = "{\"type\":\"screenshot_result\",\"data\":\"\(base64)\"}"
        webSocket?.send(.string(json)) { _ in }
    }

    func disconnect() {
        shouldReconnect = false
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
    }

    private func receiveMessages() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                self.reconnectAttempts = 0
                if case .string(let text) = message {
                    self.handleMessage(text)
                }
                self.receiveMessages()
            case .failure:
                self.attemptReconnect()
            }
        }
    }

    private func attemptReconnect() {
        guard shouldReconnect, reconnectAttempts < maxReconnectAttempts else { return }
        reconnectAttempts += 1
        let delay = min(Double(reconnectAttempts) * 2.0, 30.0)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.shouldReconnect else { return }
            self.doConnect()
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return }

        switch type {
        case "ping":
            let pong = "{\"type\":\"pong\",\"device_name\":\"\(deviceName) (Broadcast)\",\"device_id\":\"\(deviceId)\"}"
            webSocket?.send(.string(pong)) { _ in }
        case "screenshot":
            onScreenshotRequested?()
        default:
            break
        }
    }
}
