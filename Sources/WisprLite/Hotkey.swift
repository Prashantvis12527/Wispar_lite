import AppKit

/// Watches one user-chosen key globally (default Right Option, keycode 61).
/// Works for modifier keys (via flagsChanged) and regular keys such as F5 (via keyDown/keyUp).
/// Hold >= 0.35 s: push-to-talk. Double-tap: lock recording on; one more tap stops.
final class Hotkey {
    static let defaultKeyCode: Int64 = 61

    /// Modifier keycodes and the flag that is set while each is held. Caps Lock (57) is excluded: it toggles.
    private static let modifierFlags: [Int64: CGEventFlags] = [
        54: .maskCommand, 55: .maskCommand, 56: .maskShift, 60: .maskShift,
        58: .maskAlternate, 61: .maskAlternate, 59: .maskControl, 62: .maskControl,
        63: .maskSecondaryFn,
    ]

    private static let names: [Int64: String] = [
        54: "Right Command", 55: "Left Command", 56: "Left Shift", 60: "Right Shift",
        58: "Left Option", 61: "Right Option", 59: "Left Control", 62: "Right Control", 63: "Fn",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 57: "Caps Lock",
    ]

    static func name(for code: Int64) -> String { names[code] ?? "Key \(code)" }

    var onStart: (() -> Void)?
    var onStop: (() -> Void)?     // finish and process
    var onCancel: (() -> Void)?   // discard

    /// Set while waiting for the user to press a new hotkey; receives that key's code.
    var capture: ((Int64) -> Void)?

    var keyCode: Int64 = Hotkey.defaultKeyCode {
        didSet { isDown = false; locked = false; chorded = false }
    }
    private let holdThreshold: TimeInterval = 0.35
    private let doubleTapWindow: TimeInterval = 0.5
    private var tap: CFMachPort?
    private var isDown = false
    private var pressTime = Date.distantPast
    private var lastTap = Date.distantPast
    private var locked = false
    /// Set when a modifier hotkey is used in a shortcut (e.g. Right Option + e) during a press.
    private var chorded = false

    func install() -> Bool {
        let mask = CGEventMask((1 << CGEventType.flagsChanged.rawValue)
                             | (1 << CGEventType.keyDown.rawValue)
                             | (1 << CGEventType.keyUp.rawValue))
        let cb: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<Hotkey>.fromOpaque(refcon!).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
            } else {
                let code = event.getIntegerValueField(.keyboardEventKeycode)
                let flag = Hotkey.modifierFlags[code]
                if let capture = me.capture {
                    // Esc is left to cancel the capture dialog; Caps Lock can't be held.
                    let pressed = type == .keyDown || (type == .flagsChanged && flag.map { event.flags.contains($0) } == true)
                    if pressed, code != 53, code != 57 {
                        me.capture = nil
                        DispatchQueue.main.async { capture(code) }
                    }
                } else if code == me.keyCode {
                    if type == .flagsChanged, let flag = flag {
                        let down = event.flags.contains(flag)
                        DispatchQueue.main.async { me.handle(down: down) }
                    } else if type == .keyDown, flag == nil,
                              event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                        DispatchQueue.main.async { me.handle(down: true) }
                    } else if type == .keyUp, flag == nil {
                        DispatchQueue.main.async { me.handle(down: false) }
                    }
                } else if Hotkey.modifierFlags[me.keyCode] != nil,
                          type == .keyDown || (type == .flagsChanged && flag.map { event.flags.contains($0) } == true) {
                    // Another key or modifier pressed while a modifier hotkey is held: it's a shortcut, not dictation.
                    DispatchQueue.main.async { me.chord() }
                }
            }
            return Unmanaged.passUnretained(event)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                        options: .listenOnly, eventsOfInterest: mask,
                                        callback: cb,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = t
        let src = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    private func handle(down: Bool) {
        if down {
            guard !isDown else { return }
            isDown = true
            if locked { locked = false; onStop?(); return }
            pressTime = Date()
            chorded = false
            onStart?()
        } else {
            guard isDown else { return }
            isDown = false
            if chorded { chorded = false; return }   // shortcut release: not a stop, tap or double-tap
            if locked { return }
            let held = Date().timeIntervalSince(pressTime)
            if held >= holdThreshold {
                onStop?()
            } else if Date().timeIntervalSince(lastTap) <= doubleTapWindow {
                locked = true            // double-tap: keep recording
                lastTap = .distantPast
            } else {
                lastTap = Date()
                onCancel?()              // single short tap: ignore
            }
        }
    }

    /// Discards the recording started by this press, since the hotkey is being used as a normal modifier.
    private func chord() {
        guard isDown, !locked, !chorded else { return }
        chorded = true
        lastTap = .distantPast
        onCancel?()
    }
}
