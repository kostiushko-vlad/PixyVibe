import Foundation
import UIKit

/// State of a single desktop connection
struct DesktopConnection: Identifiable {
    let id: String // desktop name
    let host: String
    let port: Int
    var state: ConnectionState = .disconnected
    var webSocket: URLSessionWebSocketTask?
    var reconnectAttempts = 0
    var shouldReconnect = true
}

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
}

/// Manages WebSocket connections to multiple desktop PixyVibe instances simultaneously.
class WebSocketClient: ObservableObject {
    static let shared = WebSocketClient()

    @Published var connections: [String: DesktopConnection] = [:]

    var connectedCount: Int { connections.values.filter { $0.state == .connected }.count }
    var hasAnyConnection: Bool { connectedCount > 0 }

    private var session: URLSession?
    private let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    private let maxReconnectAttempts = 5
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private let appGroupDefaults = UserDefaults(suiteName: "group.com.pixyvibe.companion")

    /// User-configurable device name
    var deviceName: String {
        get {
            UserDefaults.standard.string(forKey: "custom_device_name")
                ?? UIDevice.current.name
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "custom_device_name")
            appGroupDefaults?.set(newValue, forKey: "device_name_display")
            appGroupDefaults?.synchronize()
        }
    }

    private init() {
        session = URLSession(configuration: .default)
        setupBackgroundHandling()
    }

    // MARK: - Background Handling

    private func setupBackgroundHandling() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.beginBackgroundKeepAlive()
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.endBackgroundKeepAlive()
        }
    }

    private func beginBackgroundKeepAlive() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "KeepWebSocket") { [weak self] in
            self?.endBackgroundKeepAlive()
        }
    }

    private func endBackgroundKeepAlive() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - Connection Management

    func connect(to desktop: DiscoveredDesktop) {
        guard let host = desktop.host, let port = desktop.port, desktop.isResolved else { return }
        connect(host: host, port: port, name: desktop.name)
    }

    func connect(host: String, port: Int, name: String) {
        // Skip if already connecting/connected to this desktop
        if let existing = connections[name], existing.state != .disconnected,
           existing.host == host, existing.port == port {
            return
        }

        // Disconnect existing connection to this desktop if any
        disconnectDesktop(name)

        let urlString = "ws://\(host):\(port)"
        guard let url = URL(string: urlString) else { return }

        let ws = session?.webSocketTask(with: url)
        ws?.resume()

        var conn = DesktopConnection(id: name, host: host, port: port, state: .connecting, webSocket: ws)
        conn.shouldReconnect = true
        connections[name] = conn

        DispatchQueue.main.async {
            self.objectWillChange.send()
        }

        // Save all connections for broadcast extension
        saveAllConnectionInfo()

        receiveMessages(for: name)
    }

    func disconnectDesktop(_ name: String) {
        guard var conn = connections[name] else { return }
        conn.shouldReconnect = false
        conn.webSocket?.cancel(with: .normalClosure, reason: nil)
        connections.removeValue(forKey: name)
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
        saveAllConnectionInfo()
    }

    func disconnectAll() {
        for name in connections.keys {
            connections[name]?.shouldReconnect = false
            connections[name]?.webSocket?.cancel(with: .normalClosure, reason: nil)
        }
        connections.removeAll()
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
        saveAllConnectionInfo()
    }

    /// Check if a desktop is connected or connecting
    func stateFor(_ desktopName: String) -> ConnectionState {
        connections[desktopName]?.state ?? .disconnected
    }

    // MARK: - App Group Storage

    private func saveAllConnectionInfo() {
        // Save list of desktops for broadcast extension
        let desktopList = connections.values.map { conn -> [String: Any] in
            ["host": conn.host, "port": conn.port, "name": conn.id]
        }

        if let data = try? JSONSerialization.data(withJSONObject: desktopList) {
            appGroupDefaults?.set(data, forKey: "desktop_list")
        }

        // Keep legacy single-desktop keys for backward compat
        if let first = connections.values.first {
            appGroupDefaults?.set(first.host, forKey: "desktop_host")
            appGroupDefaults?.set(first.port, forKey: "desktop_port")
            appGroupDefaults?.set(first.id, forKey: "desktop_name")
        }

        appGroupDefaults?.set(deviceId, forKey: "device_id")
        appGroupDefaults?.set(deviceName, forKey: "device_name_display")
        appGroupDefaults?.synchronize()
    }

    var lastDesktopName: String? {
        appGroupDefaults?.string(forKey: "desktop_name")
    }

    // MARK: - Sending

    /// Send a frame to all connected desktops
    func sendFrameToAll(_ jpegData: Data) {
        let base64 = jpegData.base64EncodedString()
        let dict: [String: Any] = ["type": "frame", "data": base64, "timestamp": Int(Date().timeIntervalSince1970)]
        for name in connections.keys {
            sendJSON(dict, to: name)
        }
    }

    /// Send a screenshot result to all connected desktops
    func sendScreenshotToAll(_ pngData: Data) {
        let base64 = pngData.base64EncodedString()
        let dict: [String: Any] = ["type": "screenshot_result", "data": base64]
        for name in connections.keys {
            sendJSON(dict, to: name)
        }
    }

    private func sendJSON(_ dict: [String: Any], to desktopName: String) {
        guard let conn = connections[desktopName],
              let json = try? JSONSerialization.data(withJSONObject: dict),
              let jsonString = String(data: json, encoding: .utf8)
        else { return }

        conn.webSocket?.send(.string(jsonString)) { error in
            if let error = error {
                print("[\(desktopName)] WebSocket send error: \(error)")
            }
        }
    }

    // MARK: - Receiving

    private func receiveMessages(for desktopName: String) {
        guard let conn = connections[desktopName] else { return }
        conn.webSocket?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self.handleMessage(text, from: desktopName)
                }
                self.receiveMessages(for: desktopName)

            case .failure(let error):
                print("[\(desktopName)] WebSocket error: \(error)")
                DispatchQueue.main.async {
                    self.connections[desktopName]?.state = .disconnected
                    self.objectWillChange.send()
                }
                self.attemptReconnect(desktopName)
            }
        }
    }

    private func handleMessage(_ text: String, from desktopName: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return }

        switch type {
        case "ping":
            let pong: [String: Any] = [
                "type": "pong",
                "device_name": deviceName,
                "device_id": deviceId
            ]
            sendJSON(pong, to: desktopName)

            DispatchQueue.main.async {
                self.connections[desktopName]?.state = .connected
                self.objectWillChange.send()
            }

        case "screenshot":
            print("[\(desktopName)] Screenshot request — triggering broadcast")
            BroadcastManager.shared.triggerBroadcast()

        default:
            break
        }
    }

    // MARK: - Reconnection

    private func attemptReconnect(_ desktopName: String) {
        guard var conn = connections[desktopName], conn.shouldReconnect else { return }

        guard conn.reconnectAttempts < maxReconnectAttempts else {
            print("[\(desktopName)] Max reconnect attempts reached")
            conn.shouldReconnect = false
            connections[desktopName] = conn
            DispatchQueue.main.async {
                self.connections.removeValue(forKey: desktopName)
                self.objectWillChange.send()
            }
            return
        }

        conn.reconnectAttempts += 1
        connections[desktopName] = conn
        let delay = min(pow(2.0, Double(conn.reconnectAttempts)), 30.0)
        let host = conn.host
        let port = conn.port

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.connections[desktopName]?.shouldReconnect == true else { return }
            self.connect(host: host, port: port, name: desktopName)
        }
    }
}
