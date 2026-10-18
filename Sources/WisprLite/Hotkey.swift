import AppKit

/// Watches the Right Option key (keycode 61) globally.
/// Hold >= 0.35 s: push-to-talk. Double-tap: lock recording on; one more tap stops.
final class Hotkey {
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?     // finish and process
    var onCancel: (() -> Void)?   // discard

    private let keyCode: Int64 = 61
    private let holdThreshold: TimeInterval = 0.35
    private let doubleTapWindow: TimeInterval = 0.5
    private var tap: CFMachPort?
    private var isDown = false
    private var pressTime = Date.distantPast
    private var lastTap = Date.distantPast
    private var locked = false

    func install() -> Bool {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let cb: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<Hotkey>.fromOpaque(refcon!).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
            } else if type == .flagsChanged,
                      event.getIntegerValueField(.keyboardEventKeycode) == me.keyCode {
                let down = event.flags.contains(.maskAlternate)
                DispatchQueue.main.async { me.handle(down: down) }
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
            onStart?()
        } else {
            guard isDown else { return }
            isDown = false
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
}
