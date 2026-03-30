import Cocoa
import SwiftUI

class ToastNotification {
    private static var currentWindow: NSWindow?

    static func show(_ message: String, icon: String? = nil, duration: TimeInterval = 2.0) {
        DispatchQueue.main.async {
            // Dismiss any existing toast
            currentWindow?.orderOut(nil)
            currentWindow = nil

            guard let screen = NSScreen.main else { return }

            let toastView = ToastView(message: message, icon: icon)
            let hostingView = NSHostingView(rootView: toastView)
            hostingView.frame = NSRect(x: 0, y: 0, width: 300, height: 50)

            let contentSize = hostingView.fittingSize
            let windowFrame = NSRect(
                x: screen.visibleFrame.maxX - contentSize.width - 20,
                y: screen.visibleFrame.maxY - contentSize.height - 20,
                width: contentSize.width,
                height: contentSize.height
            )

            let window = NSWindow(
                contentRect: windowFrame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .floating
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView = hostingView
            window.hasShadow = true
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            window.isReleasedWhenClosed = false

            // Start offscreen to the right for slide-in
            let startFrame = NSRect(
                x: windowFrame.origin.x + 30,
                y: windowFrame.origin.y,
                width: windowFrame.width,
                height: windowFrame.height
            )
            window.setFrame(startFrame, display: false)
            window.alphaValue = 0
            window.orderFrontRegardless()

            currentWindow = window

            // Slide in from right + fade in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(windowFrame, display: true)
                window.animator().alphaValue = 1
            })

            // Slide out + fade out after duration
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                let exitFrame = NSRect(
                    x: windowFrame.origin.x + 40,
                    y: windowFrame.origin.y,
                    width: windowFrame.width,
                    height: windowFrame.height
                )
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.3
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    window.animator().setFrame(exitFrame, display: true)
                    window.animator().alphaValue = 0
                }, completionHandler: {
                    window.orderOut(nil)
                    if currentWindow === window {
                        currentWindow = nil
                    }
                })
            }
        }
    }
}

struct ToastView: View {
    let message: String
    let icon: String?

    var body: some View {
        HStack(spacing: 0) {
            // Accent gradient line on left edge
            PV.Gradients.accent
                .frame(width: 3, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
                .padding(.leading, 10)
                .padding(.trailing, 8)

            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PV.Gradients.accent)
                    .padding(.trailing, 6)
            }

            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(PV.Colors.textPrimary)
                .padding(.trailing, 16)
        }
        .padding(.vertical, 12)
        .background(PV.Colors.surface, in: RoundedRectangle(cornerRadius: PV.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: PV.Radius.medium)
                .strokeBorder(PV.Border.thinColor, lineWidth: PV.Border.thin)
        )
    }
}
