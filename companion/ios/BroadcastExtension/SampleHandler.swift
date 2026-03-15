import ReplayKit
import Foundation

class SampleHandler: RPBroadcastSampleHandler {
    private var transport: FrameTransportLite?
    private var lastFrameTime: CFAbsoluteTime = 0
    private let minFrameInterval: CFAbsoluteTime = 0.1 // 10fps max

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        // Read connection info from App Group shared container
        let defaults = UserDefaults(suiteName: "group.com.pixyvibe.companion")
        guard let host = defaults?.string(forKey: "desktop_host"),
              let port = defaults?.integer(forKey: "desktop_port"), port > 0
        else {
            finishBroadcastWithError(NSError(domain: "com.pixyvibe", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No desktop connection configured. Open the PixyVibe Companion app first."]))
            return
        }

        transport = FrameTransportLite(host: host, port: port)
        transport?.connect()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }

        // Rate limit
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFrameTime >= minFrameInterval else { return }
        lastFrameTime = now

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        let uiImage = UIImage(cgImage: cgImage)
        // Use lower quality to stay within 50MB memory limit
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.5) else { return }

        transport?.sendFrame(jpegData)
    }

    override func broadcastFinished() {
        transport?.disconnect()
        transport = nil
    }
}

/// Lightweight WebSocket transport for the broadcast extension.
/// Minimal memory footprint to stay within ReplayKit's 50MB limit.
class FrameTransportLite {
    private var webSocket: URLSessionWebSocketTask?
    private let host: String
    private let port: Int

    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    func connect() {
        guard let url = URL(string: "ws://\(host):\(port)") else { return }
        let session = URLSession(configuration: .default)
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
    }

    func sendFrame(_ jpegData: Data) {
        let base64 = jpegData.base64EncodedString()
        let json = "{\"type\":\"frame\",\"data\":\"\(base64)\",\"timestamp\":\(Int(Date().timeIntervalSince1970))}"
        webSocket?.send(.string(json)) { _ in }
    }

    func disconnect() {
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
    }
}
