import Cocoa
import SwiftUI

class ActionToolbarWindow: NSPanel {
    init(
        region: CGRect,
        mode: OverlayMode,
        onScreenshot: @escaping () -> Void,
        onGif: @escaping () -> Void,
        onDiffBefore: @escaping () -> Void,
        onDiffAfter: @escaping () -> Void
    ) {
        let toolbarWidth: CGFloat = mode == .diffAfter ? 200 : 340
        let toolbarHeight: CGFloat = 50

        // Position below the selection
        let toolbarFrame = NSRect(
            x: region.midX - toolbarWidth / 2,
            y: region.minY - toolbarHeight - 12,
            width: toolbarWidth,
            height: toolbarHeight
        )

        super.init(
            contentRect: toolbarFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar + 2
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true

        let toolbar = ActionToolbarView(
            mode: mode,
            onScreenshot: onScreenshot,
            onGif: onGif,
            onDiffBefore: onDiffBefore,
            onDiffAfter: onDiffAfter
        )
        self.contentView = NSHostingView(rootView: toolbar)
    }
}

struct ActionToolbarView: View {
    let mode: OverlayMode
    let onScreenshot: () -> Void
    let onGif: () -> Void
    let onDiffBefore: () -> Void
    let onDiffAfter: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if mode == .diffAfter {
                Button(action: onDiffAfter) {
                    Label("Capture AFTER", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(PVToolbarButtonStyle())
                .keyboardShortcut(.return, modifiers: [])
            } else {
                Button(action: onScreenshot) {
                    Label("Screenshot", systemImage: "camera.fill")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(PVToolbarButtonStyle())
                .keyboardShortcut("s", modifiers: [])

                Button(action: onGif) {
                    Label("Record GIF", systemImage: "record.circle")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(PVToolbarButtonStyle())
                .keyboardShortcut("g", modifiers: [])

                Button(action: onDiffBefore) {
                    Label("Diff", systemImage: "square.split.2x1")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(PVToolbarButtonStyle())
                .keyboardShortcut("d", modifiers: [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .pvGlass(cornerRadius: PV.Radius.medium)
    }
}

struct PVToolbarButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.white.opacity(0.15) : Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isHovered ? PV.Border.focusColor : Color.clear, lineWidth: PV.Border.thin)
            )
            .foregroundColor(PV.Colors.textPrimary)
            .scaleEffect(configuration.isPressed ? 0.96 : (isHovered ? 1.02 : 1.0))
            .animation(PV.Anim.hover, value: isHovered)
            .animation(PV.Anim.hover, value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

// Keep backward compatibility alias
typealias ToolbarButtonStyle = PVToolbarButtonStyle
