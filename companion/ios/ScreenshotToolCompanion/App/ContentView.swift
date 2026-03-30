import SwiftUI

// MARK: - Design Tokens (matching macOS DesignSystem)

private enum PVi {
    // ┌──────────────────────────────────────────┐
    // │  Keep in sync with macos DesignSystem.swift │
    // └──────────────────────────────────────────┘
    static let base = Color(red: 0.051, green: 0.059, blue: 0.078)           // #0D0F14
    static let surface = Color(red: 0.086, green: 0.106, blue: 0.133)        // #161B22
    static let surfaceHigh = Color(red: 0.110, green: 0.137, blue: 0.200)    // #1C2333
    static let border = Color.white.opacity(0.06)
    static let textPrimary = Color(red: 0.902, green: 0.929, blue: 0.953)    // #E6EDF3
    static let textSecondary = Color(red: 0.545, green: 0.580, blue: 0.620)  // #8B949E

    // Accent: Ice — #38BDF8 → #818CF8
    static let accentStart = Color(red: 0.220, green: 0.741, blue: 0.973)
    static let accentEnd = Color(red: 0.506, green: 0.549, blue: 0.973)
    static let accent = LinearGradient(colors: [accentStart, accentEnd], startPoint: .leading, endPoint: .trailing)
    static let accentSolid = accentStart

    static let success = Color(red: 0.063, green: 0.725, blue: 0.506)        // #10B981
    static let snappy: Animation = .spring(duration: 0.3, bounce: 0.15)
}

struct ContentView: View {
    @EnvironmentObject var discovery: DesktopDiscovery
    @EnvironmentObject var webSocket: WebSocketClient
    @State private var editingName = false
    @State private var nameText = ""

    var body: some View {
        ZStack {
            PVi.base.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    headerView
                    deviceNameCard
                    connectedDesktopsCard
                    desktopList

                    if discovery.isSearching && discovery.desktops.isEmpty {
                        searchingView
                    } else if discovery.desktops.isEmpty {
                        emptyStateView
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            BroadcastManager.shared.initialize()
            discovery.startSearching()
        }
        .onReceive(discovery.$desktops) { desktops in
            autoConnectAll(desktops)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("PixyVibe")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(PVi.textPrimary)
                Text("Companion")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PVi.accent)
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }

    // MARK: - Device Name

    private var deviceNameCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(PVi.accentSolid.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "iphone")
                    .font(.system(size: 18))
                    .foregroundStyle(PVi.accent)
            }

            if editingName {
                TextField("Device name", text: $nameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundColor(PVi.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(PVi.surfaceHigh, in: RoundedRectangle(cornerRadius: 8))
                    .onSubmit {
                        saveName()
                    }

                PViButton("Save") { saveName() }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(webSocket.deviceName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(PVi.textPrimary)
                    Text("This device")
                        .font(.system(size: 11))
                        .foregroundColor(PVi.textSecondary)
                }

                Spacer()

                PViButton("Rename") {
                    nameText = webSocket.deviceName
                    editingName = true
                }
            }
        }
        .padding(14)
        .background(PVi.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(PVi.border, lineWidth: 0.5))
    }

    private func saveName() {
        if !nameText.trimmingCharacters(in: .whitespaces).isEmpty {
            webSocket.deviceName = nameText
        }
        editingName = false
    }

    // MARK: - Connected Desktops

    private var connectedDesktopsCard: some View {
        let sorted = Array(webSocket.connections.values).sorted { $0.id < $1.id }
        let hasAny = sorted.contains { $0.state == .connected || $0.state == .connecting }

        return Group {
            if hasAny {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("CONNECTED")
                        .padding(.bottom, 4)

                    ForEach(sorted.filter { $0.state != .disconnected }, id: \.id) { conn in
                        HStack(spacing: 10) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 14))
                                .foregroundColor(PVi.textSecondary)

                            Text(conn.id)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(PVi.textPrimary)

                            Spacer()

                            HStack(spacing: 5) {
                                Circle()
                                    .fill(conn.state == .connected ? PVi.success : Color.orange)
                                    .frame(width: 6, height: 6)
                                    .shadow(color: conn.state == .connected ? PVi.success.opacity(0.5) : .clear, radius: 4)
                                Text(conn.state == .connected ? "Connected" : "Connecting")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(PVi.textSecondary)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(PVi.surfaceHigh.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(14)
                .background(PVi.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(PVi.border, lineWidth: 0.5))
            }
        }
    }

    // MARK: - Desktop List

    private var desktopList: some View {
        let unconnected = discovery.desktops.filter { webSocket.stateFor($0.name) == .disconnected }

        return Group {
            if !unconnected.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("AVAILABLE")

                    ForEach(unconnected) { desktop in
                        Button(action: {
                            if desktop.isResolved { webSocket.connect(to: desktop) }
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "desktopcomputer")
                                    .font(.system(size: 16))
                                    .foregroundStyle(PVi.accent)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(desktop.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(PVi.textPrimary)
                                    if desktop.isResolved {
                                        Text("\(desktop.host!):\(desktop.port!)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(PVi.textSecondary)
                                    } else {
                                        Text("Resolving...")
                                            .font(.system(size: 10))
                                            .foregroundColor(.orange)
                                    }
                                }

                                Spacer()

                                Text("Connect")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(PVi.accent, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .padding(12)
                            .background(PVi.surface, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(PVi.border, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .disabled(!desktop.isResolved)
                        .opacity(desktop.isResolved ? 1 : 0.5)
                    }
                }
            }
        }
    }

    // MARK: - Empty / Searching

    private var searchingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(PVi.accentSolid)
                .scaleEffect(1.2)

            Text("Looking for PixyVibe on your network...")
                .font(.system(size: 14))
                .foregroundColor(PVi.textSecondary)
                .multilineTextAlignment(.center)

            infoBox
        }
        .padding(.top, 32)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(PVi.accentSolid.opacity(0.08))
                    .frame(width: 64, height: 64)
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 28))
                    .foregroundStyle(PVi.accent.opacity(0.6))
            }

            Text("No desktops found")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(PVi.textPrimary)

            infoBox
        }
        .padding(.top, 32)
    }

    private var infoBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            infoRow("1", "Open PixyVibe on your Mac")
            infoRow("2", "Both devices on the same Wi-Fi")
            infoRow("3", "Desktops connect automatically")
        }
        .padding(14)
        .background(PVi.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(PVi.border, lineWidth: 0.5))
    }

    private func infoRow(_ number: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(PVi.accentSolid.opacity(0.3), in: RoundedRectangle(cornerRadius: 5))
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(PVi.textSecondary)
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .tracking(1)
            .foregroundColor(PVi.textSecondary.opacity(0.6))
    }

    private func autoConnectAll(_ desktops: [DiscoveredDesktop]) {
        for desktop in desktops where desktop.isResolved {
            if webSocket.stateFor(desktop.name) == .disconnected {
                webSocket.connect(to: desktop)
            }
        }
    }
}

// MARK: - Small pill button

struct PViButton: View {
    let label: String
    let action: () -> Void

    init(_ label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PVi.accentSolid)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(PVi.accentSolid.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(PVi.accentSolid.opacity(0.2), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
