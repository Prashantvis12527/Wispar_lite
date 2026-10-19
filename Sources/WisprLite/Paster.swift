import AppKit

enum Paster {
    /// Roles that can be focused but never accept pasted text (Finder lists, buttons, the desktop...).
    private static let nonTextRoles: Set<String> = [
        "AXScrollArea", "AXList", "AXOutline", "AXTable", "AXBrowser", "AXImage", "AXButton",
        "AXStaticText", "AXToolbar", "AXSplitGroup", "AXDesktop", "AXApplication",
    ]

    private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    /// Best guess at whether Cmd+V would land somewhere: a focused element that isn't obviously non-text,
    /// or, when the app reports no focused element, a focused window (some apps don't expose it).
    static func hasPasteTarget() -> Bool {
        guard AXIsProcessTrusted() else { return true }
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &ref) == .success,
           let el = ref {
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(el as! AXUIElement, kAXRoleAttribute as CFString, &role)
            let r = role as? String ?? ""
            // Finder turns a pasted string into a .txt clipping file, so there only a real text field counts.
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" { return textRoles.contains(r) }
            if textRoles.contains(r) { return true }
            if nonTextRoles.contains(r) { return false }
            // Unknown role (e.g. a browser's AXWebArea/AXGroup when you click outside the chat box):
            // only a target if the element actually behaves like editable text.
            let ax = el as! AXUIElement
            var names: CFArray?
            AXUIElementCopyAttributeNames(ax, &names)
            if (names as? [String])?.contains(kAXSelectedTextRangeAttribute as String) == true { return true }
            var settable: DarwinBoolean = false
            AXUIElementIsAttributeSettable(ax, kAXValueAttribute as CFString, &settable)
            return settable.boolValue
        }
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" { return false }
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        var win: CFTypeRef?
        return AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier),
                                             kAXFocusedWindowAttribute as CFString, &win) == .success
    }

    private static var lastPasteEnd: Date?
    private static var lastPasteApp: String?

    /// The character right before the caret in the focused field, or nil if the app doesn't expose it.
    private static func characterBeforeCaret() -> Character? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let el = ref else { return nil }
        let ax = el as! AXUIElement
        var rangeRef: CFTypeRef?
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              AXUIElementCopyAttributeValue(ax, kAXValueAttribute as CFString, &valueRef) == .success,
              let rv = rangeRef, CFGetTypeID(rv) == AXValueGetTypeID(),
              let value = valueRef as? String else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rv as! AXValue, .cfRange, &range) else { return nil }
        // Caret at 0 is ambiguous (truly empty field, or an app that reports no real caret), so treat it as unknown.
        if range.location <= 0 { return nil }
        let ns = value as NSString
        guard range.location <= ns.length else { return nil }
        return (ns.substring(with: NSRange(location: range.location - 1, length: 1))).first
    }

    /// True when the new text would otherwise be glued onto the previous word.
    private static func needsLeadingSpace() -> Bool {
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let c = characterBeforeCaret() {
            let need = !c.isWhitespace && !"([{\"'“‘/-".contains(c)
            Debug.note("paste app=\(app ?? "?") AX before=\(String(reflecting: c)) -> space=\(need)")
            return need
        }
        // App doesn't expose the caret: assume continuation if we pasted very recently in the same app.
        let need = lastPasteApp == app && lastPasteEnd.map { Date().timeIntervalSince($0) < 120 } == true
        Debug.note("paste app=\(app ?? "?") AX unavailable -> space=\(need)")
        return need
    }

    /// Puts text on the clipboard, sends Cmd+V, then restores the previous clipboard.
    static func paste(_ original: String) {
        var text = original
        if let first = text.first, !first.isWhitespace, needsLeadingSpace() { text = " " + text }
        lastPasteEnd = Date()
        lastPasteApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let pb = NSPasteboard.general
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
        }
        pb.clearContents()
        pb.setString(text, forType: .string)

        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true) // 'v'
        let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard !saved.isEmpty else { return }
            pb.clearContents()
            for entry in saved {
                let item = NSPasteboardItem()
                for (t, d) in entry { item.setData(d, forType: t) }
                pb.writeObjects([item])
            }
        }
    }
}
