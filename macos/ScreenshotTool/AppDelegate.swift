import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    private var isDiffPending = false
    private var diffRegion: CGRect?
    private var overlayWindow: OverlayWindow?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var permissionAlertWindow: NSWindow?
    private var editor = ImageEditorWindow()
    private var companionPreview: CompanionPreviewWindow?
    private var trayPanel: TrayPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("PixyVibe: applicationDidFinishLaunching called")
        RustBridge.shared.initialize()
        NSLog("PixyVibe: Rust core initialized")

        // Force dark appearance globally
        NSApp.appearance = NSAppearance(named: .darkAqua)

        setupStatusItem()

        hotkeyManager = HotkeyManager()
        hotkeyManager.onAction = { [weak self] action in
            self?.handleAction(action)
        }

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

        if UserDefaults.standard.bool(forKey: "onboardingComplete") {
            hotkeyManager.register()
            checkPermissionsPostOnboarding()
        } else {
            showOnboarding()
        }
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
            button.action = #selector(statusItemClicked)
            button.target = self
        }
    }

    @objc private func statusItemClicked() {
        if let panel = trayPanel, panel.isVisible {
            dismissTray()
            return
        }
        showTray()
    }

    private func showTray() {
        dismissTray()

        // Refresh companion devices
        let connectedDevices = RustBridge.shared.listCompanions()
        for device in connectedDevices {
            let name = device.device_name.replacingOccurrences(of: " (Broadcast)", with: "")
            PairedDeviceStore.shared.upsert(deviceId: device.device_id, deviceName: name)
        }
        let connectedIds = Set(connectedDevices.map { $0.device_id })
        var seenIds = Set<String>()
        let pairedDevices = PairedDeviceStore.shared.devices.filter { seenIds.insert($0.deviceId).inserted }
        let history = ScreenshotHistory.shared.entries

        let content = TrayContentView(
            pairedDevices: pairedDevices,
            connectedDeviceIds: connectedIds,
            history: history,
            onCaptureRegion: { [weak self] in
                self?.dismissTray()
                self?.captureRegion()
            },
            onSelectDevice: { [weak self] deviceId in
                self?.dismissTray()
                self?.performCompanionScreenshot(deviceId: deviceId)
            },
            onRemoveDevice: { [weak self] deviceId in
                PairedDeviceStore.shared.remove(deviceId: deviceId)
                self?.dismissTray()
                self?.showTray()
            },
            onClickHistory: { [weak self] index in
                self?.dismissTray()
                self?.openHistoryEntry(at: index)
            },
            onCopyHistory: { [weak self] index in
                let entry = history[index]
                if entry.filePath.hasSuffix(".gif") {
                    ClipboardManager.copyFileAsFinderFull(entry.filePath)
                } else {
                    ClipboardManager.copyImage(entry.imageData)
                }
                self?.dismissTray()
                ToastNotification.show("Copied to clipboard", icon: "doc.on.doc")
            },
            onRemoveHistory: { [weak self] index in
                let entry = history[index]
                ScreenshotHistory.shared.remove(filePath: entry.filePath)
                NotificationCenter.default.post(name: .screenshotHistoryChanged, object: nil)
                self?.dismissTray()
                self?.showTray()
            },
            onClearHistory: { [weak self] in
                ScreenshotHistory.shared.clear()
                self?.dismissTray()
            },
            onOpenFolder: { [weak self] in
                self?.dismissTray()
                self?.openScreenshotsFolder()
            },
            onSettings: { [weak self] in
                self?.dismissTray()
                self?.openSettings()
            },
            onQuit: { [weak self] in
                self?.dismissTray()
                self?.quitApp()
            }
        )

        let hostingView = FirstClickHostingView(rootView: content)
        let fittingSize = hostingView.fittingSize
        let panelWidth = max(fittingSize.width, 320)
        let panelHeight = min(fittingSize.height, 600)

        // Position below the status item button
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonFrame = button.convert(button.bounds, to: nil)
        let screenPoint = buttonWindow.convertToScreen(buttonFrame)

        let panelFrame = NSRect(
            x: screenPoint.midX - panelWidth / 2,
            y: screenPoint.minY - panelHeight - 4,
            width: panelWidth,
            height: panelHeight
        )

        let panel = TrayPanel(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.acceptsMouseMovedEvents = true
        panel.onDismiss = { [weak self] in self?.dismissTray() }

        hostingView.frame = NSRect(origin: .zero, size: panelFrame.size)
        panel.contentView = hostingView
        panel.makeKeyAndOrderFront(nil)

        // Animate in: start slightly above + transparent, slide down + fade in
        let startFrame = NSRect(
            x: panelFrame.origin.x,
            y: panelFrame.origin.y + 6,
            width: panelFrame.width,
            height: panelFrame.height
        )
        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        trayPanel = panel

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(panelFrame, display: true)
            panel.animator().alphaValue = 1
        }
    }

    private func dismissTray() {
        guard let panel = trayPanel else { return }
        let exitFrame = NSRect(
            x: panel.frame.origin.x,
            y: panel.frame.origin.y + 4,
            width: panel.frame.width,
            height: panel.frame.height
        )
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(exitFrame, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            if self?.trayPanel === panel { self?.trayPanel = nil }
        })
    }

    private func rebuildMenu() {
        // No-op — tray is rebuilt on each open now
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
            ToastNotification.show("No iPhone connected", icon: "iphone.slash")
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
            // Connected but no frames — open preview in waiting state, trigger broadcast
            openCompanionPreview(deviceId: targetId, waitingForBroadcast: true)

            DispatchQueue.global(qos: .utility).async {
                let _ = RustBridge.shared.companionScreenshot(deviceId: targetId)
            }
        } else {
            // Not connected — open preview in disconnected state
            openCompanionPreview(deviceId: targetId, notConnected: true)
        }
    }

    private func openCompanionPreview(deviceId: String, waitingForBroadcast: Bool = false, notConnected: Bool = false) {
        companionPreview?.close()
        companionPreview = nil

        let preview = CompanionPreviewWindow(deviceId: deviceId, waitingForBroadcast: waitingForBroadcast, notConnected: notConnected)
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
        let dir = NSHomeDirectory() + "/.pixyvibe/captures"
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
            ToastNotification.show("Saved and copied to clipboard", icon: "checkmark.circle")
        }, onRemove: { [weak self] in
            try? FileManager.default.removeItem(atPath: entry.filePath)
            ScreenshotHistory.shared.remove(filePath: entry.filePath)
            NotificationCenter.default.post(name: .screenshotHistoryChanged, object: nil)
            self?.rebuildMenu()
            ToastNotification.show("Deleted", icon: "trash")
        })
    }

    @objc private func clearHistory() {
        ScreenshotHistory.shared.clear()
        rebuildMenu()
    }

    @objc private func openScreenshotsFolder() {
        let path = NSHomeDirectory() + "/.pixyvibe/captures"
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingView = FirstClickHostingView(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "PixyVibe Settings"
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = PV.Colors.nsBase
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        if let window = onboardingWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let onboardingView = OnboardingView {
            UserDefaults.standard.set(true, forKey: "onboardingComplete")
            self.hotkeyManager.register()
            self.onboardingWindow?.close()
            self.onboardingWindow = nil
        }
        let hostingView = FirstClickHostingView(rootView: onboardingView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Welcome to PixyVibe"
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = PV.Colors.nsBase
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        onboardingWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func checkPermissionsPostOnboarding() {
        let hasScreen = CGPreflightScreenCaptureAccess()
        let hasAccessibility = AXIsProcessTrusted()
        guard !hasScreen || !hasAccessibility else { return }

        // Show minimal permission alert
        if let window = permissionAlertWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let alertView = PermissionAlertView {
            self.permissionAlertWindow?.close()
            self.permissionAlertWindow = nil
        }
        let hostingView = FirstClickHostingView(rootView: alertView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 360),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "PixyVibe Permissions"
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = PV.Colors.nsBase
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        permissionAlertWindow = window

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
            ToastNotification.show("Screenshot failed", icon: "xmark.circle")
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
            ToastNotification.show("Failed to start recording", icon: "xmark.circle")
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
                ToastNotification.show("GIF encoding failed", icon: "xmark.circle")
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
            ToastNotification.show("Failed to capture 'before'", icon: "xmark.circle")
            return
        }
        isDiffPending = true
        diffRegion = region
        updateTrayIcon()
        let shortcut = ShortcutStore.shared.diff.displayString
        ToastNotification.show("Before captured — make changes, then press \(shortcut)", icon: "checkmark.circle")
    }

    private func performDiffAfter(region: CGRect) {
        guard let result = RustBridge.shared.diffCompare(region: region) else {
            ToastNotification.show("Diff comparison failed", icon: "xmark.circle")
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

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow {
            settingsWindow = nil
        } else if window === onboardingWindow {
            // User closed via close button — mark complete anyway, don't trap them
            if !UserDefaults.standard.bool(forKey: "onboardingComplete") {
                UserDefaults.standard.set(true, forKey: "onboardingComplete")
                hotkeyManager.register()
            }
            onboardingWindow = nil
        } else if window === permissionAlertWindow {
            permissionAlertWindow = nil
        }
    }
}

// MARK: - OverlayMode

enum OverlayMode {
    case normal
    case diffAfter
}

// MARK: - Custom Tray Panel (replaces NSMenu for full styling control)

// MARK: - First-click-through hosting view

class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

class TrayPanel: NSPanel {
    var onDismiss: (() -> Void)?
    private var clickMonitor: Any?

    override var canBecomeKey: Bool { true }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        // Dismiss when clicking outside
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.onDismiss?()
        }
    }

    override func orderOut(_ sender: Any?) {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        super.orderOut(sender)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDismiss?(); return }
        super.keyDown(with: event)
    }
}

// MARK: - Tray Content (SwiftUI)

struct TrayContentView: View {
    let pairedDevices: [PairedDevice]
    let connectedDeviceIds: Set<String>
    let history: [ScreenshotEntry]
    let onCaptureRegion: () -> Void
    let onSelectDevice: (String) -> Void
    let onRemoveDevice: (String) -> Void
    let onClickHistory: (Int) -> Void
    let onCopyHistory: (Int) -> Void
    let onRemoveHistory: (Int) -> Void
    let onClearHistory: () -> Void
    let onOpenFolder: () -> Void
    let onSettings: () -> Void
    let onQuit: () -> Void

    private let gridColumns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            // Devices
            if !pairedDevices.isEmpty {
                HStack {
                    Text("DEVICES")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundColor(PV.Colors.textSecondary.opacity(0.5))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 2)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(pairedDevices, id: \.deviceId) { device in
                            let isConnected = connectedDeviceIds.contains(device.deviceId)
                            TrayDeviceChip(device: device, isConnected: isConnected, onSelect: { onSelectDevice(device.deviceId) }, onRemove: { onRemoveDevice(device.deviceId) })
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }

                Rectangle()
                    .fill(PV.Colors.border.opacity(0.4))
                    .frame(height: 0.5)
                    .padding(.horizontal, 12)
            }

            // Recent captures
            HStack {
                Text("RECENT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundColor(PV.Colors.textSecondary.opacity(0.5))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 2)

            if !history.isEmpty {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 8) {
                        ForEach(Array(history.enumerated()), id: \.offset) { index, entry in
                            TrayGridCell(
                                entry: entry,
                                onClick: { onClickHistory(index) },
                                onCopy: { onCopyHistory(index) },
                                onRemove: { onRemoveHistory(index) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 340)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 24))
                        .foregroundStyle(PV.Gradients.accent.opacity(0.4))
                    Text("No captures yet")
                        .font(.system(size: 12))
                        .foregroundColor(PV.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }

            Rectangle()
                .fill(PV.Colors.border.opacity(0.4))
                .frame(height: 0.5)
                .padding(.horizontal, 12)

            // Bottom action bar
            HStack(spacing: 8) {
                Button(action: onCaptureRegion) {
                    HStack(spacing: 5) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Capture")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PV.Gradients.accent, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Spacer()

                if !history.isEmpty {
                    TrayIconBtn(icon: "trash", tip: "Clear History", action: onClearHistory)
                }
                TrayIconBtn(icon: "folder", tip: "Open Folder", action: onOpenFolder)
                TrayIconBtn(icon: "gearshape", tip: "Settings", action: onSettings)
                TrayIconBtn(icon: "power", tip: "Quit", action: onQuit)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .frame(width: 340)
        .padding(.bottom, 4)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(PV.Colors.base)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [PV.Gradients.accentSolid.opacity(0.06), Color.clear],
                                startPoint: .top, endPoint: .center
                            )
                        )
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    LinearGradient(
                        colors: [PV.Gradients.accentSolid.opacity(0.25), PV.Border.thinColor, PV.Border.thinColor],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: PV.Gradients.accentSolid.opacity(0.08), radius: 30, y: 4)
        .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
    }
}

// MARK: - Tray Icon Button

struct TrayIconBtn: View {
    let icon: String
    let tip: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(hover ? PV.Colors.textPrimary : PV.Colors.textSecondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hover ? PV.Gradients.accentSolid.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(tip)
        .onHover { hover = $0 }
        .animation(PV.Anim.hover, value: hover)
    }
}

// MARK: - Grid Cell (thumbnail card)

struct TrayGridCell: View {
    let entry: ScreenshotEntry
    let onClick: () -> Void
    let onCopy: () -> Void
    let onRemove: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail
            Button(action: onClick) {
                if let thumb = entry.thumbnail(maxSize: 160) {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 80)
                        .frame(maxWidth: .infinity)
                        .clipped()
                } else {
                    PV.Colors.surfaceHigh
                        .frame(height: 80)
                }
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottomTrailing) {
                if hover {
                    HStack(spacing: 4) {
                        Button(action: onCopy) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 22, height: 22)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .help("Copy")

                        Button(action: onRemove) {
                            Image(systemName: "trash")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 22, height: 22)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .help("Delete")
                    }
                    .padding(5)
                    .transition(.opacity)
                }
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 8))

            // Info bar
            VStack(alignment: .leading, spacing: 1) {
                Text((entry.filePath as NSString).lastPathComponent)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(PV.Colors.textPrimary)
                    .lineLimit(1)
                Text(entry.timeAgo)
                    .font(.system(size: 8))
                    .foregroundColor(PV.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
        }
        .background(PV.Colors.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    hover ? AnyShapeStyle(PV.Gradients.accent.opacity(0.45)) : AnyShapeStyle(Color.white.opacity(0.06)),
                    lineWidth: hover ? 1 : 0.5
                )
        )
        .shadow(color: hover ? PV.Gradients.accentSolid.opacity(0.15) : .clear, radius: 8)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .animation(PV.Anim.snappy, value: hover)
    }
}

// MARK: - Device Chip

struct TrayDeviceChip: View {
    let device: PairedDevice
    let isConnected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5) {
                Circle()
                    .fill(isConnected ? Color(hex: 0x10B981) : PV.Colors.border)
                    .frame(width: 6, height: 6)
                    .shadow(color: isConnected ? Color(hex: 0x10B981).opacity(0.5) : .clear, radius: 3)
                Image(systemName: "iphone")
                    .font(.system(size: 10))
                    .foregroundColor(PV.Colors.textSecondary)
                Text(device.deviceName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(hover ? PV.Colors.textPrimary : PV.Colors.textSecondary)
                    .lineLimit(1)
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(PV.Colors.textSecondary)
                        .frame(width: 14, height: 14)
                        .background(Color.white.opacity(hover ? 0.08 : 0), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Remove device")
                .opacity(hover ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hover ? PV.Gradients.accentSolid.opacity(0.08) : PV.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(hover ? PV.Gradients.accentSolid.opacity(0.25) : Color.white.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(PV.Anim.hover, value: hover)
    }
}
