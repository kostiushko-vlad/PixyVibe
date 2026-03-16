import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    private var isDiffPending = false
    private var diffRegion: CGRect?
    private var overlayWindow: OverlayWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("PixyVibe: applicationDidFinishLaunching called")
        RustBridge.shared.initialize()
        NSLog("PixyVibe: Rust core initialized")

        setupStatusItem()

        hotkeyManager = HotkeyManager()
        hotkeyManager.onHotkeyPressed = { [weak self] in
            self?.handleHotkey()
        }
        hotkeyManager.register()

        NSApp.setActivationPolicy(.accessory)

        NotificationCenter.default.addObserver(
            self, selector: #selector(historyChanged),
            name: .screenshotHistoryChanged, object: nil
        )
    }

    @objc private func historyChanged() {
        rebuildMenu()
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
        menu.items.last?.keyEquivalent = "6"
        menu.items.last?.target = self

        // History section
        let history = ScreenshotHistory.shared.entries
        if !history.isEmpty {
            menu.addItem(NSMenuItem.separator())

            let headerItem = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            headerItem.attributedTitle = NSAttributedString(
                string: "Recent Captures",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
            menu.addItem(headerItem)

            for (index, entry) in history.enumerated() {
                let item = NSMenuItem()
                item.tag = index
                item.target = self
                item.action = #selector(historyItemClicked(_:))

                // Build attributed title with thumbnail
                let view = HistoryMenuItemView(entry: entry)
                item.view = view
                menu.addItem(item)
            }

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
        handleHotkey()
    }

    @objc private func historyItemClicked(_ sender: NSMenuItem) {
        let index = sender.tag
        let entries = ScreenshotHistory.shared.entries
        guard index >= 0, index < entries.count else { return }
        let entry = entries[index]
        ClipboardManager.copyImage(entry.imageData)
        ToastNotification.show("Copied to clipboard ✓")
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
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Hotkey / Overlay

    private func handleHotkey() {
        if isDiffPending {
            showOverlay(mode: .diffAfter, savedRegion: diffRegion)
        } else {
            showOverlay(mode: .normal)
        }
    }

    private func showOverlay(mode: OverlayMode, savedRegion: CGRect? = nil) {
        overlayWindow?.hide()

        let overlay = OverlayWindow(mode: mode)
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
        ToastNotification.show("Before captured — make changes, then press ⇧⌘6")
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
        // Refresh the menu each time it opens so history is current
        rebuildMenu()
    }
}

// MARK: - OverlayMode

enum OverlayMode {
    case normal
    case diffAfter
}

// MARK: - History Menu Item View

class HistoryMenuItemView: NSView {
    private let entry: ScreenshotEntry

    init(entry: ScreenshotEntry) {
        self.entry = entry
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 52))
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private var isHighlighted = false

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            bounds.fill()
        }
    }

    private func setupView() {
        let hStack = NSStackView()
        hStack.orientation = .horizontal
        hStack.spacing = 10
        hStack.alignment = .centerY
        hStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hStack)

        NSLayoutConstraint.activate([
            hStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            hStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            hStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            hStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        // Thumbnail
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 0.5
        imageView.layer?.borderColor = NSColor.separatorColor.cgColor

        if let thumb = entry.thumbnail(maxSize: 40) {
            imageView.image = thumb
        }
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 52),
            imageView.heightAnchor.constraint(equalToConstant: 40),
        ])
        hStack.addArrangedSubview(imageView)

        // Text stack
        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let nameLabel = NSTextField(labelWithString: entry.fileName)
        nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = isHighlighted ? .white : .labelColor
        nameLabel.lineBreakMode = .byTruncatingMiddle

        let timeLabel = NSTextField(labelWithString: entry.timeAgo)
        timeLabel.font = NSFont.systemFont(ofSize: 10)
        timeLabel.textColor = isHighlighted ? .white.withAlphaComponent(0.8) : .secondaryLabelColor

        textStack.addArrangedSubview(nameLabel)
        textStack.addArrangedSubview(timeLabel)
        hStack.addArrangedSubview(textStack)

        // Copy icon on the right
        let copyIcon = NSImageView(image: NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Copy")!)
        copyIcon.contentTintColor = .secondaryLabelColor
        copyIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            copyIcon.widthAnchor.constraint(equalToConstant: 16),
            copyIcon.heightAnchor.constraint(equalToConstant: 16),
        ])
        hStack.addArrangedSubview(copyIcon)
    }

    // Handle mouse tracking for highlight
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
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        // Find our menu item and trigger its action
        guard let menuItem = enclosingMenuItem else { return }
        menuItem.menu?.cancelTracking()
        if let target = menuItem.target, let action = menuItem.action {
            NSApp.sendAction(action, to: target, from: menuItem)
        }
    }
}
