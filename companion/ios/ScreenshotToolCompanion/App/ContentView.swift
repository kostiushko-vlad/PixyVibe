import SwiftUI
import ReplayKit

struct ContentView: View {
    @EnvironmentObject var discovery: DesktopDiscovery
    @EnvironmentObject var webSocket: WebSocketClient

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Connection status
                connectionStatus

                // Desktop list
                if !discovery.desktops.isEmpty {
                    desktopList
                }

                Spacer()

                // Broadcast button
                if webSocket.isConnected {
                    broadcastSection
                }
            }
            .padding()
            .navigationTitle("PixyVibe Companion")
        }
        .onAppear {
            discovery.startSearching()
        }
    }

    private var connectionStatus: some View {
        HStack {
            Circle()
                .fill(webSocket.isConnected ? Color.green : Color.orange)
                .frame(width: 12, height: 12)

            if webSocket.isConnected {
                Text("Connected to \(webSocket.connectedDesktopName)")
                    .font(.headline)
            } else if discovery.isSearching {
                Text("Searching for PixyVibe desktops...")
                    .font(.headline)
                    .foregroundColor(.secondary)
            } else {
                Text("No desktops found")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var desktopList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Available Desktops")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach(discovery.desktops) { desktop in
                Button(action: {
                    webSocket.connect(to: desktop)
                }) {
                    HStack {
                        Image(systemName: "desktopcomputer")
                        Text(desktop.name)
                        Spacer()
                        if webSocket.connectedDesktopName == desktop.name {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var broadcastSection: some View {
        VStack(spacing: 12) {
            Text("Screen Sharing")
                .font(.subheadline)
                .foregroundColor(.secondary)

            BroadcastSetupUI()
                .frame(height: 50)
                .cornerRadius(12)
        }
    }
}
