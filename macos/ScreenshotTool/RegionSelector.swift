import Cocoa

class RegionSelectorView: NSView {
    var mode: OverlayMode = .normal
    var onRegionSelected: ((CGRect) -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?

    private var startPoint: NSPoint?
    private var currentRect: NSRect?
    private var hintText: String = "Select a region — drag to capture"
    private var cursorTrackingArea: NSTrackingArea?
    private var isPreselected = false
    private var confirmButtonRect: NSRect = .zero

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

    /// Pre-select a region (used for diff-after to show the previous selection).
    func preselect(rect localRect: CGRect) {
        currentRect = localRect
        isPreselected = true
        needsDisplay = true
    }

    func updateHint(for captureMode: CaptureMode) {
        hintText = "Drag to select region for \(captureMode.label)"
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Check if clicking the confirm button
        if isPreselected && !confirmButtonRect.isEmpty && confirmButtonRect.contains(point) {
            if let rect = currentRect, rect.width > 10, rect.height > 10 {
                onRegionSelected?(rect)
                return
            }
        }

        // Start new selection — clears preselection
        startPoint = point
        currentRect = nil
        isPreselected = false
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
        guard !isPreselected else { return }
        guard let rect = currentRect, rect.width > 10, rect.height > 10 else {
            startPoint = nil
            currentRect = nil
            needsDisplay = true
            return
        }
        onRegionSelected?(rect)
    }

    override func keyDown(with event: NSEvent) {
        // Enter confirms a pre-selected region
        if event.keyCode == 36, let rect = currentRect, rect.width > 10, rect.height > 10 {
            onRegionSelected?(rect)
            return
        }
        if onKeyDown?(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Blue-tinted semi-transparent overlay
        NSColor(srgbRed: 0.05, green: 0.06, blue: 0.08, alpha: 0.45).setFill()
        bounds.fill()

        guard let rect = currentRect else { return }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Clear the selected region
        NSColor.clear.setFill()
        rect.fill(using: .copy)

        // Gradient selection border
        if let gradient = PV.Gradients.cgAccent() {
            let borderPath = NSBezierPath(rect: rect)
            borderPath.strokeWithGradient(gradient, lineWidth: 2, in: ctx)
        } else {
            NSColor.white.setStroke()
            let borderPath = NSBezierPath(rect: rect)
            borderPath.lineWidth = 2
            borderPath.stroke()
        }

        // Dimensions label — styled pill
        let labelText = "\(Int(rect.width)) × \(Int(rect.height))"
        let dimAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: PV.Colors.nsTextPrimary,
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
        ]
        let labelSize = (labelText as NSString).size(withAttributes: dimAttrs)
        let pillPadH: CGFloat = 8
        let pillPadV: CGFloat = 3
        let pillRect = NSRect(
            x: rect.midX - (labelSize.width + pillPadH * 2) / 2,
            y: rect.minY - labelSize.height - pillPadV * 2 - 6,
            width: labelSize.width + pillPadH * 2,
            height: labelSize.height + pillPadV * 2
        )
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6)
        PV.Colors.nsSurface.setFill()
        pillPath.fill()
        PV.Border.nsThinColor.setStroke()
        pillPath.lineWidth = 0.5
        pillPath.stroke()

        let labelOrigin = NSPoint(
            x: pillRect.midX - labelSize.width / 2,
            y: pillRect.midY - labelSize.height / 2
        )
        (labelText as NSString).draw(at: labelOrigin, withAttributes: dimAttrs)

        // Draw confirm button when pre-selected (diff-after mode)
        if isPreselected {
            drawConfirmButton(below: rect, ctx: ctx)
        }
    }

    private func drawConfirmButton(below rect: NSRect, ctx: CGContext) {
        let buttonText = "  Capture After  "
        let hintText = "or press Enter  ·  drag to re-select"

        let buttonFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let hintFont = NSFont.systemFont(ofSize: 11)

        let buttonAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: buttonFont,
        ]
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: PV.Colors.nsTextSecondary,
            .font: hintFont,
        ]

        let buttonSize = (buttonText as NSString).size(withAttributes: buttonAttrs)
        let hintSize = (hintText as NSString).size(withAttributes: hintAttrs)

        let buttonPadH: CGFloat = 16
        let buttonPadV: CGFloat = 8
        let totalHeight = buttonSize.height + buttonPadV * 2
        let gap: CGFloat = 12

        let totalWidth = buttonSize.width + buttonPadH * 2 + gap + hintSize.width
        let barX = rect.midX - totalWidth / 2
        let barY = rect.minY - totalHeight - 30

        // Confirm button with gradient fill
        let btnRect = NSRect(
            x: barX,
            y: barY,
            width: buttonSize.width + buttonPadH * 2,
            height: totalHeight
        )
        let btnPath = NSBezierPath(roundedRect: btnRect, xRadius: 8, yRadius: 8)

        if let gradient = PV.Gradients.cgAccent() {
            ctx.saveGState()
            ctx.addPath(btnPath.cgPathForStroke())
            ctx.clip()
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: btnRect.minX, y: btnRect.midY),
                end: CGPoint(x: btnRect.maxX, y: btnRect.midY),
                options: []
            )
            ctx.restoreGState()
        } else {
            NSColor.controlAccentColor.setFill()
            btnPath.fill()
        }

        // Button text
        let btnTextOrigin = NSPoint(
            x: btnRect.midX - buttonSize.width / 2,
            y: btnRect.midY - buttonSize.height / 2
        )
        (buttonText as NSString).draw(at: btnTextOrigin, withAttributes: buttonAttrs)

        // Store button rect for click detection
        confirmButtonRect = btnRect

        // Hint text
        let hintOrigin = NSPoint(
            x: btnRect.maxX + gap,
            y: btnRect.midY - hintSize.height / 2
        )
        (hintText as NSString).draw(at: hintOrigin, withAttributes: hintAttrs)
    }
}

enum RegionAction {
    case screenshot
    case gif
    case diffBefore
    case diffAfter
}
