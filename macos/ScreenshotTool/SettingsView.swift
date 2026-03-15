import SwiftUI

struct SettingsView: View {
    @AppStorage("hotkeyDisplay") private var hotkeyDisplay = "Shift+Cmd+6"
    @AppStorage("saveLocation") private var saveLocation = "~/.screenshottool"
    @AppStorage("gifFPS") private var gifFPS = 10
    @AppStorage("gifMaxDuration") private var gifMaxDuration = 30
    @AppStorage("imageMaxWidth") private var imageMaxWidth = 1280
    @AppStorage("jpegQuality") private var jpegQuality = 85
    @AppStorage("autoCleanup") private var autoCleanup = true
    @AppStorage("cleanupDays") private var cleanupDays = 30

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
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
        .frame(width: 450, height: 300)
    }

    private var generalTab: some View {
        Form {
            Section("Hotkey") {
                HStack {
                    Text("Capture shortcut:")
                    Spacer()
                    Text(hotkeyDisplay)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: .constant(false))
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var captureTab: some View {
        Form {
            Section("GIF Recording") {
                Stepper("Frame rate: \(gifFPS) fps", value: $gifFPS, in: 5...30)
                Stepper("Max duration: \(gifMaxDuration)s", value: $gifMaxDuration, in: 5...120, step: 5)
            }

            Section("Image Processing") {
                Stepper("Max width: \(imageMaxWidth)px", value: $imageMaxWidth, in: 640...3840, step: 128)
                Stepper("JPEG quality: \(jpegQuality)%", value: $jpegQuality, in: 50...100, step: 5)
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
}
