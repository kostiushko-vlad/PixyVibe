import Cocoa
import SwiftUI

// MARK: - Editor Window

class ImageEditorWindow {
    private var window: NSWindow?

    func open(imageData: Data, filePath: String, isGif: Bool, onSave: @escaping (Data) -> Void) {
        window?.close()

        let editor: any View
        if isGif {
            editor = GifEditorView(imageData: imageData, filePath: filePath, onSave: onSave, onClose: { [weak self] in
                self?.window?.close()
                self?.window = nil
            })
        } else {
            editor = StaticImageEditorView(imageData: imageData, filePath: filePath, onSave: onSave, onClose: { [weak self] in
                self?.window?.close()
                self?.window = nil
            })
        }

        let hostingView = NSHostingView(rootView: AnyView(editor))
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = isGif ? "Edit GIF" : "Edit Screenshot"
        win.contentView = hostingView
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }
}

// MARK: - Drawing Tool Types

enum DrawingTool: String, CaseIterable {
    case pen = "Pen"
    case arrow = "Arrow"
    case rectangle = "Rectangle"
    case text = "Text"

    var icon: String {
        switch self {
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

// MARK: - Static Image Editor

struct StaticImageEditorView: View {
    let imageData: Data
    let filePath: String
    let onSave: (Data) -> Void
    let onClose: () -> Void

    @State private var selectedTool: DrawingTool = .pen
    @State private var selectedColor: Color = .red
    @State private var lineWidth: CGFloat = 3
    @State private var elements: [DrawingElement] = []

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                ForEach(DrawingTool.allCases, id: \.self) { tool in
                    Button(action: { selectedTool = tool }) {
                        VStack(spacing: 2) {
                            Image(systemName: tool.icon)
                                .font(.system(size: 14))
                            Text(tool.rawValue)
                                .font(.system(size: 9))
                        }
                        .frame(width: 50, height: 36)
                        .background(selectedTool == tool ? Color.accentColor.opacity(0.2) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                Divider().frame(height: 30)

                ColorPicker("", selection: $selectedColor)
                    .labelsHidden()
                    .frame(width: 30)

                Divider().frame(height: 30)

                HStack(spacing: 4) {
                    Text("Size:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Slider(value: $lineWidth, in: 1...10)
                        .frame(width: 80)
                }

                Divider().frame(height: 30)

                Button(action: {
                    if !elements.isEmpty { elements.removeLast() }
                }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .disabled(elements.isEmpty)

                Spacer()

                Button("Cancel") { onClose() }
                Button("Save") { saveImage() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            // Canvas
            DrawingCanvasView(
                imageData: imageData,
                elements: $elements,
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
                let path = NSBezierPath()
                path.lineWidth = element.lineWidth
                path.move(to: start)
                path.line(to: end)
                path.stroke()
                let angle = atan2(end.y - start.y, end.x - start.x)
                let headLen: CGFloat = 15
                let headAngle: CGFloat = .pi / 6
                let arrow = NSBezierPath()
                arrow.move(to: end)
                arrow.line(to: CGPoint(x: end.x - headLen * cos(angle - headAngle),
                                       y: end.y - headLen * sin(angle - headAngle)))
                arrow.move(to: end)
                arrow.line(to: CGPoint(x: end.x - headLen * cos(angle + headAngle),
                                       y: end.y - headLen * sin(angle + headAngle)))
                arrow.lineWidth = element.lineWidth
                arrow.stroke()

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
        nsView.selectedColor = NSColor(selectedColor)
        nsView.lineWidth = lineWidth
        nsView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    class Coordinator {
        var parent: DrawingCanvasView
        init(parent: DrawingCanvasView) { self.parent = parent }

        func addElement(_ element: DrawingElement) {
            parent.elements.append(element)
        }

        func updateElement(at index: Int, _ element: DrawingElement) {
            guard index >= 0, index < parent.elements.count else { return }
            parent.elements[index] = element
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

    // MARK: - Hit test for text elements

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
        if hitTestTextElement(at: viewPt) != nil {
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
            showTextField(at: vp, text: text, fontSize: editFontSize)
            return
        }

        // Single click on existing text → prepare for drag
        if let idx = hitTestTextElement(at: viewPt) {
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
            showTextField(at: viewPt, text: "", fontSize: fontSize())
            return
        }

        // Other tools: start drawing
        isDragging = true
        currentPoints = [imgPt]
    }

    override func mouseDragged(with event: NSEvent) {
        let viewPt = convert(event.locationInWindow, from: nil)

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
        let imgPt = toImageCoords(viewPt)

        if selectedTool == .pen {
            currentPoints.append(imgPt)
        } else {
            if currentPoints.count == 1 { currentPoints.append(imgPt) }
            else { currentPoints[1] = imgPt }
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
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
            var element = elements[idx]
            element.text = text
            coordinator?.updateElement(at: idx, element)
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
        addCursorRect(bounds, cursor: selectedTool == .text ? .iBeam : .crosshair)
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
            let path = NSBezierPath()
            path.lineWidth = element.lineWidth
            path.move(to: start)
            path.line(to: end)
            path.stroke()
            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLen: CGFloat = 12
            let headAngle: CGFloat = .pi / 6
            let arrow = NSBezierPath()
            arrow.move(to: end)
            arrow.line(to: CGPoint(x: end.x - headLen * cos(angle - headAngle),
                                   y: end.y - headLen * sin(angle - headAngle)))
            arrow.move(to: end)
            arrow.line(to: CGPoint(x: end.x - headLen * cos(angle + headAngle),
                                   y: end.y - headLen * sin(angle + headAngle)))
            arrow.lineWidth = element.lineWidth
            arrow.stroke()

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
        }
    }
}

// MARK: - GIF Editor

// MARK: - Bordered container for inline text editing

// MARK: - GIF Editor

struct GifEditorView: View {
    let imageData: Data
    let filePath: String
    let onSave: (Data) -> Void
    let onClose: () -> Void

    @State private var speed: Double = 1.0
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 1.0
    @State private var reverse = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit GIF").font(.headline)
                Spacer()
                Button("Cancel") { onClose() }
                Button("Save") { saveGif() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            AnimatedGIFView(data: imageData)
                .frame(maxHeight: 350)
                .padding(12)

            Divider()

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trim").font(.system(size: 12, weight: .semibold))
                    HStack {
                        Text("Start").font(.system(size: 11)).frame(width: 40)
                        Slider(value: $trimStart, in: 0...trimEnd)
                        Text("\(Int(trimStart * 100))%")
                            .font(.system(size: 11, design: .monospaced)).frame(width: 40)
                    }
                    HStack {
                        Text("End").font(.system(size: 11)).frame(width: 40)
                        Slider(value: $trimEnd, in: trimStart...1.0)
                        Text("\(Int(trimEnd * 100))%")
                            .font(.system(size: 11, design: .monospaced)).frame(width: 40)
                    }
                }

                HStack {
                    Text("Speed").font(.system(size: 12, weight: .semibold)).frame(width: 50, alignment: .leading)
                    Slider(value: $speed, in: 0.25...3.0)
                    Text("\(String(format: "%.1f", speed))x")
                        .font(.system(size: 11, design: .monospaced)).frame(width: 40)
                }

                Toggle("Reverse playback", isOn: $reverse)
                    .font(.system(size: 12))
            }
            .padding(16)
        }
    }

    private func saveGif() {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { onClose(); return }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { onClose(); return }

        let startFrame = Int(trimStart * Double(frameCount))
        let endFrame = Int(trimEnd * Double(frameCount))
        guard endFrame > startFrame else { onClose(); return }

        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, "com.compuserve.gif" as CFString, endFrame - startFrame, nil) else { onClose(); return }

        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]
        ]
        CGImageDestinationSetProperties(dest, gifProperties as CFDictionary)

        let frameRange = reverse ? Array((startFrame..<endFrame).reversed()) : Array(startFrame..<endFrame)

        for i in frameRange {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            var delay = 0.1
            if let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
               let gifProps = props[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                if let d = gifProps[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double, d > 0 { delay = d }
                else if let d = gifProps[kCGImagePropertyGIFDelayTime as String] as? Double, d > 0 { delay = d }
            }
            delay /= speed
            delay = max(0.02, delay)

            let frameProps: [String: Any] = [
                kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: delay]
            ]
            CGImageDestinationAddImage(dest, cgImage, frameProps as CFDictionary)
        }

        CGImageDestinationFinalize(dest)
        onSave(output as Data)
        onClose()
    }
}
