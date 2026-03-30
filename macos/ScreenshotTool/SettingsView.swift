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

    var body: some View {
        TabView {
            shortcutsTab
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            captureTab
                .tabItem {
                    Label("Capture", systemImage: "camera")
                }

            outputTab
                .tabItem {
                    Label("Output", systemImage: "folder")
                }
        }
        .frame(width: 480, height: 420)
    }

    private var shortcutsTab: some View {
        Form {
            Section("Keyboard Shortcuts") {
                ShortcutRow(label: "Screenshot", action: .screenshot)
                ShortcutRow(label: "Record GIF", action: .gifRecording)
                ShortcutRow(label: "Before/After Diff", action: .diff)
            }

            Section {
                Text("Click a shortcut and press your desired key combination to change it.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Button("Reset to Defaults") {
                    ShortcutStore.shared.screenshot = .defaultScreenshot
                    ShortcutStore.shared.gifRecording = .defaultGifRecording
                    ShortcutStore.shared.diff = .defaultDiff
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var captureTab: some View {
        Form {
            Section("GIF Recording") {
                sliderRow("Frame rate", value: $gifFPS, range: 5...30, step: 1, unit: "fps")
                sliderRow("Max duration", value: $gifMaxDuration, range: 5...120, step: 5, unit: "s")
            }

            Section("Image Processing") {
                sliderRow("Max width", value: $imageMaxWidth, range: 640...3840, step: 128, unit: "px")
                sliderRow("JPEG quality", value: $jpegQuality, range: 50...100, step: 5, unit: "%")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var outputTab: some View {
        Form {
            Section("Save Location") {
                HStack {
                    Text(saveLocation)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose...") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK, let url = panel.url {
                            saveLocation = url.path
                        }
                    }
                }
            }

            Section("Cleanup") {
                Toggle("Auto-delete old captures", isOn: $autoCleanup)
                if autoCleanup {
                    Stepper("Keep for \(cleanupDays) days", value: $cleanupDays, in: 1...365)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func sliderRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int, unit: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 100, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int(($0 / Double(step)).rounded()) * step }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound)
            )
            Text("\(value.wrappedValue)\(unit)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
    }
}

// MARK: - Shortcut Row with inline recorder

struct ShortcutRow: View {
    let label: String
    let action: HotkeyAction

    @State private var isRecording = false
    @State private var displayString: String = ""
    @State private var eventMonitor: Any?

    var body: some View {
        HStack {
            Text(label)
            Spacer()

            if isRecording {
                Text("Press shortcut…")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

                Button("Cancel") {
                    stopRecording()
                }
                .font(.system(size: 11))
            } else {
                Text(displayString)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

                Button("Change") {
                    startRecording()
                }
                .font(.system(size: 11))
            }
        }
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

            // ESC cancels
            if keyCode == 53 {
                stopRecording()
                return nil // consume the event
            }

            let flags = event.modifierFlags
            let shift = flags.contains(.shift)
            let command = flags.contains(.command)
            let control = flags.contains(.control)
            let option = flags.contains(.option)

            // Require at least one modifier
            guard shift || command || control || option else { return event }

            let shortcut = KeyboardShortcut(
                keyCode: keyCode,
                shift: shift,
                command: command,
                control: control,
                option: option
            )

            // Save
            switch action {
            case .screenshot: ShortcutStore.shared.screenshot = shortcut
            case .gifRecording: ShortcutStore.shared.gifRecording = shortcut
            case .diff: ShortcutStore.shared.diff = shortcut
            }

            displayString = shortcut.displayString
            stopRecording()
            return nil // consume the event
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
