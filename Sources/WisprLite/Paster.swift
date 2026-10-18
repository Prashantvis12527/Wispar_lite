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
            return !nonTextRoles.contains(r)
        }
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" { return false }
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        var win: CFTypeRef?
        return AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier),
                                             kAXFocusedWindowAttribute as CFString, &win) == .success
    }

    /// Puts text on the clipboard, sends Cmd+V, then restores the previous clipboard.
    static func paste(_ text: String) {
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
