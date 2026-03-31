import Cocoa
import SwiftUI

enum CompanionCaptureMode: String {
    case screenshot = "screenshot"
    case gif = "gif"

    static var saved: CompanionCaptureMode {
        let raw = UserDefaults.standard.string(forKey: "companion_capture_mode") ?? "screenshot"
        return CompanionCaptureMode(rawValue: raw) ?? .screenshot
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: "companion_capture_mode")
    }
}

enum CompanionRecordingState {
    case idle
    case ready
    case recording
}

enum CompanionAreaMode: String {
    case fullScreen = "full"
    case region = "region"

    static var saved: CompanionAreaMode {
        let raw = UserDefaults.standard.string(forKey: "companion_area_mode") ?? "region"
        return CompanionAreaMode(rawValue: raw) ?? .region
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: "companion_area_mode")
    }
}

/// Window that shows a live broadcast from a companion device.
/// The user can drag to select a region for screenshot or GIF recording.
class CompanionPreviewWindow {
    var onCapture: ((Data, String) -> Void)?

    private var window: NSWindow?
    private var imageView: NSImageView?
    private var regionSelector: CompanionRegionSelector?
    // toolbar is now embedded — see embeddedToolbarView
    private var frameTimer: Timer?
    private let deviceId: String
    private var currentFrameData: Data?
    private var captureMode: CompanionCaptureMode = .saved
    private var areaMode: CompanionAreaMode = .saved

    // GIF recording state
    private var gifRegion: NSRect?
    private var gifFrames: [CGImage] = []
    private var isRecordingGif = false
    private var recordingState: CompanionRecordingState = .idle
    private var gifEscMonitor: Any?

    private var waitingForBroadcast: Bool
    private var notConnected: Bool
    private var waitingOverlay: NSView?

    init(deviceId: String, waitingForBroadcast: Bool = false, notConnected: Bool = false) {
        self.deviceId = deviceId
        self.waitingForBroadcast = waitingForBroadcast
        self.notConnected = notConnected
    }

    func show() {
        let initialFrame = RustBridge.shared.companionLatestFrame(deviceId: deviceId)
        let initialImage = initialFrame.flatMap { NSImage(data: $0) }
        let imageSize = initialImage?.size ?? NSSize(width: 390, height: 844)

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let maxHeight = screen.frame.height * 0.75
        let scale = min(1.0, maxHeight / imageSize.height)
        let windowSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)

        let windowFrame = NSRect(
            x: screen.frame.midX - windowSize.width / 2,
            y: screen.frame.midY - windowSize.height / 2,
            width: windowSize.width,
            height: windowSize.height
        )

        let win = NSWindow(
            contentRect: windowFrame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "iPhone Live View — drag to capture"
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.backgroundColor = NSColor(hex: 0x0D0F14)

        let iv = NSImageView(frame: NSRect(origin: .zero, size: windowSize))
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.autoresizingMask = [.width, .height]
        if let img = initialImage {
            iv.image = img
            currentFrameData = initialFrame
        }

        let selector = CompanionRegionSelector(frame: NSRect(origin: .zero, size: windowSize))
        selector.autoresizingMask = [.width, .height]
        selector.isDimmed = (captureMode == .gif && areaMode == .region)
        selector.usesCrosshair = !(captureMode == .gif && areaMode == .fullScreen)
        selector.onRegionSelected = { [weak self] rect in
            self?.handleRegionSelected(rect)
        }
        selector.onClicked = { [weak self] in
            self?.handleFullScreenAction()
        }

        let contentView = NSView(frame: NSRect(origin: .zero, size: windowSize))
        contentView.addSubview(iv)
        contentView.addSubview(selector)
        win.contentView = contentView

        self.window = win
        self.imageView = iv
        self.regionSelector = selector

        // Clean up when user closes with red button
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            self?.close()
        }

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !(captureMode == .gif && areaMode == .fullScreen) {
            NSCursor.crosshair.set()
        }

        // Show waiting overlay if broadcast hasn't started yet
        if waitingForBroadcast {
            let devId = deviceId
            let overlay = NSHostingView(rootView: WaitingForBroadcastView(onRetry: {
                DispatchQueue.global(qos: .utility).async {
                    let _ = RustBridge.shared.companionScreenshot(deviceId: devId)
                }
            }))
            overlay.frame = NSRect(origin: .zero, size: windowSize)
            overlay.autoresizingMask = [.width, .height]
            contentView.addSubview(overlay)
            waitingOverlay = overlay
            selector.isHidden = true
        }

        // Show not-connected overlay
        if notConnected {
            let deviceName = PairedDeviceStore.shared.devices.first(where: { $0.deviceId == deviceId })?.deviceName ?? "Device"
            let overlay = NSHostingView(rootView: DeviceNotConnectedView(deviceName: deviceName))
            overlay.frame = NSRect(origin: .zero, size: windowSize)
            overlay.autoresizingMask = [.width, .height]
            contentView.addSubview(overlay)
            waitingOverlay = overlay
            selector.isHidden = true
        }

        // Toolbar as child window attached to bottom
        showToolbar(attachedTo: win)

        // Auto-show Start button if saved mode is GIF + Full
        if !waitingForBroadcast {
            updateGifFullScreenState()
        }

        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            self?.updateFrame()
        }
    }

    func close() {
        guard window != nil else { return }
        if isRecordingGif { stopGifRecording(cancel: true) }
        else if recordingState == .ready { cancelGifSetup() }
        frameTimer?.invalidate()
        frameTimer = nil
        toolbarPanel?.orderOut(nil)
        toolbarPanel = nil
        NotificationCenter.default.removeObserver(self)
        window?.orderOut(nil)
        window = nil
        NSCursor.arrow.set()
    }

    private var toolbarPanel: CompanionToolbarPanel?

    private func showToolbar(attachedTo win: NSWindow) {
        rebuildToolbar()
        if let panel = toolbarPanel {
            win.addChildWindow(panel, ordered: .below)
        }
    }

    private func rebuildToolbar() {
        guard let win = window else { return }
        let oldPanel = toolbarPanel

        let content = CompanionToolbarContent(
            selectedMode: captureMode,
            selectedArea: areaMode,
            showAreaToggle: captureMode == .gif && recordingState != .recording,
            recordingState: recordingState,
            onModeChange: { [weak self] mode in
                self?.captureMode = mode
                mode.save()
                self?.updateTitle()
                let isFullGif = mode == .gif && self?.areaMode == .fullScreen
                self?.regionSelector?.usesCrosshair = !isFullGif
                (isFullGif ? NSCursor.arrow : NSCursor.crosshair).set()
                if mode == .screenshot {
                    self?.regionSelector?.isDimmed = false
                } else {
                    self?.regionSelector?.isDimmed = (self?.areaMode == .region)
                }
                if self?.recordingState == .ready { self?.cancelGifSetup() }
                DispatchQueue.main.async {
                    self?.rebuildToolbar()
                    self?.updateGifFullScreenState()
                }
            },
            onAreaChange: { [weak self] area in
                self?.areaMode = area
                area.save()
                self?.updateTitle()
                self?.regionSelector?.isDimmed = (area == .region)
                let isFullGif = self?.captureMode == .gif && area == .fullScreen
                self?.regionSelector?.usesCrosshair = !isFullGif
                (isFullGif ? NSCursor.arrow : NSCursor.crosshair).set()
                if self?.recordingState == .ready { self?.cancelGifSetup() }
                DispatchQueue.main.async {
                    self?.rebuildToolbar()
                    self?.updateGifFullScreenState()
                }
            },
            onStart: { [weak self] in self?.beginGifRecording() },
            onStop: { [weak self] in self?.stopGifRecording() }
        )

        let hosting = NSHostingView(rootView: content)
        let fitting = hosting.fittingSize
        let panelWidth = max(fitting.width, 200)
        let panelHeight = fitting.height

        let panelFrame = NSRect(
            x: win.frame.midX - panelWidth / 2,
            y: win.frame.minY - panelHeight - 4,
            width: panelWidth,
            height: panelHeight
        )

        if let old = oldPanel {
            old.contentView = hosting
            old.setFrame(panelFrame, display: true)
        } else {
            let panel = CompanionToolbarPanel(
                frame: panelFrame,
                mode: captureMode,
                area: areaMode,
                recordingState: recordingState
            )
            panel.contentView = hosting
            panel.setFrame(panelFrame, display: true)
            panel.orderFront(nil)
            toolbarPanel = panel
            win.addChildWindow(panel, ordered: .below)
        }
    }

    private func updateFrame() {
        // If not connected, poll for connection
        if notConnected {
            let connectedIds = Set(RustBridge.shared.listCompanions().map { $0.device_id })
            if connectedIds.contains(deviceId) {
                // Device connected — check for frames
                notConnected = false
                if let data = RustBridge.shared.companionLatestFrame(deviceId: deviceId),
                   let image = NSImage(data: data) {
                    // Has frames — go straight to live view
                    currentFrameData = data
                    imageView?.image = image
                    waitingOverlay?.removeFromSuperview()
                    waitingOverlay = nil
                    regionSelector?.isHidden = false
                    updateTitle()
                    updateGifFullScreenState()
                } else {
                    // Connected but no frames — switch to waiting for broadcast
                    waitingForBroadcast = true
                    let devId = deviceId
                    let newOverlay = NSHostingView(rootView: WaitingForBroadcastView(onRetry: {
                        DispatchQueue.global(qos: .utility).async {
                            let _ = RustBridge.shared.companionScreenshot(deviceId: devId)
                        }
                    }))
                    newOverlay.frame = waitingOverlay?.frame ?? imageView?.bounds ?? .zero
                    newOverlay.autoresizingMask = [.width, .height]
                    waitingOverlay?.removeFromSuperview()
                    window?.contentView?.addSubview(newOverlay)
                    waitingOverlay = newOverlay

                    // Trigger broadcast request
                    DispatchQueue.global(qos: .utility).async {
                        let _ = RustBridge.shared.companionScreenshot(deviceId: devId)
                    }
                }
            }
            return
        }

        guard let data = RustBridge.shared.companionLatestFrame(deviceId: deviceId),
              let image = NSImage(data: data) else { return }
        currentFrameData = data
        imageView?.image = image

        // Dismiss waiting overlay once frames start arriving
        if waitingForBroadcast {
            waitingForBroadcast = false
            waitingOverlay?.removeFromSuperview()
            waitingOverlay = nil
            regionSelector?.isHidden = false
            updateTitle()
            updateGifFullScreenState()
        }

        // If recording GIF, capture a cropped frame
        if let region = gifRegion, isRecordingGif {
            if let cropped = cropCurrentFrame(to: region) {
                gifFrames.append(cropped)
            }
        }
    }

    private func updateTitle() {
        let action = captureMode == .gif ? "record GIF" : "capture"
        if captureMode == .gif && areaMode == .fullScreen {
            window?.title = "iPhone Live View — click to \(action) full screen"
        } else {
            window?.title = "iPhone Live View — drag to \(action)"
        }
    }

    // MARK: - Region handling

    private func handleRegionSelected(_ viewRect: NSRect) {
        switch captureMode {
        case .screenshot:
            captureScreenshot(viewRect)
        case .gif:
            startGifRecording(viewRect)
        }
    }

    private func handleFullScreenAction() {
        guard captureMode == .gif, areaMode == .fullScreen else { return }
        guard let iv = imageView else { return }
        guard recordingState == .idle else { return }
        startGifRecording(iv.bounds)
    }

    /// Auto-show or cancel the Start button based on current mode
    private func updateGifFullScreenState() {
        if captureMode == .gif && areaMode == .fullScreen {
            guard recordingState == .idle else { return }
            guard let iv = imageView else { return }
            startGifRecording(iv.bounds)
        } else if recordingState == .ready {
            cancelGifSetup()
        }
    }

    // MARK: - Screenshot

    private func captureScreenshot(_ viewRect: NSRect) {
        guard let cropped = cropCurrentFrame(to: viewRect) else {
            close()
            return
        }

        let pngData = cgImageToPng(cropped)
        close()
        if let data = pngData {
            onCapture?(data, "iOS Screenshot")
        }
    }

    // MARK: - GIF Recording

    private func startGifRecording(_ viewRect: NSRect) {
        gifRegion = viewRect
        gifFrames = []
        isRecordingGif = false
        recordingState = .ready

        regionSelector?.lockRegion(viewRect)

        // Update toolbar to show Start button
        rebuildToolbar()

        gifEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                if self?.isRecordingGif == true {
                    self?.stopGifRecording()
                } else {
                    self?.cancelGifSetup()
                }
                return nil
            }
            return event
        }
    }

    private func beginGifRecording() {
        isRecordingGif = true
        recordingState = .recording
        regionSelector?.recordingActive = true
        rebuildToolbar()
    }

    private func cancelGifSetup() {
        isRecordingGif = false
        recordingState = .idle
        if let monitor = gifEscMonitor {
            NSEvent.removeMonitor(monitor)
            gifEscMonitor = nil
        }
        regionSelector?.recordingActive = false
        regionSelector?.unlockRegion()
        gifFrames = []
        gifRegion = nil
        rebuildToolbar()
    }

    private func stopGifRecording(cancel: Bool = false) {
        isRecordingGif = false
        recordingState = .idle
        if let monitor = gifEscMonitor {
            NSEvent.removeMonitor(monitor)
            gifEscMonitor = nil
        }
        regionSelector?.recordingActive = false
        regionSelector?.unlockRegion()

        guard !cancel, !gifFrames.isEmpty else {
            gifFrames = []
            gifRegion = nil
            rebuildToolbar()
            return
        }

        let frames = gifFrames
        gifFrames = []
        gifRegion = nil

        // Encode GIF
        close()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let gifData = self?.encodeGif(frames: frames, fps: 10) else {
                DispatchQueue.main.async {
                    ToastNotification.show("GIF encoding failed", icon: "xmark.circle")
                }
                return
            }
            DispatchQueue.main.async {
                self?.onCapture?(gifData, "iOS GIF Recording")
            }
        }
    }

    // MARK: - Image utilities

    private func cropCurrentFrame(to viewRect: NSRect) -> CGImage? {
        guard let frameData = currentFrameData,
              let image = NSImage(data: frameData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let iv = imageView else { return nil }

        let viewSize = iv.bounds.size
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        let viewAspect = viewSize.width / viewSize.height
        let imageAspect = imageWidth / imageHeight

        var displayRect: CGRect
        if imageAspect > viewAspect {
            let displayWidth = viewSize.width
            let displayHeight = displayWidth / imageAspect
            let yOffset = (viewSize.height - displayHeight) / 2
            displayRect = CGRect(x: 0, y: yOffset, width: displayWidth, height: displayHeight)
        } else {
            let displayHeight = viewSize.height
            let displayWidth = displayHeight * imageAspect
            let xOffset = (viewSize.width - displayWidth) / 2
            displayRect = CGRect(x: xOffset, y: 0, width: displayWidth, height: displayHeight)
        }

        let scaleX = imageWidth / displayRect.width
        let scaleY = imageHeight / displayRect.height

        let cropRect = CGRect(
            x: (viewRect.origin.x - displayRect.origin.x) * scaleX,
            y: (viewRect.origin.y - displayRect.origin.y) * scaleY,
            width: viewRect.width * scaleX,
            height: viewRect.height * scaleY
        ).intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

        guard cropRect.width > 1, cropRect.height > 1 else { return nil }

        let flippedCropRect = CGRect(
            x: cropRect.origin.x,
            y: imageHeight - cropRect.origin.y - cropRect.height,
            width: cropRect.width,
            height: cropRect.height
        )

        return cgImage.cropping(to: flippedCropRect)
    }

    private func cgImageToPng(_ cgImage: CGImage) -> Data? {
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return pngData
    }

    private func encodeGif(frames: [CGImage], fps: Int) -> Data? {
        guard let first = frames.first else { return nil }
        let width = first.width
        let height = first.height

        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData,
            "com.compuserve.gif" as CFString,
            frames.count,
            nil
        ) else { return nil }

        let gifProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ] as CFDictionary
        CGImageDestinationSetProperties(dest, gifProperties)

        let frameDelay = 1.0 / Double(fps)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay,
                kCGImagePropertyGIFUnclampedDelayTime: frameDelay,
            ]
        ] as CFDictionary

        for frame in frames {
            // Resize if needed to match first frame dimensions
            if frame.width == width && frame.height == height {
                CGImageDestinationAddImage(dest, frame, frameProperties)
            } else if let resized = resizeCGImage(frame, to: CGSize(width: width, height: height)) {
                CGImageDestinationAddImage(dest, resized, frameProperties)
            }
        }

        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    private func resizeCGImage(_ image: CGImage, to size: CGSize) -> CGImage? {
        guard let ctx = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }
}

// MARK: - Waiting for Broadcast View

struct WaitingForBroadcastView: View {
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            PV.Colors.base

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                Text("Waiting for broadcast...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(PV.Colors.textPrimary)

                Text("Accept the broadcast request on your iPhone")
                    .font(.system(size: 13))
                    .foregroundColor(PV.Colors.textSecondary)
                    .multilineTextAlignment(.center)

                Button(action: onRetry) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                        Text("Request Again")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(PV.Colors.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.clear, in: RoundedRectangle(cornerRadius: PV.Radius.small))
                    .overlay(
                        RoundedRectangle(cornerRadius: PV.Radius.small)
                            .strokeBorder(AnyShapeStyle(PV.Gradients.accent), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(40)
        }
    }
}

struct DeviceNotConnectedView: View {
    let deviceName: String

    var body: some View {
        ZStack {
            PV.Colors.base

            VStack(spacing: 16) {
                Image(systemName: "iphone.slash")
                    .font(.system(size: 36))
                    .foregroundStyle(PV.Gradients.accent.opacity(0.6))

                Text("\(deviceName) is not connected")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PV.Colors.textPrimary)

                Text("Open the PixyVibe companion app on your iPhone to connect.")
                    .font(.system(size: 13))
                    .foregroundColor(PV.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
            .padding(40)
        }
    }
}

struct BroadcastFailedView: View {
    var body: some View {
        ZStack {
            PV.Colors.base

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundColor(Color(hex: 0xF59E0B))

                Text("Broadcast not started")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(PV.Colors.textPrimary)

                Text("The broadcast request was not accepted.\nTry again or check your iPhone.")
                    .font(.system(size: 13))
                    .foregroundColor(PV.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(40)
        }
    }
}

// MARK: - Toolbar Panel

class CompanionToolbarPanel: NSPanel {
    var onModeChanged: ((CompanionCaptureMode) -> Void)?
    var onAreaChanged: ((CompanionAreaMode) -> Void)?
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?

    init(frame: NSRect, mode: CompanionCaptureMode, area: CompanionAreaMode, recordingState: CompanionRecordingState) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .floating + 1
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true

        rebuildContent(mode: mode, area: area, recordingState: recordingState)
    }

    func rebuildContent(mode: CompanionCaptureMode, area: CompanionAreaMode, recordingState: CompanionRecordingState) {
        let content = CompanionToolbarContent(
            selectedMode: mode,
            selectedArea: area,
            showAreaToggle: mode == .gif && recordingState != .recording,
            recordingState: recordingState,
            onModeChange: { [weak self] m in self?.onModeChanged?(m) },
            onAreaChange: { [weak self] a in self?.onAreaChanged?(a) },
            onStart: { [weak self] in self?.onStart?() },
            onStop: { [weak self] in self?.onStop?() }
        )
        let hosting = NSHostingView(rootView: content)

        let fitting = hosting.fittingSize
        let centerX = self.frame.midX
        let newFrame = NSRect(
            x: centerX - fitting.width / 2,
            y: self.frame.origin.y,
            width: fitting.width,
            height: fitting.height
        )
        self.setFrame(newFrame, display: false)
        self.contentView = hosting
    }
}

struct CompanionToolbarContent: View {
    let selectedMode: CompanionCaptureMode
    let selectedArea: CompanionAreaMode
    let showAreaToggle: Bool
    let recordingState: CompanionRecordingState
    let onModeChange: (CompanionCaptureMode) -> Void
    let onAreaChange: (CompanionAreaMode) -> Void
    let onStart: () -> Void
    let onStop: () -> Void

    @State private var elapsed: TimeInterval = 0
    @State private var dotPulse = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            if recordingState == .recording {
                // Recording state: show timer + stop
                Circle()
                    .fill(Color(hex: 0xEF4444))
                    .frame(width: 10, height: 10)
                    .scaleEffect(dotPulse ? 1.4 : 1.0)
                    .opacity(dotPulse ? 0.6 : 1.0)
                    .animation(PV.Anim.pulse, value: dotPulse)
                    .padding(.trailing, 6)
                    .onAppear { dotPulse = true }

                Text("REC \(formatTime(elapsed))")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(PV.Colors.textPrimary)
                    .frame(minWidth: 70, alignment: .leading)

                Spacer().frame(width: 12)

                Button(action: onStop) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill").font(.system(size: 11))
                        Text("Stop").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(PV.Gradients.recording, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            } else {
                // Normal / ready state
                toolbarButton("Screenshot", icon: "camera.viewfinder", mode: .screenshot)
                Divider().frame(height: 20).opacity(0.15)
                toolbarButton("Record GIF", icon: "record.circle", mode: .gif)
                if showAreaToggle {
                    Divider().frame(height: 20).opacity(0.15).padding(.horizontal, 4)
                    areaToggle
                }
                if recordingState == .ready {
                    Divider().frame(height: 20).opacity(0.15).padding(.horizontal, 4)
                    Button(action: onStart) {
                        HStack(spacing: 4) {
                            Image(systemName: "record.circle").font(.system(size: 11))
                            Text("Start").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(PV.Gradients.success, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .pvGlass(cornerRadius: PV.Radius.medium)
        .fixedSize()
        .animation(nil, value: elapsed)
        .animation(nil, value: recordingState == .recording)
        .onReceive(timer) { _ in
            if recordingState == .recording { elapsed += 1 }
        }
    }

    private var areaToggle: some View {
        HStack(spacing: 2) {
            areaButton("Full", icon: "iphone", area: .fullScreen)
            areaButton("Region", icon: "crop", area: .region)
        }
    }

    private func toolbarButton(_ label: String, icon: String, mode: CompanionCaptureMode) -> some View {
        let isSelected = selectedMode == mode
        return Button(action: {
            onModeChange(mode)
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isSelected ? PV.Colors.textPrimary : PV.Colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(PV.Gradients.accentSolid.opacity(isSelected ? 0.15 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? AnyShapeStyle(PV.Gradients.accent) : AnyShapeStyle(Color.clear), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func areaButton(_ label: String, icon: String, area: CompanionAreaMode) -> some View {
        let isSelected = selectedArea == area
        return Button(action: {
            onAreaChange(area)
        }) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 10))
                Text(label).font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.white.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Region Selector for companion preview

class CompanionRegionSelector: NSView {
    var onRegionSelected: ((NSRect) -> Void)?
    var onClicked: (() -> Void)?
    var recordingActive = false { didSet { needsDisplay = true } }
    var isDimmed: Bool = true { didSet { needsDisplay = true } }
    var usesCrosshair: Bool = true { didSet { resetCursorRects() } }

    private var startPoint: NSPoint?
    private var currentRect: NSRect?
    private var lockedRect: NSRect?

    func lockRegion(_ rect: NSRect) {
        lockedRect = rect
        currentRect = rect
        needsDisplay = true
    }

    func unlockRegion() {
        lockedRect = nil
        currentRect = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard lockedRect == nil else { return }
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard lockedRect == nil, let start = startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        currentRect = rect
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard lockedRect == nil else { return }
        guard let rect = currentRect, rect.width > 5, rect.height > 5 else {
            // No drag — treat as a click (for full-screen mode)
            currentRect = nil
            startPoint = nil
            needsDisplay = true
            onClicked?()
            return
        }
        onRegionSelected?(rect)
        startPoint = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isDimmed && currentRect == nil {
            NSColor.black.withAlphaComponent(0.4).setFill()
            bounds.fill()
            return
        }

        guard let rect = currentRect else { return }

        // Dim outside selection
        NSColor.black.withAlphaComponent(0.4).setFill()
        let path = NSBezierPath(rect: bounds)
        path.append(NSBezierPath(rect: rect).reversed)
        path.fill()

        // Selection border
        let borderColor: NSColor = recordingActive ? .systemRed : .white
        borderColor.setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = recordingActive ? 2.0 : 1.5
        border.stroke()

        // Size label
        let labelText = recordingActive ? "Recording…" : "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = (labelText as NSString).size(withAttributes: attrs)
        let labelRect = NSRect(
            x: rect.midX - textSize.width / 2 - 6,
            y: rect.maxY + 4,
            width: textSize.width + 12,
            height: textSize.height + 4
        )
        let bgColor: NSColor = recordingActive ? .systemRed.withAlphaComponent(0.8) : .black.withAlphaComponent(0.7)
        bgColor.setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()
        (labelText as NSString).draw(
            at: NSPoint(x: labelRect.origin.x + 6, y: labelRect.origin.y + 2),
            withAttributes: attrs
        )
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: usesCrosshair ? .crosshair : .arrow)
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            (window?.windowController ?? nil) != nil ? window?.close() : window?.close()
        } else {
            super.keyDown(with: event)
        }
    }
}
