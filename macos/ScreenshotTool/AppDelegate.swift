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
    private var companionPreview: CompanionPreviewWindow?

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

        // Companion devices section — always show paired devices
        let connectedDevices = RustBridge.shared.listCompanions()
        let connectedIds = Set(connectedDevices.map { $0.device_id })

        // Update paired store — use best name (skip "(Broadcast)" suffix)
        for device in connectedDevices {
            let name = device.device_name.replacingOccurrences(of: " (Broadcast)", with: "")
            PairedDeviceStore.shared.upsert(deviceId: device.device_id, deviceName: name)
        }

        // Deduplicate: group by device_id, show one entry per physical device
        var seenIds = Set<String>()
        let pairedDevices = PairedDeviceStore.shared.devices.filter { seenIds.insert($0.deviceId).inserted }
        if !pairedDevices.isEmpty {
            menu.addItem(NSMenuItem.separator())
            for device in pairedDevices {
                let isConnected = connectedIds.contains(device.deviceId)

                let item = NSMenuItem()
                item.target = self
                item.action = #selector(captureCompanion(_:))
                item.representedObject = device.deviceId

                // Custom view: iPhone icon + name + small status dot on the right
                let menuWidth = menu.size.width > 0 ? menu.size.width : 320
                let rowView = CompanionMenuRowView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 22))
                rowView.autoresizingMask = [.width]
                rowView.deviceId = device.deviceId
                rowView.onTap = { [weak self] id in
                    self?.statusItem.menu?.cancelTracking()
                    self?.performCompanionScreenshot(deviceId: id)
                }

                let iconView = NSImageView(frame: NSRect(x: 14, y: 3, width: 14, height: 14))
                iconView.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: nil)
                iconView.contentTintColor = .secondaryLabelColor
                rowView.addSubview(iconView)

                let label = NSTextField(labelWithString: device.deviceName)
                label.font = NSFont.menuFont(ofSize: 14)
                label.textColor = .labelColor
                label.frame = NSRect(x: 34, y: 1, width: 180, height: 18)
                rowView.addSubview(label)

                let dot = NSView(frame: NSRect(x: rowView.frame.width - 20, y: 7, width: 8, height: 8))
                dot.autoresizingMask = [.minXMargin]
                dot.wantsLayer = true
                dot.layer?.cornerRadius = 4
                dot.layer?.backgroundColor = isConnected ? NSColor.systemGreen.cgColor : NSColor.systemGray.withAlphaComponent(0.4).cgColor
                rowView.addSubview(dot)

                item.view = rowView
                menu.addItem(item)
            }
        }

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

    private func performCompanionScreenshot(deviceId: String? = nil) {
        let targetId: String
        if let id = deviceId {
            targetId = id
        } else if let first = RustBridge.shared.listCompanions().first {
            targetId = first.device_id
        } else if let first = PairedDeviceStore.shared.devices.first {
            targetId = first.deviceId
        } else {
            ToastNotification.show("No iPhone connected")
            return
        }

        // Close any existing preview for a different device
        companionPreview?.close()
        companionPreview = nil

        // Check if this specific device is connected AND has an active broadcast
        // (broadcast extension registers as a separate connection with same device_id)
        let connectedDevices = RustBridge.shared.listCompanions()
        let connectedIds = Set(connectedDevices.map { $0.device_id })
        let isConnected = connectedIds.contains(targetId)
        let hasLiveFrames = RustBridge.shared.companionLatestFrame(deviceId: targetId) != nil

        if isConnected && hasLiveFrames {
            openCompanionPreview(deviceId: targetId)
        } else if isConnected {
            // Connected but no frames — trigger broadcast and wait
            ToastNotification.show("Starting broadcast — confirm on device")

            DispatchQueue.global(qos: .utility).async {
                let _ = RustBridge.shared.companionScreenshot(deviceId: targetId)
            }

            pollForFrames(deviceId: targetId)
        } else {
            // Not connected — device is offline
            let deviceName = PairedDeviceStore.shared.devices.first(where: { $0.deviceId == targetId })?.deviceName ?? "Device"
            ToastNotification.show("\(deviceName) is not connected — open companion app on that device")
        }
    }

    private func pollForFrames(deviceId: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var attempts = 0
            while attempts < 60 {
                Thread.sleep(forTimeInterval: 0.5)
                if RustBridge.shared.companionLatestFrame(deviceId: deviceId) != nil {
                    DispatchQueue.main.async {
                        self.openCompanionPreview(deviceId: deviceId)
                    }
                    return
                }
                attempts += 1
            }
            DispatchQueue.main.async {
                ToastNotification.show("Broadcast didn't start — please confirm on device")
            }
        }
    }

    private func openCompanionPreview(deviceId: String) {
        companionPreview?.close()
        companionPreview = nil

        let preview = CompanionPreviewWindow(deviceId: deviceId)
        preview.onCapture = { [weak self] imageData, label in
            self?.companionPreview = nil
            let isGif = label.contains("GIF")
            let filePath = self?.saveCompanionCapture(imageData, isGif: isGif) ?? ""
            ScreenshotHistory.shared.add(imageData: imageData, filePath: filePath)
            self?.rebuildMenu()
            if isGif {
                ClipboardManager.copyFileAsFinderFull(filePath)
            } else {
                ClipboardManager.copyImage(imageData)
            }
            CapturePreview.show(imageData: imageData, filePath: filePath, label: label)
        }
        companionPreview = preview
        preview.show()
    }

    private func saveCompanionCapture(_ data: Data, isGif: Bool = false) -> String {
        let dir = NSHomeDirectory() + "/.screenshottool/screenshots"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let ext = isGif ? "gif" : "png"
        let filename = "\(formatter.string(from: Date())).\(ext)"
        let path = (dir as NSString).appendingPathComponent(filename)
        try? data.write(to: URL(fileURLWithPath: path))
        return path
    }

    @objc private func captureCompanion(_ sender: NSMenuItem) {
        guard let deviceId = sender.representedObject as? String else { return }
        performCompanionScreenshot(deviceId: deviceId)
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
        overlay.onCompanionDevice = { [weak self] deviceId in
            self?.performCompanionScreenshot(deviceId: deviceId)
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

        var frameTimer: Timer?
        var clickAnimator: ClickAnimator?

        pill.onStart = {
            let animator = ClickAnimator()
            animator.start()
            clickAnimator = animator

            let fps = 10
            frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / Double(fps), repeats: true) { _ in
                let _ = RustBridge.shared.gifAddFrame(sessionId, region: region)
            }
        }

        pill.onStop = { [weak self] in
            frameTimer?.invalidate()
            clickAnimator?.stop()
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

        pill.onCancel = {
            pill.close()
            let _ = RustBridge.shared.gifFinish(sessionId)
        }

        pill.show()
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

// MARK: - Companion menu row with click support + hover highlight

class CompanionMenuRowView: NSView {
    var deviceId: String = ""
    var onTap: ((String) -> Void)?
    private var isHighlighted = false

    override func mouseUp(with event: NSEvent) {
        onTap?(deviceId)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(rect: bounds).fill()
        }
        super.draw(dirtyRect)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        // Update label colors for highlighted state
        for sub in subviews {
            if let label = sub as? NSTextField {
                label.textColor = .white
            }
            if let iv = sub as? NSImageView {
                iv.contentTintColor = .white
            }
        }
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        for sub in subviews {
            if let label = sub as? NSTextField {
                label.textColor = .labelColor
            }
            if let iv = sub as? NSImageView {
                iv.contentTintColor = .secondaryLabelColor
            }
        }
        needsDisplay = true
    }
}
