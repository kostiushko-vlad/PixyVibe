import SwiftUI

@main
struct CompanionApp: App {
    @StateObject private var discovery = DesktopDiscovery()
    @StateObject private var webSocket = WebSocketClient.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(discovery)
                .environmentObject(webSocket)
        }
    }
}
