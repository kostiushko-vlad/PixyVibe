import Cocoa
import SwiftUI

class ToastNotification {
    private static var currentWindow: NSWindow?

    static func show(_ message: String, duration: TimeInterval = 2.0) {
        DispatchQueue.main.async {
            // Dismiss any existing toast
            currentWindow?.orderOut(nil)
            currentWindow = nil

            guard let screen = NSScreen.main else { return }

            let toastView = ToastView(message: message)
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

            window.alphaValue = 0
            window.orderFrontRegardless()

            currentWindow = window

            // Fade in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                window.animator().alphaValue = 1
            })

            // Fade out after duration
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.3
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

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
    }
}
