import Cocoa

/// Shows a brief expanding ring animation at mouse click positions during GIF recording.
class ClickAnimator {
    private var monitor: Any?
    private var activeRings: [ClickRingWindow] = []

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.showRing(at: NSEvent.mouseLocation)
        }
    }

    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        for ring in activeRings {
            ring.orderOut(nil)
        }
        activeRings.removeAll()
    }

    private func showRing(at screenPoint: NSPoint) {
        let ring = ClickRingWindow(center: screenPoint)
        ring.orderFrontRegardless()
        activeRings.append(ring)

        ring.animate { [weak self] in
            ring.orderOut(nil)
            self?.activeRings.removeAll { $0 === ring }
        }
    }
}

class ClickRingWindow: NSPanel {
    private static let ringSize: CGFloat = 40
    private let ringView: ClickRingView

    init(center: NSPoint) {
        let size = Self.ringSize
        let frame = NSRect(
            x: center.x - size / 2,
            y: center.y - size / 2,
            width: size,
            height: size
        )

        ringView = ClickRingView(frame: NSRect(origin: .zero, size: frame.size))

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver - 2
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = true
        self.hasShadow = false
        self.isReleasedWhenClosed = false
        self.contentView = ringView
    }

    func animate(completion: @escaping () -> Void) {
        // Expand + fade out over 0.35s
        let duration = 0.35
        let expandScale: CGFloat = 1.8

        let startFrame = frame
        let expandedSize = NSSize(
            width: startFrame.width * expandScale,
            height: startFrame.height * expandScale
        )
        let expandedOrigin = NSPoint(
            x: startFrame.midX - expandedSize.width / 2,
            y: startFrame.midY - expandedSize.height / 2
        )
        let expandedFrame = NSRect(origin: expandedOrigin, size: expandedSize)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(expandedFrame, display: true)
            self.animator().alphaValue = 0
        }, completionHandler: completion)
    }
}

class ClickRingView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let inset: CGFloat = 2
        let rect = bounds.insetBy(dx: inset, dy: inset)

        // Gradient ring
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = 2

        if let gradient = PV.Gradients.cgAccent() {
            path.strokeWithGradient(gradient, lineWidth: 2, in: ctx)
        } else {
            NSColor.white.withAlphaComponent(0.7).setStroke()
            path.stroke()
        }

        // Subtle gradient-tinted fill
        NSColor(hex: 0x10B981, alpha: 0.1).setFill()
        path.fill()
    }
}
