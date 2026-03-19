import Cocoa
import Carbon

/// Represents a keyboard shortcut (modifier flags + key code).
struct KeyboardShortcut: Codable, Equatable {
    var keyCode: Int
    var shift: Bool
    var command: Bool
    var control: Bool
    var option: Bool

    /// Human-readable display string.
    var displayString: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        return Int(keyCode) == self.keyCode
            && flags.contains(.maskShift) == shift
            && flags.contains(.maskCommand) == command
            && flags.contains(.maskControl) == control
            && flags.contains(.maskAlternate) == option
    }

    /// Default shortcuts
    static let defaultScreenshot = KeyboardShortcut(keyCode: 18, shift: true, command: true, control: false, option: false) // ⇧⌘1
    static let defaultGifRecording = KeyboardShortcut(keyCode: 19, shift: true, command: true, control: false, option: false) // ⇧⌘2
    static let defaultDiff = KeyboardShortcut(keyCode: 22, shift: true, command: true, control: false, option: false) // ⇧⌘6
}

/// Maps key codes to readable key names.
private func keyCodeToString(_ keyCode: Int) -> String {
    let map: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        49: "Space", 50: "`",
        36: "↩", 48: "⇥", 51: "⌫", 53: "⎋",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15",
        118: "F4", 120: "F2", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
    return map[keyCode] ?? "Key\(keyCode)"
}

// MARK: - Shortcut Store

class ShortcutStore {
    static let shared = ShortcutStore()

    private let defaults = UserDefaults.standard

    var screenshot: KeyboardShortcut {
        get { load("shortcut_screenshot") ?? .defaultScreenshot }
        set { save(newValue, key: "shortcut_screenshot") }
    }

    var gifRecording: KeyboardShortcut {
        get { load("shortcut_gif") ?? .defaultGifRecording }
        set { save(newValue, key: "shortcut_gif") }
    }

    var diff: KeyboardShortcut {
        get { load("shortcut_diff") ?? .defaultDiff }
        set { save(newValue, key: "shortcut_diff") }
    }

    private func load(_ key: String) -> KeyboardShortcut? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyboardShortcut.self, from: data)
    }

    private func save(_ shortcut: KeyboardShortcut, key: String) {
        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: key)
        }
        NotificationCenter.default.post(name: .shortcutsChanged, object: nil)
    }
}

extension Notification.Name {
    static let shortcutsChanged = Notification.Name("shortcutsChanged")
    static let shortcutRecordingStarted = Notification.Name("shortcutRecordingStarted")
    static let shortcutRecordingStopped = Notification.Name("shortcutRecordingStopped")
}

// MARK: - Hotkey Manager

enum HotkeyAction {
    case screenshot
    case gifRecording
    case diff
}

class HotkeyManager {
    var onAction: ((HotkeyAction) -> Void)?
    /// When true, all hotkeys are ignored (used during shortcut recording in Settings)
    var isPaused = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func register() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let userInfo = Unmanaged.passRetained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { (proxy, type_, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type_, event: event)
            },
            userInfo: userInfo
        ) else {
            print("Failed to create event tap. Check Accessibility permissions.")
            Unmanaged<HotkeyManager>.fromOpaque(userInfo).release()
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func unregister() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .keyDown && !isPaused {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            let store = ShortcutStore.shared

            if store.screenshot.matches(keyCode: keyCode, flags: flags) {
                DispatchQueue.main.async { [weak self] in self?.onAction?(.screenshot) }
                return nil
            }
            if store.gifRecording.matches(keyCode: keyCode, flags: flags) {
                DispatchQueue.main.async { [weak self] in self?.onAction?(.gifRecording) }
                return nil
            }
            if store.diff.matches(keyCode: keyCode, flags: flags) {
                DispatchQueue.main.async { [weak self] in self?.onAction?(.diff) }
                return nil
            }
        }
        return Unmanaged.passRetained(event)
    }
}
