import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    private var isDiffPending = false
    private var diffRegion: CGRect?
    private var overlayWindow: OverlayWindow?
    private var settingsWindow: NSWindow?
    private var editor = ImageEditorWindow()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("PixyVibe: applicationDidFinishLaunching called")
        RustBridge.shared.initialize()
        NSLog("PixyVibe: Rust core initialized")

        setupStatusItem()

        hotkeyManager = HotkeyManager()
        hotkeyManager.onAction = { [weak self] action in
            self?.handleAction(action)
        }
        hotkeyManager.register()

        NSApp.setActivationPolicy(.accessory)

        NotificationCenter.default.addObserver(
            self, selector: #selector(historyChanged),
            name: .screenshotHistoryChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(pauseHotkeys),
            name: .shortcutRecordingStarted, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(resumeHotkeys),
            name: .shortcutRecordingStopped, object: nil
        )
    }

    @objc private func historyChanged() {
        rebuildMenu()
    }

    @objc private func pauseHotkeys() {
        hotkeyManager.isPaused = true
    }

    @objc private func resumeHotkeys() {
        hotkeyManager.isPaused = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregister()
        RustBridge.shared.shutdown()
    }

    // MARK: - Menu Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "PixyVibe")
            button.image?.size = NSSize(width: 18, height: 18)
        }

        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(withTitle: "Capture Region", action: #selector(captureRegion), keyEquivalent: "")
        menu.items.last?.keyEquivalentModifierMask = [.shift, .command]
        menu.items.last?.keyEquivalent = "2"
        menu.items.last?.target = self

        // History section
        let history = ScreenshotHistory.shared.entries
        if !history.isEmpty {
            menu.addItem(NSMenuItem.separator())

            let gridItem = NSMenuItem()
            let gridView = HistoryGridView(
                entries: history,
                onClickEntry: { [weak self] index in
                    self?.openHistoryEntry(at: index)
                },
                onCopyEntry: { index in
                    let entry = history[index]
                    if entry.filePath.hasSuffix(".gif") {
                        ClipboardManager.copyFileAsFinderFull(entry.filePath)
                    } else {
                        ClipboardManager.copyImage(entry.imageData)
                    }
                    ToastNotification.show("Copied to clipboard")
                },
                onRemoveEntry: { [weak self] index in
                    let entry = history[index]
                    ScreenshotHistory.shared.remove(filePath: entry.filePath)
                    NotificationCenter.default.post(name: .screenshotHistoryChanged, object: nil)
                    self?.rebuildMenu()
                }
            )
            // Show 2 rows visible, scroll for more
            let maxVisibleHeight: CGFloat = 90 * 2 + 6 + 20  // 2 rows + padding + margins
            let needsScroll = gridView.frame.height > maxVisibleHeight
            if needsScroll {
                let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: gridView.frame.width, height: maxVisibleHeight))
                scrollView.documentView = gridView
                scrollView.hasVerticalScroller = true
                scrollView.hasHorizontalScroller = false
                scrollView.autohidesScrollers = true
                scrollView.drawsBackground = false
                scrollView.scrollerStyle = .overlay
                gridItem.view = scrollView
            } else {
                gridItem.view = gridView
            }
            menu.addItem(gridItem)

            menu.addItem(NSMenuItem.separator())

            let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)

            let openFolderItem = NSMenuItem(title: "Open Screenshots Folder", action: #selector(openScreenshotsFolder), keyEquivalent: "")
            openFolderItem.target = self
            menu.addItem(openFolderItem)
        }

        menu.addItem(NSMenuItem.separator())

        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.items.last?.target = self

        menu.addItem(NSMenuItem.separator())

        menu.addItem(withTitle: "Quit PixyVibe", action: #selector(quitApp), keyEquivalent: "q")
        menu.items.last?.target = self

        statusItem.menu = menu
    }

    // MARK: - Menu Actions

    @objc private func captureRegion() {
        handleAction(.screenshot)
    }

    private func openHistoryEntry(at index: Int) {
        let entries = ScreenshotHistory.shared.entries
        guard index >= 0, index < entries.count else { return }
        let entry = entries[index]
        let isGif = entry.filePath.hasSuffix(".gif")
        editor.open(imageData: entry.imageData, filePath: entry.filePath, isGif: isGif, onSave: { [weak self] newData in
            try? newData.write(to: URL(fileURLWithPath: entry.filePath))
            ScreenshotHistory.shared.remove(filePath: entry.filePath)
            ScreenshotHistory.shared.add(imageData: newData, filePath: entry.filePath)
            NotificationCenter.default.post(name: .screenshotHistoryChanged, object: nil)
            self?.rebuildMenu()
            if isGif {
                ClipboardManager.copyFileAsFinderFull(entry.filePath)
            } else {
                ClipboardManager.copyImage(newData)
            }
            ToastNotification.show("Saved and copied to clipboard")
        }, onRemove: { [weak self] in
            try? FileManager.default.removeItem(atPath: entry.filePath)
            ScreenshotHistory.shared.remove(filePath: entry.filePath)
            NotificationCenter.default.post(name: .screenshotHistoryChanged, object: nil)
            self?.rebuildMenu()
            ToastNotification.show("Deleted")
        })
    }

    @objc private func clearHistory() {
        ScreenshotHistory.shared.clear()
        rebuildMenu()
    }

    @objc private func openScreenshotsFolder() {
        let path = NSHomeDirectory() + "/.screenshottool/screenshots"
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingView = NSHostingView(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "PixyVibe Settings"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Hotkey / Overlay

    private func handleAction(_ action: HotkeyAction) {
        switch action {
        case .screenshot:
            showOverlay(mode: .normal, preselectedMode: .screenshot)
        case .gifRecording:
            showOverlay(mode: .normal, preselectedMode: .gif)
        case .diff:
            if isDiffPending {
                showOverlay(mode: .diffAfter, savedRegion: diffRegion)
            } else {
                showOverlay(mode: .normal, preselectedMode: .diff)
            }
        }
    }

    private func showOverlay(mode: OverlayMode, savedRegion: CGRect? = nil, preselectedMode: CaptureMode? = nil) {
        overlayWindow?.hide()

        let overlay = OverlayWindow(mode: mode, preselectedMode: preselectedMode)
        overlay.savedRegion = savedRegion
        overlay.onScreenshot = { [weak self] region in
            self?.performScreenshot(region: region)
        }
        overlay.onGifStart = { [weak self] region in
            self?.performGifRecording(region: region)
        }
        overlay.onDiffBefore = { [weak self] region in
            self?.performDiffBefore(region: region)
        }
        overlay.onDiffAfter = { [weak self] region in
            self?.performDiffAfter(region: region)
        }
        overlayWindow = overlay
        overlay.show()
    }

    // MARK: - Capture Actions

    private func performScreenshot(region: CGRect) {
        NSLog("PixyVibe: performScreenshot for region %@", NSStringFromRect(region))
        guard let result = RustBridge.shared.processScreenshot(region: region) else {
            NSLog("PixyVibe: processScreenshot returned nil")
            ToastNotification.show("Screenshot failed")
            return
        }
        NSLog("PixyVibe: got result, %d bytes", result.imageData.count)

        // Save to history
        ScreenshotHistory.shared.add(imageData: result.imageData, filePath: result.filePath)
        rebuildMenu()

        ClipboardManager.copyImage(result.imageData)
        CapturePreview.show(imageData: result.imageData, filePath: result.filePath, label: "Screenshot")
    }

    private func performGifRecording(region: CGRect) {
        guard let sessionId = RustBridge.shared.gifStart() else {
            ToastNotification.show("Failed to start recording")
            return
        }

        let pill = RecordingPill(region: region)
        pill.show()

        let clickAnimator = ClickAnimator()
        clickAnimator.start()

        let fps = 10
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / Double(fps), repeats: true) { _ in
            let _ = RustBridge.shared.gifAddFrame(sessionId, region: region)
        }

        pill.onStop = { [weak self] in
            timer.invalidate()
            clickAnimator.stop()
            pill.close()

            if let result = RustBridge.shared.gifFinish(sessionId) {
                ScreenshotHistory.shared.add(imageData: result.imageData, filePath: result.filePath)
                self?.rebuildMenu()
                ClipboardManager.copyFileAsFinderFull(result.filePath)
                CapturePreview.show(imageData: result.imageData, filePath: result.filePath, label: "GIF Recording")
            } else {
                ToastNotification.show("GIF encoding failed")
            }
        }
    }

    private func performDiffBefore(region: CGRect) {
        guard RustBridge.shared.diffStoreBefore(region: region) else {
            ToastNotification.show("Failed to capture 'before'")
            return
        }
        isDiffPending = true
        diffRegion = region
        updateTrayIcon()
        let shortcut = ShortcutStore.shared.diff.displayString
        ToastNotification.show("Before captured — make changes, then press \(shortcut)")
    }

    private func performDiffAfter(region: CGRect) {
        guard let result = RustBridge.shared.diffCompare(region: region) else {
            ToastNotification.show("Diff comparison failed")
            isDiffPending = false
            diffRegion = nil
            updateTrayIcon()
            return
        }
        isDiffPending = false
        diffRegion = nil
        updateTrayIcon()

        ScreenshotHistory.shared.add(imageData: result.imageData, filePath: result.filePath)
        rebuildMenu()

        ClipboardManager.copyImage(result.imageData)
        let pct = String(format: "%.1f", result.changePercentage)
        CapturePreview.show(imageData: result.imageData, filePath: result.filePath, label: "Diff — \(pct)% changed")
    }

    private func updateTrayIcon() {
        if let button = statusItem.button {
            let iconName = isDiffPending ? "arrow.triangle.2.circlepath.camera" : "camera.viewfinder"
            button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "PixyVibe")
            button.image?.size = NSSize(width: 18, height: 18)
        }
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === settingsWindow {
            settingsWindow = nil
        }
    }
}

// MARK: - OverlayMode

enum OverlayMode {
    case normal
    case diffAfter
}

// MARK: - History Grid View (2-column grid of recent captures)

class HistoryGridView: NSView {
    private let entries: [ScreenshotEntry]
    private var onClickEntry: ((Int) -> Void)?
    private var onCopyEntry: ((Int) -> Void)?
    private var onRemoveEntry: ((Int) -> Void)?

    private let cols = 2
    private let cellWidth: CGFloat = 150
    private let thumbHeight: CGFloat = 90
    private let cellPadding: CGFloat = 6
    private let menuPadding: CGFloat = 10

    private var cellRects: [NSRect] = []  // thumb rects per entry
    private var hoveredIndex: Int? = nil

    init(entries: [ScreenshotEntry],
         onClickEntry: ((Int) -> Void)?,
         onCopyEntry: ((Int) -> Void)?,
         onRemoveEntry: ((Int) -> Void)?) {
        self.entries = entries
        self.onClickEntry = onClickEntry
        self.onCopyEntry = onCopyEntry
        self.onRemoveEntry = onRemoveEntry

        let rows = Int(ceil(Double(entries.count) / Double(2)))
        let totalWidth = cellWidth * 2 + cellPadding + menuPadding * 2
        let totalHeight = CGFloat(rows) * thumbHeight + CGFloat(max(0, rows - 1)) * cellPadding + menuPadding * 2

        super.init(frame: NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight))
        buildCellRects()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func buildCellRects() {
        cellRects = []
        for i in 0..<entries.count {
            let col = i % cols
            let row = i / cols
            let x = menuPadding + CGFloat(col) * (cellWidth + cellPadding)
            let y = menuPadding + CGFloat(row) * (thumbHeight + cellPadding)
            cellRects.append(NSRect(x: x, y: y, width: cellWidth, height: thumbHeight))
        }
    }

    // Overlay rects (inside thumb, at bottom — in flipped coords, bottom = maxY)
    private func overlayRect(for cellRect: NSRect) -> NSRect {
        NSRect(x: cellRect.minX, y: cellRect.maxY - 24, width: cellRect.width, height: 24)
    }

    private func copyIconRect(for cellRect: NSRect) -> NSRect {
        NSRect(x: cellRect.maxX - 34, y: cellRect.maxY - 19, width: 14, height: 14)
    }

    private func removeIconRect(for cellRect: NSRect) -> NSRect {
        NSRect(x: cellRect.maxX - 16, y: cellRect.maxY - 19, width: 14, height: 14)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for (i, cellRect) in cellRects.enumerated() {
            let entry = entries[i]

            // Thumbnail
            if let thumb = entry.thumbnail(maxSize: cellWidth) {
                NSGraphicsContext.saveGraphicsState()
                let clip = NSBezierPath(roundedRect: cellRect, xRadius: 5, yRadius: 5)
                clip.addClip()
                thumb.draw(in: cellRect)
                NSGraphicsContext.restoreGraphicsState()

                NSColor.separatorColor.setStroke()
                let border = NSBezierPath(roundedRect: cellRect, xRadius: 5, yRadius: 5)
                border.lineWidth = 0.5
                border.stroke()
            }

            // Hover overlay
            if hoveredIndex == i {
                let ovr = overlayRect(for: cellRect)
                NSGraphicsContext.saveGraphicsState()
                // Clip to bottom of rounded rect
                let clip = NSBezierPath(roundedRect: cellRect, xRadius: 5, yRadius: 5)
                clip.addClip()
                NSColor.black.withAlphaComponent(0.6).setFill()
                ovr.fill()
                NSGraphicsContext.restoreGraphicsState()

                // Time label
                let timeAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 9),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.9),
                ]
                let timeRect = NSRect(x: cellRect.minX + 6, y: cellRect.maxY - 19, width: cellRect.width - 44, height: 14)
                (entry.timeAgo as NSString).draw(in: timeRect, withAttributes: timeAttrs)

                // Copy icon
                if let copyImg = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil) {
                    let tinted = copyImg.tinted(with: .white)
                    tinted.draw(in: copyIconRect(for: cellRect))
                }

                // Remove icon
                if let trashImg = NSImage(systemSymbolName: "trash", accessibilityDescription: nil) {
                    let tinted = trashImg.tinted(with: .white)
                    tinted.draw(in: removeIconRect(for: cellRect))
                }
            }
        }
    }

    // MARK: - Mouse tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let newHover = cellRects.firstIndex(where: { $0.contains(pt) })
        if newHover != hoveredIndex {
            hoveredIndex = newHover
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)

        for (i, cellRect) in cellRects.enumerated() {
            guard cellRect.contains(pt) else { continue }

            // Copy icon hit
            if copyIconRect(for: cellRect).insetBy(dx: -6, dy: -6).contains(pt) {
                enclosingMenuItem?.menu?.cancelTracking()
                onCopyEntry?(i)
                return
            }
            // Remove icon hit
            if removeIconRect(for: cellRect).insetBy(dx: -6, dy: -6).contains(pt) {
                enclosingMenuItem?.menu?.cancelTracking()
                onRemoveEntry?(i)
                return
            }
            // Thumbnail hit — open editor
            enclosingMenuItem?.menu?.cancelTracking()
            onClickEntry?(i)
            return
        }
    }
}

// Helper to tint SF Symbols for drawing
private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let img = self.copy() as! NSImage
        img.lockFocus()
        color.set()
        NSRect(origin: .zero, size: img.size).fill(using: .sourceAtop)
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}
