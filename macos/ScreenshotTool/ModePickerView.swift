import Cocoa
import SwiftUI

enum CaptureMode: Int, CaseIterable {
    case screenshot = 0
    case gif = 1
    case diff = 2

    var label: String {
        switch self {
        case .screenshot: return "Screenshot"
        case .gif: return "Record GIF"
        case .diff: return "Diff"
        }
    }

    var icon: String {
        switch self {
        case .screenshot: return "camera.viewfinder"
        case .gif: return "record.circle"
        case .diff: return "square.split.2x1"
        }
    }

    var shortcutHint: String {
        switch self {
        case .screenshot: return "S"
        case .gif: return "G"
        case .diff: return "D"
        }
    }
}

class ModePickerPanel: NSPanel {
    var onModeSelected: ((CaptureMode) -> Void)?
    var onCancel: (() -> Void)?
    private var hostingView: NSHostingView<ModePickerContent>!
    private var selectedMode: CaptureMode = .screenshot

    init() {
        let panelWidth: CGFloat = 360
        let panelHeight: CGFloat = 72

        guard let screen = NSScreen.main else {
            super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            return
        }

        let panelFrame = NSRect(
            x: screen.frame.midX - panelWidth / 2,
            y: screen.frame.minY + 120,
            width: panelWidth,
            height: panelHeight
        )

        super.init(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver + 1
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true

        updateContent()
    }

    private func updateContent() {
        let content = ModePickerContent(
            selectedMode: selectedMode,
            onSelect: { [weak self] mode in
                self?.selectedMode = mode
                self?.updateContent()
                self?.onModeSelected?(mode)
            },
            onCancel: { [weak self] in
                self?.onCancel?()
            }
        )
        if hostingView == nil {
            hostingView = NSHostingView(rootView: content)
            self.contentView = hostingView
        } else {
            hostingView.rootView = content
        }
    }

    func selectMode(_ mode: CaptureMode) {
        selectedMode = mode
        updateContent()
        onModeSelected?(mode)
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // ESC
            onCancel?()
            return true
        case 1: // S
            selectMode(.screenshot)
            return true
        case 5: // G
            selectMode(.gif)
            return true
        case 2: // D
            selectMode(.diff)
            return true
        default:
            return false
        }
    }
}

struct ModePickerContent: View {
    let selectedMode: CaptureMode
    let onSelect: (CaptureMode) -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CaptureMode.allCases, id: \.rawValue) { mode in
                modeButton(mode)
                if mode != CaptureMode.allCases.last {
                    Divider()
                        .frame(height: 28)
                        .opacity(0.3)
                }
            }

            Divider()
                .frame(height: 28)
                .opacity(0.3)
                .padding(.horizontal, 4)

            // Close button
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func modeButton(_ mode: CaptureMode) -> some View {
        let isSelected = mode == selectedMode
        return Button(action: { onSelect(mode) }) {
            VStack(spacing: 3) {
                Image(systemName: mode.icon)
                    .font(.system(size: 16))
                Text(mode.label)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(width: 84, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
