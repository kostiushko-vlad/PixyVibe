import SwiftUI
import Cocoa

struct SettingsView: View {
    @AppStorage("saveLocation") private var saveLocation = "~/.pixyvibe/captures"
    @AppStorage("gifFPS") private var gifFPS = 10
    @AppStorage("gifMaxDuration") private var gifMaxDuration = 30
    @AppStorage("imageMaxWidth") private var imageMaxWidth = 1280
    @AppStorage("jpegQuality") private var jpegQuality = 85
    @AppStorage("autoCleanup") private var autoCleanup = true
    @AppStorage("cleanupDays") private var cleanupDays = 30

    @State private var selectedTab = 0

    private let tabs = [
        ("keyboard", "Shortcuts"),
        ("camera", "Capture"),
        ("folder", "Output"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker in titlebar area
            HStack(spacing: 2) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { i, tab in
                    PVTabButton(icon: tab.0, label: tab.1, isSelected: selectedTab == i) {
                        withAnimation(PV.Anim.snappy) { selectedTab = i }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 0)
            .padding(.bottom, 8)
            .frame(height: 44)

            Rectangle()
                .fill(PV.Colors.border.opacity(0.4))
                .frame(height: 0.5)

            // Content
            Group {
                switch selectedTab {
                case 0: shortcutsTab
                case 1: captureTab
                case 2: outputTab
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 480, height: 460)
        .background(PV.Colors.base)
        .preferredColorScheme(.dark)
    }

    // MARK: - Shortcuts

    private var shortcutsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                pvSectionHeader("Keyboard Shortcuts")

                PVCard {
                    VStack(spacing: 0) {
                        ShortcutRow(label: "Screenshot", icon: "camera.viewfinder", action: .screenshot)
                        pvDivider()
                        ShortcutRow(label: "Record GIF", icon: "record.circle", action: .gifRecording)
                        pvDivider()
                        ShortcutRow(label: "Before/After Diff", icon: "square.split.2x1", action: .diff)
                    }
                }

                HStack {
                    Text("Click a shortcut, then press your new key combination.")
                        .font(.system(size: 11))
                        .foregroundColor(PV.Colors.textSecondary)
                    Spacer()
                    PVTextButton("Reset to Defaults") {
                        ShortcutStore.shared.screenshot = .defaultScreenshot
                        ShortcutStore.shared.gifRecording = .defaultGifRecording
                        ShortcutStore.shared.diff = .defaultDiff
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Capture

    private var captureTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                pvSectionHeader("GIF Recording")

                PVCard {
                    VStack(spacing: 14) {
                        pvSliderRow("Frame rate", value: $gifFPS, range: 5...30, step: 1, unit: "fps")
                        pvSliderRow("Max duration", value: $gifMaxDuration, range: 5...120, step: 5, unit: "s")
                    }
                }

                pvSectionHeader("Image Processing")

                PVCard {
                    VStack(spacing: 14) {
                        pvSliderRow("Max width", value: $imageMaxWidth, range: 640...3840, step: 128, unit: "px")
                        pvSliderRow("JPEG quality", value: $jpegQuality, range: 50...100, step: 5, unit: "%")
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Output

    private var outputTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                pvSectionHeader("Save Location")

                PVCard {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 12))
                            .foregroundColor(PV.Colors.textSecondary)
                        Text(saveLocation)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(PV.Colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        PVTextButton("Change") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            if panel.runModal() == .OK, let url = panel.url {
                                saveLocation = url.path
                            }
                        }
                    }
                }

                pvSectionHeader("Cleanup")

                PVCard {
                    VStack(alignment: .leading, spacing: 12) {
                        PVToggle("Auto-delete old captures", isOn: $autoCleanup)
                        if autoCleanup {
                            HStack {
                                Text("Keep for")
                                    .font(.system(size: 13))
                                    .foregroundColor(PV.Colors.textPrimary)
                                PVStepperField(value: $cleanupDays, range: 1...365)
                                Text("days")
                                    .font(.system(size: 13))
                                    .foregroundColor(PV.Colors.textSecondary)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Helpers

    private func pvSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(PV.Gradients.accent)
    }

    @ViewBuilder
    private func pvDivider() -> some View {
        Rectangle()
            .fill(PV.Colors.border.opacity(0.4))
            .frame(height: 0.5)
    }

    private func pvSliderRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int, unit: String) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(PV.Colors.textSecondary)
                Spacer()
                Text("\(value.wrappedValue)\(unit)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(PV.Colors.textPrimary)
            }
            GeometryReader { geo in
                let totalSteps = (range.upperBound - range.lowerBound) / step
                let pct = CGFloat(value.wrappedValue - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(PV.Colors.surfaceHigh)
                        .frame(height: 4)
                    // Filled track
                    PV.Gradients.accent
                        .frame(width: geo.size.width * pct, height: 4)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    // Thumb
                    Circle()
                        .fill(PV.Colors.textPrimary)
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .offset(x: geo.size.width * pct - 7)
                }
                .frame(height: 14)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let pct = max(0, min(1, drag.location.x / geo.size.width))
                            let raw = Double(range.lowerBound) + pct * Double(range.upperBound - range.lowerBound)
                            value.wrappedValue = Int((raw / Double(step)).rounded()) * step
                            value.wrappedValue = max(range.lowerBound, min(range.upperBound, value.wrappedValue))
                        }
                )
            }
            .frame(height: 14)
        }
    }
}

// MARK: - Custom Tab Button

struct PVTabButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : PV.Colors.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AnyShapeStyle(PV.Gradients.accent) : AnyShapeStyle(Color.white.opacity(hover ? 0.06 : 0)))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.clear : (hover ? Color.white.opacity(0.08) : Color.clear), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(PV.Anim.hover, value: hover)
    }
}

// MARK: - Custom Text Button

struct PVTextButton: View {
    let label: String
    let action: () -> Void
    @State private var hover = false

    init(_ label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hover ? AnyShapeStyle(PV.Gradients.accent) : AnyShapeStyle(PV.Colors.textSecondary))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(PV.Colors.surfaceHigh, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(hover ? PV.Gradients.accentSolid.opacity(0.3) : PV.Border.thinColor, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(PV.Anim.hover, value: hover)
    }
}

// MARK: - Custom Toggle

struct PVToggle: View {
    let label: String
    @Binding var isOn: Bool

    init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        self._isOn = isOn
    }

    var body: some View {
        Button(action: { withAnimation(PV.Anim.snappy) { isOn.toggle() } }) {
            HStack {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(PV.Colors.textPrimary)
                Spacer()
                // Toggle track
                ZStack(alignment: isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isOn ? PV.Gradients.accentSolid : PV.Colors.surfaceHigh)
                        .frame(width: 36, height: 20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(isOn ? PV.Gradients.accentSolid.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                    // Knob
                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                        .padding(.horizontal, 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Custom Stepper

struct PVStepperField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 0) {
            Button(action: { if value > range.lowerBound { value -= 1 } }) {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(PV.Colors.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            Text("\(value)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(PV.Colors.textPrimary)
                .frame(width: 36)

            Button(action: { if value < range.upperBound { value += 1 } }) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(PV.Colors.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .background(PV.Colors.surfaceHigh, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(PV.Border.thinColor, lineWidth: PV.Border.thin))
    }
}

// MARK: - Card container

struct PVCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PV.Colors.surface, in: RoundedRectangle(cornerRadius: PV.Radius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: PV.Radius.medium)
                    .strokeBorder(PV.Border.thinColor, lineWidth: PV.Border.thin)
            )
    }
}

// MARK: - Shortcut Row with inline recorder

struct ShortcutRow: View {
    let label: String
    let icon: String
    let action: HotkeyAction

    @State private var isRecording = false
    @State private var displayString: String = ""
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(PV.Colors.textSecondary)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(PV.Colors.textPrimary)
            Spacer()

            if isRecording {
                Text("Press shortcut…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PV.Gradients.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(PV.Gradients.accentSolid.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(PV.Gradients.accentSolid.opacity(0.3), lineWidth: 0.5))

                PVTextButton("Cancel") { stopRecording() }
            } else {
                Text(displayString)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(PV.Colors.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(PV.Colors.surfaceHigh, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(PV.Border.thinColor, lineWidth: PV.Border.thin))

                PVTextButton("Change") { startRecording() }
            }
        }
        .padding(.vertical, 6)
        .onAppear {
            displayString = currentShortcut.displayString
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var currentShortcut: KeyboardShortcut {
        switch action {
        case .screenshot: return ShortcutStore.shared.screenshot
        case .gifRecording: return ShortcutStore.shared.gifRecording
        case .diff: return ShortcutStore.shared.diff
        }
    }

    private func startRecording() {
        isRecording = true
        NotificationCenter.default.post(name: .shortcutRecordingStarted, object: nil)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = Int(event.keyCode)
            if keyCode == 53 { stopRecording(); return nil }

            let flags = event.modifierFlags
            let shift = flags.contains(.shift)
            let command = flags.contains(.command)
            let control = flags.contains(.control)
            let option = flags.contains(.option)

            guard shift || command || control || option else { return event }

            let shortcut = KeyboardShortcut(
                keyCode: keyCode, shift: shift, command: command, control: control, option: option
            )

            switch action {
            case .screenshot: ShortcutStore.shared.screenshot = shortcut
            case .gifRecording: ShortcutStore.shared.gifRecording = shortcut
            case .diff: ShortcutStore.shared.diff = shortcut
            }

            displayString = shortcut.displayString
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isRecording = false
        NotificationCenter.default.post(name: .shortcutRecordingStopped, object: nil)
    }
}
