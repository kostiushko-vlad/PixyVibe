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

// MARK: - Recording Pill (timer + stop button)

class RecordingPill: NSPanel {
    var onStop: (() -> Void)?
    private var startTime: Date = Date()
    private var timer: Timer?
    private var hostingView: NSHostingView<RecordingPillView>!
    private var elapsedSeconds: Int = 0
    private var borderWindow: RecordingBorderWindow?

    init(region: CGRect) {
        let pillWidth: CGFloat = 160
        let pillHeight: CGFloat = 40
        let pillFrame = NSRect(
            x: region.midX - pillWidth / 2,
            y: region.maxY + 12,
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

        let pillView = RecordingPillView(elapsed: 0) { [weak self] in
            self?.onStop?()
        }
        hostingView = NSHostingView(rootView: pillView)
        self.contentView = hostingView

        // Create border overlay for the recording region
        borderWindow = RecordingBorderWindow(region: region)
    }

    func show() {
        startTime = Date()
        elapsedSeconds = 0
        makeKeyAndOrderFront(nil)
        borderWindow?.orderFront(nil)

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.elapsedSeconds = Int(Date().timeIntervalSince(self.startTime))
            let pillView = RecordingPillView(elapsed: self.elapsedSeconds) { [weak self] in
                self?.onStop?()
            }
            self.hostingView.rootView = pillView
        }
    }

    override func close() {
        timer?.invalidate()
        timer = nil
        borderWindow?.orderOut(nil)
        borderWindow = nil
        super.close()
    }
}

// MARK: - Pill SwiftUI View

struct RecordingPillView: View {
    let elapsed: Int
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)

            Text("REC \(formatTime(elapsed))")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)

            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .padding(4)
            .background(Color.white.opacity(0.2), in: Circle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.8), in: Capsule())
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
