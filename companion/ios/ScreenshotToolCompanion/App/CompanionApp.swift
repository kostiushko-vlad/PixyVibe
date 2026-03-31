import SwiftUI

@main
struct CompanionApp: App {
    @StateObject private var discovery = DesktopDiscovery()
    @StateObject private var webSocket = WebSocketClient.shared
    @AppStorage("companionOnboardingComplete") private var onboardingComplete = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(discovery)
                    .environmentObject(webSocket)

                if !onboardingComplete {
                    CompanionOnboardingView {
                        withAnimation(PVi.snappy) {
                            onboardingComplete = true
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }
}
