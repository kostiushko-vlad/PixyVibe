import Foundation

class WebSocketClient: ObservableObject {
    static let shared = WebSocketClient()

    @Published var isConnected = false
    @Published var connectedDesktopName = ""

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    private let deviceName = UIDevice.current.name

    private init() {
        session = URLSession(configuration: .default)
    }

    func connect(to desktop: DiscoveredDesktop) {
        disconnect()

        let urlString = "ws://\(desktop.host):\(desktop.port)"
        guard let url = URL(string: urlString) else { return }

        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()

        isConnected = true
        connectedDesktopName = desktop.name

        receiveMessages()
    }

    func disconnect() {
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        isConnected = false
        connectedDesktopName = ""
    }

    func sendFrame(_ jpegData: Data) {
        let base64 = jpegData.base64EncodedString()
        let message: [String: Any] = [
            "type": "frame",
            "data": base64,
            "timestamp": Int(Date().timeIntervalSince1970)
        ]

        guard let json = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: json, encoding: .utf8)
        else { return }

        webSocket?.send(.string(jsonString)) { error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }

    func sendScreenshot(_ pngData: Data) {
        let base64 = pngData.base64EncodedString()
        let message: [String: Any] = [
            "type": "screenshot_result",
            "data": base64
        ]

        guard let json = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: json, encoding: .utf8)
        else { return }

        webSocket?.send(.string(jsonString)) { _ in }
    }

    private func receiveMessages() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                default:
                    break
                }
                // Continue receiving
                self.receiveMessages()

            case .failure(let error):
                print("WebSocket receive error: \(error)")
                DispatchQueue.main.async {
                    self.isConnected = false
                }
                // Attempt reconnect after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    // TODO: reconnect logic
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return }

        switch type {
        case "ping":
            // Respond with pong
            let pong: [String: Any] = [
                "type": "pong",
                "device_name": deviceName,
                "device_id": deviceId
            ]
            if let pongData = try? JSONSerialization.data(withJSONObject: pong),
               let pongString = String(data: pongData, encoding: .utf8)
            {
                webSocket?.send(.string(pongString)) { _ in }
            }

        case "screenshot":
            // Capture and send a screenshot
            // This is handled by the broadcast extension
            print("Screenshot request received")

        case "start_recording":
            let fps = json["fps"] as? Int ?? 10
            print("Start recording at \(fps) fps")

        case "stop_recording":
            print("Stop recording")

        default:
            print("Unknown message type: \(type)")
        }
    }
}
