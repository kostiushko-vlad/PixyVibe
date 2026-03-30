import Cocoa
import SwiftUI

class CapturePreview {
    private static var currentWindow: NSPanel?
    private static var mouseTracker: PreviewMouseTracker?
    private static var editor = ImageEditorWindow()

    /// Show a preview of a captured image with action buttons.
    static func show(imageData: Data, filePath: String, label: String = "Screenshot") {
        DispatchQueue.main.async {
            currentWindow?.orderOut(nil)
            currentWindow = nil

            guard let screen = NSScreen.main else { return }

            let isGif = filePath.hasSuffix(".gif")

            let previewView = CapturePreviewView(
                imageData: imageData,
                isGif: isGif,
                label: label,
                filePath: filePath,
                onEdit: {
                    dismiss()
                    editor.open(imageData: imageData, filePath: filePath, isGif: isGif, onSave: { newData in
                        // Save edited version over the original file
                        try? newData.write(to: URL(fileURLWithPath: filePath))
                        // Update history
                        ScreenshotHistory.shared.remove(filePath: filePath)
                        ScreenshotHistory.shared.add(imageData: newData, filePath: filePath)
                        NotificationCenter.default.post(name: .screenshotHistoryChanged, object: nil)
                        // Copy to clipboard
                        if isGif {
                            ClipboardManager.copyFileAsFinderFull(filePath)
                        } else {
                            ClipboardManager.copyImage(newData)
                        }
                        ToastNotification.show("Saved and copied to clipboard")
                    })
                },
                onSaveAs: {
                    saveAs(imageData: imageData, defaultName: (filePath as NSString).lastPathComponent)
                },
                onOpenInFinder: {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: filePath)])
                },
                onCopyPath: {
                    ClipboardManager.copyFilePath(filePath)
                    ToastNotification.show("Path copied")
                },
                onDelete: {
                    deleteCapture(filePath: filePath)
                    dismiss()
                    ToastNotification.show("Deleted")
                },
                onClose: {
                    dismiss()
                }
            )

            let hostingView = NSHostingView(rootView: previewView)
            let fittingSize = hostingView.fittingSize
            let maxWidth: CGFloat = 420
            let width = min(fittingSize.width, maxWidth)
            let height = fittingSize.height

            let windowFrame = NSRect(
                x: screen.frame.maxX - width - 20,
                y: screen.frame.minY + 10,
                width: width,
                height: height
            )

            let panel = NSPanel(
                contentRect: windowFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.contentView = hostingView
            panel.hasShadow = true
            panel.isReleasedWhenClosed = false
            panel.isMovableByWindowBackground = true
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

            panel.alphaValue = 0
            panel.orderFrontRegardless()
            currentWindow = panel

            // Track mouse enter/exit on the panel's content view
            let tracker = PreviewMouseTracker()
            panel.contentView?.addSubview(tracker)
            tracker.frame = panel.contentView?.bounds ?? .zero
            tracker.autoresizingMask = [.width, .height]
            mouseTracker = tracker

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 1
            }

            // Auto-dismiss after 8 seconds, but not while mouse is inside
            scheduleDismiss(for: panel, delay: 8)
        }
    }

    private static func scheduleDismiss(for panel: NSPanel, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard currentWindow === panel else { return }
            if mouseTracker?.isMouseInside == true {
                // Mouse is hovering — wait for it to leave, then dismiss
                mouseTracker?.onMouseExited = {
                    scheduleDismiss(for: panel, delay: 1.5)
                }
                return
            }
            dismiss()
        }
    }

    static func dismiss() {
        guard let window = currentWindow else { return }
        mouseTracker?.onMouseExited = nil
        mouseTracker = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            if currentWindow === window {
                currentWindow = nil
            }
        })
    }

    private static func saveAs(imageData: Data, defaultName: String) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = defaultName
        savePanel.allowedContentTypes = [.png, .jpeg]
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? imageData.write(to: url)
            }
        }
    }

    private static func deleteCapture(filePath: String) {
        try? FileManager.default.removeItem(atPath: filePath)
        ScreenshotHistory.shared.remove(filePath: filePath)
        NotificationCenter.default.post(name: .screenshotHistoryChanged, object: nil)
    }
}

// MARK: - Animated GIF NSImageView wrapper

struct AnimatedGIFView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.canDrawSubviewsIntoLayer = true
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        if let image = NSImage(data: data) {
            imageView.image = image
        }
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {}
}

// MARK: - Preview View

struct CapturePreviewView: View {
    let imageData: Data
    let isGif: Bool
    let label: String
    let filePath: String
    let onEdit: () -> Void
    let onSaveAs: () -> Void
    let onOpenInFinder: () -> Void
    let onCopyPath: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image preview — click to edit
            Group {
                if isGif, let img = NSImage(data: imageData) {
                    let isPortrait = img.size.height > img.size.width
                    let maxW: CGFloat = isPortrait ? 220 : 400
                    let maxH: CGFloat = isPortrait ? 480 : 240
                    let scale = min(maxW / img.size.width, maxH / img.size.height, 1.0)
                    let w = img.size.width * scale
                    let h = img.size.height * scale
                    AnimatedGIFView(data: imageData)
                        .frame(width: w, height: h)
                        .frame(maxWidth: .infinity)
                } else if let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 400, maxHeight: 240)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { onEdit() }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.7))
                    .shadow(radius: 2)
                    .padding(6)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            // Label + clipboard badge
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                    Text((filePath as NSString).lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                    Text("Copied to clipboard")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.15), in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // For GIFs: show copyable file path (terminal paste can't do animated GIFs)
            if isGif {
                HStack(spacing: 6) {
                    Text(filePath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(action: onCopyPath) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }

            // Action buttons
            HStack(spacing: 6) {
                previewButton("pencil", "Edit") { onEdit() }
                previewButton("square.and.arrow.down", "Save As") { onSaveAs() }
                previewButton("folder", "Reveal") { onOpenInFinder() }
                deleteButton()
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .frame(width: 400)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func previewButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func deleteButton() -> some View {
        Button(action: onDelete) {
            HStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                Text("Delete")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.red.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mouse hover tracker

class PreviewMouseTracker: NSView {
    var isMouseInside = false
    var onMouseExited: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        onMouseExited?()
        onMouseExited = nil
    }
}
