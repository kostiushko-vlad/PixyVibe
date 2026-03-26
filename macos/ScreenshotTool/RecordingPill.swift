import Cocoa
import SwiftUI

// MARK: - Recording Border (highlights the captured region)

class RecordingBorderWindow: NSPanel {
    private let borderWidth: CGFloat = 1

    init(region: CGRect) {
        // Expand frame slightly to fit the border outside the region
        let frame = region.insetBy(dx: -borderWidth, dy: -borderWidth)

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver - 1
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = true
        self.hasShadow = false
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let borderView = RecordingBorderView(borderWidth: borderWidth)
        borderView.frame = NSRect(origin: .zero, size: frame.size)
        self.contentView = borderView
    }
}

class RecordingBorderView: NSView {
    private let borderWidth: CGFloat

    init(borderWidth: CGFloat) {
        self.borderWidth = borderWidth
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let inset = bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
        let path = NSBezierPath(roundedRect: inset, xRadius: 3, yRadius: 3)
        path.lineWidth = borderWidth
        path.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.white.withAlphaComponent(0.8).setStroke()
        path.stroke()
    }
}

enum RecordingPillPhase {
    case ready
    case recording
}

// MARK: - Recording Pill (timer + stop button)

class RecordingPill: NSPanel {
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?
    private var phase: RecordingPillPhase = .ready
    private var startTime: Date = Date()
    private var timer: Timer?
    private var hostingView: NSHostingView<RecordingPillView>!
    private var elapsedSeconds: Int = 0
    private var borderWindow: RecordingBorderWindow?
    private var escMonitor: Any?
    private var regionSize: NSSize

    init(region: CGRect) {
        self.regionSize = region.size
        let pillWidth: CGFloat = 200
        let pillHeight: CGFloat = 40
        // Position above region, but flip below if it would go off-screen
        let screenMaxY = NSScreen.main?.frame.maxY ?? region.maxY + 100
        let aboveY = region.maxY + 12
        let belowY = region.minY - pillHeight - 12
        let pillY = (aboveY + pillHeight > screenMaxY) ? belowY : aboveY
        let pillFrame = NSRect(
            x: region.midX - pillWidth / 2,
            y: pillY,
            width: pillWidth,
            height: pillHeight
        )

        super.init(
            contentRect: pillFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isReleasedWhenClosed = false

        let pillView = RecordingPillView(
            phase: .ready,
            elapsed: 0,
            regionSize: regionSize,
            onStart: { [weak self] in self?.beginRecording() },
            onStop: { [weak self] in self?.onStop?() }
        )
        hostingView = NSHostingView(rootView: pillView)
        self.contentView = hostingView

        // Create border overlay for the recording region
        borderWindow = RecordingBorderWindow(region: region)
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            if phase == .ready { onCancel?() } else { onStop?() }
            return
        }
        super.keyDown(with: event)
    }

    func show() {
        phase = .ready
        makeKeyAndOrderFront(nil)
        borderWindow?.orderFront(nil)

        // Monitor ESC key globally (pill is non-activating so keyDown may not fire)
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                if self?.phase == .ready { self?.onCancel?() } else { self?.onStop?() }
                return nil
            }
            return event
        }
    }

    private func beginRecording() {
        phase = .recording
        startTime = Date()
        elapsedSeconds = 0
        onStart?()

        let pillView = RecordingPillView(
            phase: .recording,
            elapsed: 0,
            regionSize: nil,
            onStart: {},
            onStop: { [weak self] in self?.onStop?() }
        )
        hostingView.rootView = pillView

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.elapsedSeconds = Int(Date().timeIntervalSince(self.startTime))
            let pillView = RecordingPillView(
                phase: .recording,
                elapsed: self.elapsedSeconds,
                regionSize: nil,
                onStart: {},
                onStop: { [weak self] in self?.onStop?() }
            )
            self.hostingView.rootView = pillView
        }
    }

    override func close() {
        timer?.invalidate()
        timer = nil
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
        borderWindow?.orderOut(nil)
        borderWindow = nil
        super.close()
    }
}

// MARK: - Pill SwiftUI View

struct RecordingPillView: View {
    let phase: RecordingPillPhase
    let elapsed: Int
    let regionSize: NSSize?
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            switch phase {
            case .ready:
                if let size = regionSize {
                    Text("\(Int(size.width))×\(Int(size.height))")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
                Button(action: onStart) {
                    HStack(spacing: 4) {
                        Image(systemName: "record.circle")
                            .font(.system(size: 11))
                        Text("Start")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

            case .recording:
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)

                Text("REC \(formatTime(elapsed))")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)

                Button(action: onStop) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11))
                        Text("Stop")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.8), in: Capsule())
        .fixedSize()
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
