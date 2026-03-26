import SwiftUI

struct ContentView: View {
    @EnvironmentObject var discovery: DesktopDiscovery
    @EnvironmentObject var webSocket: WebSocketClient
    @State private var editingName = false
    @State private var nameText = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    deviceNameCard
                    connectedDesktopsCard
                    desktopList

                    if webSocket.hasAnyConnection {
                        broadcastSection
                    } else if discovery.isSearching && discovery.desktops.isEmpty {
                        searchingView
                    } else if discovery.desktops.isEmpty {
                        emptyStateView
                    }
                }
                .padding()
            }
            .navigationTitle("PixyVibe")
            .onAppear {
                BroadcastManager.shared.initialize()
                discovery.startSearching()
            }
            .onReceive(discovery.$desktops) { desktops in
                autoConnectAll(desktops)
            }
        }
    }

    // MARK: - Device Name

    private var deviceNameCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone")
                .font(.title3)
                .foregroundColor(.accentColor)

            if editingName {
                TextField("Device name", text: $nameText, onCommit: {
                    if !nameText.trimmingCharacters(in: .whitespaces).isEmpty {
                        webSocket.deviceName = nameText
                    }
                    editingName = false
                })
                .textFieldStyle(RoundedBorderTextFieldStyle())

                Button("Save") {
                    if !nameText.trimmingCharacters(in: .whitespaces).isEmpty {
                        webSocket.deviceName = nameText
                    }
                    editingName = false
                }
                .font(.caption)
            } else {
                Text(webSocket.deviceName)
                    .font(.body)

                Spacer()

                Button("Rename") {
                    nameText = webSocket.deviceName
                    editingName = true
                }
                .font(.caption)
                .foregroundColor(.accentColor)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Connected Desktops Status

    private var connectedDesktopsCard: some View {
        let connected = webSocket.connections.values.filter { $0.state == .connected }
        let connecting = webSocket.connections.values.filter { $0.state == .connecting }

        return Group {
            if !connected.isEmpty || !connecting.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(webSocket.connections.values).sorted(by: { $0.id < $1.id }), id: \.id) { conn in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(conn.state == .connected ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)

                            Text(conn.id)
                                .font(.subheadline)

                            Spacer()

                            Text(conn.state == .connected ? "Connected" : "Connecting...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Desktop List

    private var desktopList: some View {
        let unconnected = discovery.desktops.filter { webSocket.stateFor($0.name) == .disconnected }

        return Group {
            if !unconnected.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Available Desktops")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)

                    ForEach(unconnected) { desktop in
                        Button(action: {
                            if desktop.isResolved {
                                webSocket.connect(to: desktop)
                            }
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "desktopcomputer")
                                    .font(.title3)
                                    .foregroundColor(.accentColor)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(desktop.name)
                                        .font(.body)
                                        .foregroundColor(.primary)

                                    if desktop.isResolved {
                                        Text("\(desktop.host!):\(desktop.port!)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Resolving...")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                    }
                                }

                                Spacer()

                                Text("Connect")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .disabled(!desktop.isResolved)
                    }
                }
            }
        }
    }

    // MARK: - Broadcast

    private var broadcastSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "record.circle")
                    .font(.system(size: 40))
                    .foregroundColor(.red)

                Text("Screen Broadcast")
                    .font(.headline)

                Text("Tap the button below to start streaming your screen to connected desktops.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            BroadcastSetupUI()
                .frame(height: 50)
                .cornerRadius(12)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }

    // MARK: - Empty / Searching States

    private var searchingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Looking for PixyVibe on your network...")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            infoBox
        }
        .padding(.top, 40)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("No desktops found")
                .font(.headline)

            infoBox
        }
        .padding(.top, 40)
    }

    private var infoBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Open PixyVibe on your Mac", systemImage: "1.circle.fill")
            Label("Both devices on the same Wi-Fi", systemImage: "2.circle.fill")
            Label("Desktops connect automatically", systemImage: "3.circle.fill")
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Auto-Connect to ALL discovered desktops

    private func autoConnectAll(_ desktops: [DiscoveredDesktop]) {
        for desktop in desktops where desktop.isResolved {
            if webSocket.stateFor(desktop.name) == .disconnected {
                webSocket.connect(to: desktop)
            }
        }
    }
}
