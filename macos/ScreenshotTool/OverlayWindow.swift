import Cocoa

// MARK: - Single-screen overlay panel (one per display)

class ScreenOverlayPanel: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hasShadow = false
        self.isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Multi-screen overlay coordinator

class OverlayWindow {
    var onScreenshot: ((CGRect) -> Void)?
    var onGifStart: ((CGRect) -> Void)?
    var onDiffBefore: ((CGRect) -> Void)?
    var onDiffAfter: ((CGRect) -> Void)?
    var onCompanionDevice: ((String) -> Void)?

    private let mode: OverlayMode
    private var panels: [ScreenOverlayPanel] = []
    private var regionSelectors: [RegionSelectorView] = []
    private var modePicker: ModePickerPanel!
    private var selectedCaptureMode: CaptureMode = .screenshot
    /// Saved region in global AppKit coordinates, used to pre-select for diff-after
    var savedRegion: CGRect?

    init(mode: OverlayMode, preselectedMode: CaptureMode? = nil) {
        self.mode = mode

        if mode == .diffAfter {
            selectedCaptureMode = .diff
        } else if let preselected = preselectedMode {
            selectedCaptureMode = preselected
        }

        // Create one overlay panel per screen
        for screen in NSScreen.screens {
            let panel = ScreenOverlayPanel(screen: screen)

            let selector = RegionSelectorView(frame: NSRect(origin: .zero, size: screen.frame.size))
            selector.mode = mode
            selector.onRegionSelected = { [weak self] localRect in
                // Convert from view-local coordinates to global screen coordinates
                var globalRect = CGRect(
                    x: screen.frame.origin.x + localRect.origin.x,
                    y: screen.frame.origin.y + localRect.origin.y,
                    width: localRect.width,
                    height: localRect.height
                )
                // If selection reaches near the top of screen, extend to include menu bar
                let menuBarThreshold: CGFloat = 40
                let distanceToTop = screen.frame.maxY - globalRect.maxY
                if distanceToTop < menuBarThreshold && distanceToTop > 0 {
                    globalRect.size.height += distanceToTop
                }
                self?.handleRegionSelected(globalRect)
            }
            selector.onKeyDown = { [weak self] event in
                return self?.handleKeyDown(event) ?? false
            }
            panel.contentView = selector

            panels.append(panel)
            regionSelectors.append(selector)
        }

        // Mode picker on the main screen
        modePicker = ModePickerPanel(initialMode: selectedCaptureMode)
        modePicker.isReleasedWhenClosed = false
        modePicker.onModeSelected = { [weak self] captureMode in
            self?.selectedCaptureMode = captureMode
            self?.regionSelectors.forEach { $0.updateHint(for: captureMode) }
        }
        modePicker.onCompanionDeviceSelected = { [weak self] deviceId in
            self?.selectedCaptureMode = .companion
            self?.hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self?.onCompanionDevice?(deviceId)
            }
        }
        modePicker.onCancel = { [weak self] in
            self?.hide()
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)

        for panel in panels {
            panel.orderFrontRegardless()
        }
        modePicker.orderFront(nil)

        // Make the main screen's panel key and its selector first responder
        if let mainPanel = panels.first {
            mainPanel.makeKeyAndOrderFront(nil)
            mainPanel.makeFirstResponder(mainPanel.contentView)
        }
        NSCursor.crosshair.set()

        // Pre-select saved region (e.g. diff-after reuses the diff-before region)
        if let globalRect = savedRegion {
            applySavedRegion(globalRect)
        }
    }

    private func applySavedRegion(_ globalRect: CGRect) {
        // Find which screen contains this region and set it on the matching selector
        for (i, screen) in NSScreen.screens.enumerated() where i < panels.count {
            if screen.frame.intersects(globalRect) {
                // Convert global coordinates to view-local coordinates
                let localRect = CGRect(
                    x: globalRect.origin.x - screen.frame.origin.x,
                    y: globalRect.origin.y - screen.frame.origin.y,
                    width: globalRect.width,
                    height: globalRect.height
                )
                regionSelectors[i].preselect(rect: localRect)

                // Make this screen's panel key so Enter works
                panels[i].makeKeyAndOrderFront(nil)
                panels[i].makeFirstResponder(regionSelectors[i])
                break
            }
        }
    }

    func hide() {
        for panel in panels {
            panel.makeFirstResponder(nil)
            panel.orderOut(nil)
        }
        modePicker.orderOut(nil)
        NSCursor.arrow.set()
    }

    /// Forward key events from any panel to the mode picker
    func handleKeyDown(_ event: NSEvent) -> Bool {
        return modePicker.handleKeyDown(event)
    }

    private func handleRegionSelected(_ rect: CGRect) {
        let captureMode = selectedCaptureMode
        let overlayMode = mode

        // Hide everything so overlay doesn't appear in the capture
        hide()

        // Wait for the window server to fully remove our overlay windows
        // before taking the screenshot
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            switch captureMode {
            case .screenshot: self?.onScreenshot?(rect)
            case .gif: self?.onGifStart?(rect)
            case .diff:
                if overlayMode == .diffAfter {
                    self?.onDiffAfter?(rect)
                } else {
                    self?.onDiffBefore?(rect)
                }
            case .companion:
                // Handled by onModeSelected, not by region selection
                break
            }
        }
    }
}
