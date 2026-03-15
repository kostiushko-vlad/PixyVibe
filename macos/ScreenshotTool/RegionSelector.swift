import Cocoa

class RegionSelectorView: NSView {
    var mode: OverlayMode = .normal
    var onRegionSelected: ((CGRect) -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?

    private var startPoint: NSPoint?
    private var currentRect: NSRect?
    private var hintText: String = "Select a region — drag to capture"
    private var cursorTrackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = cursorTrackingArea {
            removeTrackingArea(existing)
        }
        cursorTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(cursorTrackingArea!)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    func updateHint(for captureMode: CaptureMode) {
        hintText = "Drag to select region for \(captureMode.label)"
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)

        let x = min(start.x, current.x)
        let y = min(start.y, current.y)
        let w = abs(current.x - start.x)
        let h = abs(current.y - start.y)

        currentRect = NSRect(x: x, y: y, width: w, height: h)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let rect = currentRect, rect.width > 10, rect.height > 10 else {
            startPoint = nil
            currentRect = nil
            needsDisplay = true
            return
        }
        onRegionSelected?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Semi-transparent dark overlay
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

        if let rect = currentRect {
            // Clear the selected region
            NSColor.clear.setFill()
            rect.fill(using: .copy)

            // White border
            NSColor.white.setStroke()
            let borderPath = NSBezierPath(rect: rect)
            borderPath.lineWidth = 2
            borderPath.stroke()

            // Dimensions label
            let labelText = "\(Int(rect.width)) × \(Int(rect.height))"
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                .backgroundColor: NSColor.black.withAlphaComponent(0.7)
            ]
            let labelSize = (labelText as NSString).size(withAttributes: attrs)
            let labelOrigin = NSPoint(
                x: rect.midX - labelSize.width / 2,
                y: rect.minY - labelSize.height - 6
            )
            (labelText as NSString).draw(at: labelOrigin, withAttributes: attrs)
        }
    }
}

// Keep for backward compat, no longer used in overlay
enum RegionAction {
    case screenshot
    case gif
    case diffBefore
    case diffAfter
}
