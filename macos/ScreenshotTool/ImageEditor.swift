import Cocoa
import SwiftUI

// MARK: - Editor Window

class ImageEditorWindow {
    private var window: NSWindow?

    func open(imageData: Data, filePath: String, isGif: Bool, onSave: @escaping (Data) -> Void, onRemove: (() -> Void)? = nil) {
        window?.close()

        let closeAction: () -> Void = { [weak self] in
            self?.window?.close()
            self?.window = nil
        }

        let content: any View
        if isGif {
            content = GifPlayerView(imageData: imageData, onClose: closeAction)
        } else {
            content = StaticImageEditorView(imageData: imageData, filePath: filePath, onSave: onSave, onRemove: {
                closeAction()
                onRemove?()
            }, onClose: closeAction)
        }

        // Size window to fit the image, capped to screen percentage
        var winWidth: CGFloat = 320
        var winHeight: CGFloat = 400
        if let screen = NSScreen.main?.visibleFrame {
            if let img = NSImage(data: imageData) {
                let isPortrait = img.size.height > img.size.width * 1.3
                let maxW = isPortrait ? min(screen.width * 0.5625, 787) : screen.width * 0.7
                let maxH = isPortrait ? min(screen.height * 1.0, 1125) : screen.height * 0.7
                let controlsHeight: CGFloat = 50
                let scale = min(maxW / img.size.width, (maxH - controlsHeight) / img.size.height, 1.0)
                let scaledW = img.size.width * scale
                let scaledH = img.size.height * scale + controlsHeight
                winWidth = max(280, min(scaledW, maxW))
                winHeight = max(250, min(scaledH, maxH))
            } else {
                // NSImage failed to load — use small defaults
                winWidth = 320
                winHeight = 400
            }
        }

        let hostingView = NSHostingView(rootView: AnyView(content))
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: winWidth, height: winHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = isGif ? "GIF Player" : "Edit Screenshot"
        win.contentView = hostingView
        // Force window to calculated size — NSHostingView may try to expand to image dimensions
        win.setContentSize(NSSize(width: winWidth, height: winHeight))
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }
}

// MARK: - Drawing Tool Types

enum DrawingTool: String, CaseIterable {
    case hand = "Hand"
    case pen = "Pen"
    case arrow = "Arrow"
    case rectangle = "Rectangle"
    case text = "Text"

    var icon: String {
        switch self {
        case .hand: return "hand.draw"
        case .pen: return "pencil.tip"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .text: return "textformat"
        }
    }
}

struct DrawingElement {
    let tool: DrawingTool
    let color: NSColor
    let lineWidth: CGFloat
    var points: [CGPoint]
    var text: String?
}

// MARK: - Inline Color Picker

struct InlineColorPicker: View {
    @Binding var selectedColor: Color
    private let presets: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .white, .black]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(presets, id: \.self) { color in
                Circle()
                    .fill(color)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.gray.opacity(0.25), lineWidth: 0.5)
                    )
                    .scaleEffect(selectedColor == color ? 1.25 : 1.0)
                    .shadow(color: selectedColor == color ? color.opacity(0.5) : .clear, radius: 3)
                    .animation(.easeInOut(duration: 0.15), value: selectedColor == color)
                    .onTapGesture { selectedColor = color }
            }
        }
    }
}

// MARK: - Static Image Editor

struct StaticImageEditorView: View {
    let imageData: Data
    let filePath: String
    let onSave: (Data) -> Void
    let onRemove: () -> Void
    let onClose: () -> Void

    @State private var selectedTool: DrawingTool = .pen
    @State private var selectedColor: Color = .red
    @State private var lineWidth: CGFloat = 3
    @State private var elements: [DrawingElement] = []
    @State private var undoStack: [[DrawingElement]] = []
    @State private var redoStack: [[DrawingElement]] = []

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 2) {
                // Tool buttons in a pill group
                HStack(spacing: 0) {
                    ForEach(DrawingTool.allCases, id: \.self) { tool in
                        Button(action: { selectedTool = tool }) {
                            Image(systemName: tool.icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(selectedTool == tool ? .white : PV.Colors.textSecondary)
                                .frame(width: 30, height: 26)
                                .background(selectedTool == tool ? PV.Gradients.accent : LinearGradient(colors: [.clear], startPoint: .leading, endPoint: .trailing))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(tool.rawValue)
                    }
                }
                .background(PV.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer().frame(width: 8)

                InlineColorPicker(selectedColor: $selectedColor)

                Spacer().frame(width: 8)

                // Size slider in subtle container
                Slider(value: $lineWidth, in: 1...10)
                    .frame(width: 60)
                    .controlSize(.mini)

                Spacer().frame(width: 8)

                // Undo/Redo pill
                HStack(spacing: 0) {
                    Button(action: {
                        guard !undoStack.isEmpty else { return }
                        redoStack.append(elements)
                        elements = undoStack.removeLast()
                    }) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(undoStack.isEmpty ? .secondary.opacity(0.3) : .secondary)
                            .frame(width: 28, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(undoStack.isEmpty)

                    Button(action: {
                        guard !redoStack.isEmpty else { return }
                        undoStack.append(elements)
                        elements = redoStack.removeLast()
                    }) {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(redoStack.isEmpty ? .secondary.opacity(0.3) : .secondary)
                            .frame(width: 28, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(redoStack.isEmpty)
                }
                .background(PV.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer()

                // Action buttons
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(PV.Colors.textSecondary)
                        .frame(width: 30, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete")

                Button(action: { saveImage() }) {
                    Text("Save")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 26)
                        .background(PV.Gradients.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)

            // Canvas
            DrawingCanvasView(
                imageData: imageData,
                elements: $elements,
                undoStack: $undoStack,
                redoStack: $redoStack,
                selectedTool: selectedTool,
                selectedColor: selectedColor,
                lineWidth: lineWidth
            )
        }
    }

    private func saveImage() {
        guard let nsImage = NSImage(data: imageData) else { return }
        let size = nsImage.size

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!

        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx

        nsImage.draw(in: NSRect(origin: .zero, size: size))

        for element in elements {
            let color = element.color
            color.setStroke()
            color.setFill()

            switch element.tool {
            case .pen:
                let path = NSBezierPath()
                path.lineWidth = element.lineWidth
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                for (i, pt) in element.points.enumerated() {
                    if i == 0 { path.move(to: pt) } else { path.line(to: pt) }
                }
                path.stroke()

            case .arrow:
                guard element.points.count >= 2 else { continue }
                let start = element.points[0]
                let end = element.points[1]
                let angle = atan2(end.y - start.y, end.x - start.x)
                let headLen: CGFloat = max(14, element.lineWidth * 4)
                let headAngle: CGFloat = .pi / 6
                let p1 = CGPoint(x: end.x - headLen * cos(angle - headAngle),
                                  y: end.y - headLen * sin(angle - headAngle))
                let p2 = CGPoint(x: end.x - headLen * cos(angle + headAngle),
                                  y: end.y - headLen * sin(angle + headAngle))
                let base = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
                let shaft = NSBezierPath()
                shaft.lineWidth = element.lineWidth
                shaft.lineCapStyle = .round
                shaft.move(to: start)
                shaft.line(to: base)
                shaft.stroke()
                let head = NSBezierPath()
                head.move(to: end)
                head.line(to: p1)
                head.line(to: p2)
                head.close()
                head.fill()

            case .rectangle:
                guard element.points.count >= 2 else { continue }
                let r = rectFrom(element.points[0], element.points[1])
                let path = NSBezierPath(rect: r)
                path.lineWidth = element.lineWidth
                path.stroke()

            case .text:
                guard let text = element.text, let pt = element.points.first else { continue }
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: color,
                    .font: NSFont.systemFont(ofSize: max(14, element.lineWidth * 5), weight: .semibold),
                ]
                let size = (text as NSString).boundingRect(with: NSSize(width: 600, height: 10000), options: [.usesLineFragmentOrigin], attributes: attrs)
                (text as NSString).draw(in: NSRect(origin: pt, size: size.size), withAttributes: attrs)

            case .hand:
                break
            }
        }

        NSGraphicsContext.restoreGraphicsState()
        guard let pngData = rep.representation(using: .png, properties: [:]) else { return }
        onSave(pngData)
        onClose()
    }
}

private func rectFrom(_ a: CGPoint, _ b: CGPoint) -> NSRect {
    NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
           width: abs(b.x - a.x), height: abs(b.y - a.y))
}

// MARK: - Drawing Canvas (NSView bridge)

struct DrawingCanvasView: NSViewRepresentable {
    let imageData: Data
    @Binding var elements: [DrawingElement]
    @Binding var undoStack: [[DrawingElement]]
    @Binding var redoStack: [[DrawingElement]]
    let selectedTool: DrawingTool
    let selectedColor: Color
    let lineWidth: CGFloat

    func makeNSView(context: Context) -> DrawingCanvasNSView {
        let view = DrawingCanvasNSView()
        view.image = NSImage(data: imageData)
        view.elements = elements
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: DrawingCanvasNSView, context: Context) {
        nsView.elements = elements
        nsView.selectedTool = selectedTool
        let newColor = NSColor(selectedColor)
        let colorChanged = nsView.selectedColor != newColor
        let sizeChanged = nsView.lineWidth != lineWidth
        nsView.selectedColor = newColor
        nsView.lineWidth = lineWidth
        if colorChanged || sizeChanged {
            nsView.applyStyleToActiveText()
        }
        nsView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    class Coordinator {
        var parent: DrawingCanvasView
        init(parent: DrawingCanvasView) { self.parent = parent }

        func addElement(_ element: DrawingElement) {
            parent.undoStack.append(parent.elements)
            parent.redoStack.removeAll()
            parent.elements.append(element)
        }

        func updateElement(at index: Int, _ element: DrawingElement) {
            guard index >= 0, index < parent.elements.count else { return }
            parent.elements[index] = element
        }

        /// Save a snapshot before a destructive edit (e.g. text commit that changes color/size).
        func saveSnapshot() {
            parent.undoStack.append(parent.elements)
            parent.redoStack.removeAll()
        }
    }
}

// MARK: - Drawing Canvas NSView

class DrawingCanvasNSView: NSView, NSTextViewDelegate {
    var image: NSImage?
    var elements: [DrawingElement] = []
    var selectedTool: DrawingTool = .pen
    var selectedColor: NSColor = .red
    var lineWidth: CGFloat = 3
    weak var coordinator: DrawingCanvasView.Coordinator?

    private var currentPoints: [CGPoint] = []
    private var isDragging = false

    // Text editing state
    private var activeTextContainer: NSView?
    private var activeTextView: NSTextView?
    private var textPlacementPoint: CGPoint = .zero
    private var editingTextIndex: Int? = nil
    private var blockNextClick = false

    // Text dragging state
    private var draggingTextIndex: Int? = nil
    private var dragOffset: CGPoint = .zero
    private var clickedTextIndex: Int? = nil  // tracks single-click vs double-click on text

    // Hand tool dragging state
    private var handDraggingIndex: Int? = nil
    private var handDragStartImg: CGPoint = .zero  // drag start in image coords
    private var handDragOriginalPoints: [CGPoint] = []  // original points before drag

    // Cursor tracking
    private var cursorTrackingArea: NSTrackingArea?

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    private var imageRect: NSRect {
        guard let image = image else { return bounds }
        let aspect = image.size.width / image.size.height
        let boundsAspect = bounds.width / bounds.height
        if aspect > boundsAspect {
            let w = bounds.width
            let h = w / aspect
            return NSRect(x: 0, y: (bounds.height - h) / 2, width: w, height: h)
        } else {
            let h = bounds.height
            let w = h * aspect
            return NSRect(x: (bounds.width - w) / 2, y: 0, width: w, height: h)
        }
    }

    private func toImageCoords(_ viewPoint: CGPoint) -> CGPoint {
        guard let image = image else { return viewPoint }
        let rect = imageRect
        let x = (viewPoint.x - rect.origin.x) / rect.width * image.size.width
        let y = (viewPoint.y - rect.origin.y) / rect.height * image.size.height
        return CGPoint(x: x, y: y)
    }

    private func toViewCoords(_ imagePoint: CGPoint) -> CGPoint {
        guard let image = image else { return imagePoint }
        let rect = imageRect
        let x = imagePoint.x / image.size.width * rect.width + rect.origin.x
        let y = imagePoint.y / image.size.height * rect.height + rect.origin.y
        return CGPoint(x: x, y: y)
    }

    private func fontSize() -> CGFloat {
        return max(14, lineWidth * 5)
    }

    // MARK: - Hit testing

    private func textElementRect(at index: Int) -> NSRect? {
        let element = elements[index]
        guard element.tool == .text, let text = element.text, let pt = element.points.first else { return nil }
        let vp = toViewCoords(pt)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(14, element.lineWidth * 5), weight: .semibold),
        ]
        let size = (text as NSString).boundingRect(with: NSSize(width: 600, height: 10000), options: [.usesLineFragmentOrigin], attributes: attrs)
        return NSRect(x: vp.x, y: vp.y, width: max(size.width, 20), height: max(size.height, 16))
    }

    private func hitTestTextElement(at viewPoint: CGPoint) -> Int? {
        for (i, _) in elements.enumerated().reversed() {
            if let rect = textElementRect(at: i), rect.contains(viewPoint) {
                return i
            }
        }
        return nil
    }

    /// Hit test any element (for the hand tool). Returns the index of the topmost hit element.
    private func hitTestAnyElement(at viewPoint: CGPoint) -> Int? {
        let tolerance: CGFloat = 6
        for (i, element) in elements.enumerated().reversed() {
            switch element.tool {
            case .text:
                if let rect = textElementRect(at: i), rect.contains(viewPoint) { return i }

            case .pen:
                for j in 0..<max(0, element.points.count - 1) {
                    let a = toViewCoords(element.points[j])
                    let b = toViewCoords(element.points[j + 1])
                    if distanceFromPoint(viewPoint, toSegment: a, b) < tolerance + element.lineWidth / 2 { return i }
                }
                if element.points.count == 1 {
                    let p = toViewCoords(element.points[0])
                    if hypot(viewPoint.x - p.x, viewPoint.y - p.y) < tolerance + element.lineWidth / 2 { return i }
                }

            case .arrow:
                guard element.points.count >= 2 else { continue }
                let a = toViewCoords(element.points[0])
                let b = toViewCoords(element.points[1])
                if distanceFromPoint(viewPoint, toSegment: a, b) < tolerance + element.lineWidth / 2 { return i }

            case .rectangle:
                guard element.points.count >= 2 else { continue }
                let a = toViewCoords(element.points[0])
                let b = toViewCoords(element.points[1])
                let r = rectFrom(a, b)
                let expanded = r.insetBy(dx: -(tolerance + element.lineWidth / 2), dy: -(tolerance + element.lineWidth / 2))
                let inner = r.insetBy(dx: tolerance + element.lineWidth / 2, dy: tolerance + element.lineWidth / 2)
                if expanded.contains(viewPoint) && !inner.contains(viewPoint) { return i }

            case .hand:
                break
            }
        }
        return nil
    }

    /// Distance from a point to a line segment.
    private func distanceFromPoint(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(p.x - proj.x, p.y - proj.y)
    }

    // MARK: - Tracking area for cursor changes

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = cursorTrackingArea { removeTrackingArea(existing) }
        cursorTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
            owner: self
        )
        addTrackingArea(cursorTrackingArea!)
    }

    override func mouseMoved(with event: NSEvent) {
        let viewPt = convert(event.locationInWindow, from: nil)
        if selectedTool == .hand {
            if hitTestAnyElement(at: viewPt) != nil {
                NSCursor.openHand.set()
            } else {
                NSCursor.arrow.set()
            }
        } else if hitTestTextElement(at: viewPt) != nil {
            NSCursor.openHand.set()
        } else if selectedTool == .text {
            NSCursor.iBeam.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        let viewPt = convert(event.locationInWindow, from: nil)
        let imgPt = toImageCoords(viewPt)

        // Block the click that follows a text commit (from losing focus)
        if blockNextClick {
            blockNextClick = false
            return
        }

        let isOnTextEditor = activeTextContainer.map { $0.frame.contains(viewPt) } ?? false

        // Click is on the active text editor — let it handle normally
        if isOnTextEditor {
            return
        }

        // Click is outside the active text editor — commit it
        if activeTextContainer != nil {
            commitTextField()
            return
        }

        // Hand tool: click on any element to start dragging
        if selectedTool == .hand {
            if let idx = hitTestAnyElement(at: viewPt) {
                coordinator?.saveSnapshot()
                handDraggingIndex = idx
                handDragStartImg = imgPt
                handDragOriginalPoints = elements[idx].points
                NSCursor.closedHand.set()
            }
            return
        }

        // Double-click on existing text → re-edit it
        if event.clickCount == 2, let idx = hitTestTextElement(at: viewPt) {
            draggingTextIndex = nil
            clickedTextIndex = nil
            let element = elements[idx]
            guard let text = element.text, let pt = element.points.first else { return }
            let vp = toViewCoords(pt)
            editingTextIndex = idx
            textPlacementPoint = pt
            let editFontSize = max(14, element.lineWidth * 5)
            // Drawn text origin is bottom-left in non-flipped coords;
            // shift up by the text bounding height so the edit field aligns with the rendered text
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: editFontSize, weight: .semibold),
            ]
            let textBounds = (text as NSString).boundingRect(with: NSSize(width: 600, height: 10000), options: [.usesLineFragmentOrigin], attributes: attrs)
            showTextField(at: CGPoint(x: vp.x, y: vp.y + textBounds.height), text: text, fontSize: editFontSize)
            return
        }

        // Single click on existing text → prepare for drag
        if let idx = hitTestTextElement(at: viewPt) {
            coordinator?.saveSnapshot()
            clickedTextIndex = idx
            let existingPt = toViewCoords(elements[idx].points[0])
            dragOffset = CGPoint(x: viewPt.x - existingPt.x, y: viewPt.y - existingPt.y)
            NSCursor.closedHand.set()
            return
        }

        clickedTextIndex = nil

        // Text tool on empty area: place new text field
        if selectedTool == .text {
            textPlacementPoint = imgPt
            editingTextIndex = nil
            // Shift up so text starts at cursor (non-flipped coords: drawn text origin is bottom-left)
            let font = NSFont.systemFont(ofSize: fontSize(), weight: .semibold)
            showTextField(at: CGPoint(x: viewPt.x, y: viewPt.y + font.ascender), text: "", fontSize: fontSize())
            return
        }

        // Other tools: start drawing
        isDragging = true
        currentPoints = [imgPt]
    }

    override func mouseDragged(with event: NSEvent) {
        let viewPt = convert(event.locationInWindow, from: nil)
        let imgPt = toImageCoords(viewPt)

        // Hand tool: drag any element by offsetting all its points
        if let idx = handDraggingIndex {
            let dx = imgPt.x - handDragStartImg.x
            let dy = imgPt.y - handDragStartImg.y
            var element = elements[idx]
            element.points = handDragOriginalPoints.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            coordinator?.updateElement(at: idx, element)
            needsDisplay = true
            return
        }

        // Start or continue dragging a text element
        if let idx = clickedTextIndex {
            draggingTextIndex = idx
            let newViewPt = CGPoint(x: viewPt.x - dragOffset.x, y: viewPt.y - dragOffset.y)
            let newImgPt = toImageCoords(newViewPt)
            var element = elements[idx]
            element.points = [newImgPt]
            coordinator?.updateElement(at: idx, element)
            needsDisplay = true
            return
        }

        guard isDragging else { return }

        if selectedTool == .pen {
            currentPoints.append(imgPt)
        } else {
            if currentPoints.count == 1 { currentPoints.append(imgPt) }
            else { currentPoints[1] = imgPt }
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if handDraggingIndex != nil {
            handDraggingIndex = nil
            handDragOriginalPoints = []
            let viewPt = convert(event.locationInWindow, from: nil)
            if hitTestAnyElement(at: viewPt) != nil {
                NSCursor.openHand.set()
            } else {
                NSCursor.arrow.set()
            }
            return
        }

        if draggingTextIndex != nil || clickedTextIndex != nil {
            draggingTextIndex = nil
            clickedTextIndex = nil
            NSCursor.openHand.set()
            return
        }

        guard isDragging else { return }
        isDragging = false

        if currentPoints.count >= 2 || (selectedTool == .pen && !currentPoints.isEmpty) {
            let element = DrawingElement(
                tool: selectedTool, color: selectedColor, lineWidth: lineWidth,
                points: currentPoints, text: nil
            )
            coordinator?.addElement(element)
        }
        currentPoints = []
        needsDisplay = true
    }

    // MARK: - Inline multiline text editor

    private func showTextField(at viewPoint: CGPoint, text: String, fontSize size: CGFloat) {
        activeTextContainer?.removeFromSuperview()
        activeTextContainer = nil
        activeTextView = nil

        let font = NSFont.systemFont(ofSize: size, weight: .semibold)
        let layoutManager = NSLayoutManager()
        let lineHeight = layoutManager.defaultLineHeight(for: font)
        let lineCount = CGFloat(max(1, text.components(separatedBy: "\n").count))
        let inset: CGFloat = 4
        let width: CGFloat = max(200, CGFloat(text.count) * size * 0.6)
        let height: CGFloat = lineCount * lineHeight + inset * 2

        // Plain NSView with layer border (NSBox adds hidden internal padding)
        // In non-flipped coords, position so top edge aligns with click point
        let container = NSView(frame: NSRect(x: viewPoint.x, y: viewPoint.y - height + inset, width: width, height: height))
        container.wantsLayer = true
        container.layer?.borderColor = selectedColor.cgColor
        container.layer?.borderWidth = 2
        container.layer?.cornerRadius = 3

        let textView = NSTextView(frame: NSRect(x: inset, y: inset, width: width - inset * 2, height: height - inset * 2))
        textView.font = font
        textView.textColor = selectedColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isFieldEditor = false
        textView.delegate = self
        textView.string = text
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 600, height: 10000)
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 2
        textView.insertionPointColor = selectedColor

        container.addSubview(textView)
        addSubview(container)
        window?.makeFirstResponder(textView)
        activeTextContainer = container
        activeTextView = textView
        needsDisplay = true

        if !text.isEmpty {
            textView.selectAll(nil)
        }
    }

    // Enter inserts newline, ESC commits
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            textView.insertNewlineIgnoringFieldEditor(nil)
            NSLog("PixyVibe: newline inserted, text is now: %@", textView.string.debugDescription)
            resizeTextContainer()
            NSLog("PixyVibe: resize called synchronously")
            return true
        }
        if commandSelector == #selector(cancelOperation(_:)) {
            commitTextField()
            return true
        }
        return false
    }

    // Text view lost focus — commit only if focus moved away (not from Enter key)
    func textDidEndEditing(_ notification: Notification) {
        // Check the reason for ending editing
        let movement = (notification.userInfo?["NSTextMovement"] as? Int) ?? 0
        // 0 = other (click outside), NSReturnTextMovement = 16 (Enter key)
        // Only commit on click-outside (0), not on Enter
        if movement == 0 {
            blockNextClick = true
            commitTextField()
        }
    }

    func textDidChange(_ notification: Notification) {
        resizeTextContainer()
    }

    private func resizeTextContainer() {
        guard let textView = activeTextView, let container = activeTextContainer else {
            NSLog("PixyVibe: resizeTextContainer - no active text view or container")
            return
        }

        let text = textView.string
        let font = textView.font ?? NSFont.systemFont(ofSize: fontSize())
        let layoutManager = NSLayoutManager()
        let lineHeight = layoutManager.defaultLineHeight(for: font)

        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        var maxLineWidth: CGFloat = 0
        let lines = text.components(separatedBy: "\n")
        for line in lines {
            let lineWidth = (line as NSString).size(withAttributes: attrs).width
            maxLineWidth = max(maxLineWidth, lineWidth)
        }
        let lineCount = CGFloat(max(1, lines.count))

        let inset: CGFloat = 4
        let newWidth = max(200, maxLineWidth + inset * 2 + 8)
        let newHeight = lineCount * lineHeight + inset * 2

        var boxFrame = container.frame
        boxFrame.size.width = newWidth
        boxFrame.size.height = newHeight
        container.frame = boxFrame

        textView.frame = NSRect(x: inset, y: inset, width: newWidth - inset * 2, height: newHeight - inset * 2)
    }

    /// Update the active text field's color and font size to match current toolbar settings.
    func applyStyleToActiveText() {
        guard let textView = activeTextView, let container = activeTextContainer else { return }
        let newFontSize = fontSize()
        let newFont = NSFont.systemFont(ofSize: newFontSize, weight: .semibold)
        textView.textColor = selectedColor
        textView.insertionPointColor = selectedColor
        textView.font = newFont
        container.layer?.borderColor = selectedColor.cgColor
        resizeTextContainer()
    }

    private func commitTextField() {
        guard let textView = activeTextView else { return }
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentFontSize = textView.font?.pointSize ?? fontSize()
        activeTextContainer?.removeFromSuperview()
        activeTextContainer = nil
        activeTextView = nil

        guard !text.isEmpty else {
            editingTextIndex = nil
            return
        }

        if let idx = editingTextIndex {
            coordinator?.saveSnapshot()
            let updatedElement = DrawingElement(
                tool: .text, color: selectedColor, lineWidth: currentFontSize / 5,
                points: elements[idx].points, text: text
            )
            coordinator?.updateElement(at: idx, updatedElement)
            editingTextIndex = nil
        } else {
            let element = DrawingElement(
                tool: .text, color: selectedColor, lineWidth: currentFontSize / 5,
                points: [textPlacementPoint], text: text
            )
            coordinator?.addElement(element)
        }
        needsDisplay = true
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        let cursor: NSCursor = selectedTool == .hand ? .arrow : selectedTool == .text ? .iBeam : .crosshair
        addCursorRect(bounds, cursor: cursor)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        image?.draw(in: imageRect)

        for (i, element) in elements.enumerated() {
            // Skip the element currently being edited
            if i == editingTextIndex && activeTextContainer != nil { continue }
            drawElement(element)
        }

        if isDragging && !currentPoints.isEmpty {
            let current = DrawingElement(
                tool: selectedTool, color: selectedColor, lineWidth: lineWidth,
                points: currentPoints, text: nil
            )
            drawElement(current)
        }
    }

    private func drawElement(_ element: DrawingElement) {
        element.color.setStroke()
        element.color.setFill()

        switch element.tool {
        case .pen:
            let path = NSBezierPath()
            path.lineWidth = element.lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            for (i, pt) in element.points.enumerated() {
                let vp = toViewCoords(pt)
                if i == 0 { path.move(to: vp) } else { path.line(to: vp) }
            }
            path.stroke()

        case .arrow:
            guard element.points.count >= 2 else { return }
            let start = toViewCoords(element.points[0])
            let end = toViewCoords(element.points[1])
            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLen: CGFloat = max(14, element.lineWidth * 4)
            let headAngle: CGFloat = .pi / 6
            let p1 = CGPoint(x: end.x - headLen * cos(angle - headAngle),
                              y: end.y - headLen * sin(angle - headAngle))
            let p2 = CGPoint(x: end.x - headLen * cos(angle + headAngle),
                              y: end.y - headLen * sin(angle + headAngle))
            // Shaft stops at the base of the triangle
            let base = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
            let shaft = NSBezierPath()
            shaft.lineWidth = element.lineWidth
            shaft.lineCapStyle = .round
            shaft.move(to: start)
            shaft.line(to: base)
            shaft.stroke()
            // Filled triangle head
            let head = NSBezierPath()
            head.move(to: end)
            head.line(to: p1)
            head.line(to: p2)
            head.close()
            head.fill()

        case .rectangle:
            guard element.points.count >= 2 else { return }
            let a = toViewCoords(element.points[0])
            let b = toViewCoords(element.points[1])
            let r = rectFrom(a, b)
            let path = NSBezierPath(rect: r)
            path.lineWidth = element.lineWidth
            path.stroke()

        case .text:
            guard let text = element.text, let pt = element.points.first else { return }
            let vp = toViewCoords(pt)
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: element.color,
                .font: NSFont.systemFont(ofSize: max(14, element.lineWidth * 5), weight: .semibold),
            ]
            let size = (text as NSString).boundingRect(with: NSSize(width: 600, height: 10000), options: [.usesLineFragmentOrigin], attributes: attrs)
            (text as NSString).draw(in: NSRect(origin: vp, size: size.size), withAttributes: attrs)

        case .hand:
            break
        }
    }
}

// MARK: - GIF Player

struct GifPlayerView: View {
    let imageData: Data
    let onClose: () -> Void

    @State private var isPlaying = true

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ControllableGIFView(data: imageData, isPlaying: isPlaying)
                    .frame(width: geo.size.width, height: geo.size.height)
            }

            HStack {
                Button(action: { isPlaying.toggle() }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ControllableGIFView: NSViewRepresentable {
    let data: Data
    let isPlaying: Bool

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = isPlaying
        imageView.canDrawSubviewsIntoLayer = true
        imageView.wantsLayer = true
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        if let image = NSImage(data: data) {
            imageView.image = image
        }
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.animates = isPlaying
    }
}
