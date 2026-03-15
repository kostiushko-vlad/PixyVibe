import Cocoa
import Carbon

class HotkeyManager {
    var onHotkeyPressed: (() -> Void)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func register() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        // Store self reference for the callback
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
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags

            // Shift+Cmd+6: keyCode 22 = '6'
            let isShift = flags.contains(.maskShift)
            let isCommand = flags.contains(.maskCommand)
            let isNoOther = !flags.contains(.maskControl) && !flags.contains(.maskAlternate)

            if keyCode == 22 && isShift && isCommand && isNoOther {
                DispatchQueue.main.async { [weak self] in
                    self?.onHotkeyPressed?()
                }
                return nil // Consume the event
            }
        }

        return Unmanaged.passRetained(event)
    }
}
