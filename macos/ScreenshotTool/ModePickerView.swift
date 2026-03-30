import Cocoa
import SwiftUI

enum CaptureMode: Int, CaseIterable {
    case screenshot = 0
    case gif = 1
    case diff = 2
    case companion = 3

    var label: String {
        switch self {
        case .screenshot: return "Screenshot"
        case .gif: return "Record GIF"
        case .diff: return "Diff"
        case .companion: return "iPhone"
        }
    }

    var icon: String {
        switch self {
        case .screenshot: return "camera.viewfinder"
        case .gif: return "record.circle"
        case .diff: return "square.split.2x1"
        case .companion: return "iphone"
        }
    }

    var shortcutHint: String {
        switch self {
        case .screenshot: return "S"
        case .gif: return "G"
        case .diff: return "D"
        case .companion: return "I"
        }
    }

    var shortcutDisplay: String {
        let store = ShortcutStore.shared
        switch self {
        case .screenshot: return store.screenshot.displayString
        case .gif: return store.gifRecording.displayString
        case .diff: return store.diff.displayString
        case .companion: return "I"
        }
    }

    /// Core modes (always shown)
    static let coreModes: [CaptureMode] = [.screenshot, .gif, .diff]

    /// Whether companion devices are available
    static var hasCompanionDevices: Bool {
        !PairedDeviceStore.shared.devices.isEmpty
    }
}

class ModePickerPanel: NSPanel {
    var onModeSelected: ((CaptureMode) -> Void)?
    /// Called when a specific companion device is selected, passes device_id
    var onCompanionDeviceSelected: ((String) -> Void)?
    var onCancel: (() -> Void)?
    private var hostingView: NSHostingView<ModePickerContent>!
    private var selectedMode: CaptureMode = .screenshot
    private var selectedDeviceId: String?

    init(initialMode: CaptureMode = .screenshot) {
        self.selectedMode = initialMode
        let devices = PairedDeviceStore.shared.devices
        let deviceCount = devices.count
        let baseWidth: CGFloat = 360
        let deviceWidth: CGFloat = deviceCount > 0 ? CGFloat(deviceCount) * 90.0 : 0
        let panelWidth = baseWidth + deviceWidth
        let panelHeight: CGFloat = 82

        guard let screen = NSScreen.main else {
            super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            return
        }

        let panelFrame = NSRect(
            x: screen.frame.midX - panelWidth / 2,
            y: screen.frame.minY + 120,
            width: panelWidth,
            height: panelHeight
        )

        super.init(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver + 1
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true

        updateContent()
    }

    private func updateContent() {
        let devices = PairedDeviceStore.shared.devices
        let connectedIds = Set(RustBridge.shared.listCompanions().map { $0.device_id })

        let content = ModePickerContent(
            selectedMode: selectedMode,
            selectedDeviceId: selectedDeviceId,
            devices: devices,
            connectedDeviceIds: connectedIds,
            onSelectMode: { [weak self] mode in
                self?.selectedMode = mode
                self?.selectedDeviceId = nil
                self?.updateContent()
                self?.onModeSelected?(mode)
            },
            onSelectDevice: { [weak self] deviceId in
                self?.selectedMode = .companion
                self?.selectedDeviceId = deviceId
                self?.updateContent()
                self?.onCompanionDeviceSelected?(deviceId)
            },
            onCancel: { [weak self] in
                self?.onCancel?()
            }
        )
        if hostingView == nil {
            hostingView = NSHostingView(rootView: content)
            self.contentView = hostingView
        } else {
            hostingView.rootView = content
        }
    }

    func selectMode(_ mode: CaptureMode) {
        selectedMode = mode
        selectedDeviceId = nil
        updateContent()
        onModeSelected?(mode)
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // ESC
            onCancel?()
            return true
        case 1: // S
            selectMode(.screenshot)
            return true
        case 5: // G
            selectMode(.gif)
            return true
        case 2: // D
            selectMode(.diff)
            return true
        case 18, 19, 20, 21, 23, 22, 26, 28, 25: // 1-9 keys
            let numberMap: [UInt16: Int] = [18:1, 19:2, 20:3, 21:4, 23:5, 22:6, 26:7, 28:8, 25:9]
            if let number = numberMap[event.keyCode] {
                let devices = PairedDeviceStore.shared.devices
                let index = number - 1
                if index < devices.count {
                    selectedMode = .companion
                    selectedDeviceId = devices[index].deviceId
                    updateContent()
                    onCompanionDeviceSelected?(devices[index].deviceId)
                }
            }
            return true
        default:
            return false
        }
    }
}

struct ModePickerContent: View {
    let selectedMode: CaptureMode
    let selectedDeviceId: String?
    let devices: [PairedDevice]
    let connectedDeviceIds: Set<String>
    let onSelectMode: (CaptureMode) -> Void
    let onSelectDevice: (String) -> Void
    let onCancel: () -> Void

    @Namespace private var modeIndicator

    var body: some View {
        HStack(spacing: 0) {
            // Core mode buttons
            ForEach(CaptureMode.coreModes, id: \.rawValue) { mode in
                modeButton(mode)
                Divider()
                    .frame(height: 28)
                    .opacity(0.15)
            }

            // Device buttons
            ForEach(Array(devices.enumerated()), id: \.element.deviceId) { index, device in
                deviceButton(device, number: index + 1)
                if device.deviceId != devices.last?.deviceId {
                    Divider()
                        .frame(height: 28)
                        .opacity(0.15)
                }
            }

            if !devices.isEmpty {
                Divider()
                    .frame(height: 28)
                    .opacity(0.15)
                    .padding(.horizontal, 4)
            }

            // Close button
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(PV.Colors.textSecondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(ModePickerCloseButtonStyle())
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .pvGlass()
    }

    private let modeButtonSize = CGSize(width: 90, height: 58)

    private func modeButton(_ mode: CaptureMode) -> some View {
        let isSelected = mode == selectedMode && selectedDeviceId == nil
        let shortcut = mode.shortcutDisplay
        return Button(action: { onSelectMode(mode) }) {
            VStack(spacing: 3) {
                Image(systemName: mode.icon)
                    .font(.system(size: 16))
                Text(mode.label)
                    .font(.system(size: 10, weight: .medium))
                Text(shortcut)
                    .font(.system(size: 9))
                    .foregroundColor(PV.Colors.textSecondary)
            }
            .foregroundColor(isSelected ? PV.Colors.textPrimary : PV.Colors.textSecondary)
            .frame(width: modeButtonSize.width, height: modeButtonSize.height)
            .background(
                RoundedRectangle(cornerRadius: PV.Radius.medium)
                    .fill(PV.Gradients.accentSolid.opacity(isSelected ? 0.15 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PV.Radius.medium)
                    .strokeBorder(isSelected ? AnyShapeStyle(PV.Gradients.accent) : AnyShapeStyle(Color.clear), lineWidth: 1.5)
            )
            .animation(PV.Anim.snappy, value: isSelected)
        }
        .buttonStyle(.plain)
    }

    private func deviceButton(_ device: PairedDevice, number: Int) -> some View {
        let isSelected = selectedDeviceId == device.deviceId
        let isConnected = connectedDeviceIds.contains(device.deviceId)
        return Button(action: { onSelectDevice(device.deviceId) }) {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "iphone")
                        .font(.system(size: 16))
                    Circle()
                        .fill(isConnected ? Color(hex: 0x10B981) : PV.Colors.border)
                        .frame(width: 6, height: 6)
                        .offset(x: 4, y: -2)
                }
                Text(device.deviceName)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                Text("\(number)")
                    .font(.system(size: 9))
                    .foregroundColor(PV.Colors.textSecondary)
            }
            .foregroundColor(isSelected ? PV.Colors.textPrimary : PV.Colors.textSecondary)
            .frame(width: modeButtonSize.width, height: modeButtonSize.height)
            .background(
                RoundedRectangle(cornerRadius: PV.Radius.medium)
                    .fill(PV.Gradients.accentSolid.opacity(isSelected ? 0.15 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PV.Radius.medium)
                    .strokeBorder(isSelected ? AnyShapeStyle(PV.Gradients.accent) : AnyShapeStyle(Color.clear), lineWidth: 1.5)
            )
            .animation(PV.Anim.snappy, value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Close button with hover

struct ModePickerCloseButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isHovered ? 1.1 : 1.0)
            .animation(PV.Anim.hover, value: isHovered)
            .onHover { isHovered = $0 }
    }
}
