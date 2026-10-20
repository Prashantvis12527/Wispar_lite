import AppKit
import AVFoundation
import ServiceManagement

final class App: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let hotkey = Hotkey()
    private let recorder = Recorder()
    private let overlay = Overlay()
    private let dashboard = Dashboard()
    private var lastText = ""
    private var recording = false
    private var cleanupItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var floatItem: NSMenuItem!
    private var positionMenu: NSMenu!
    private var hotkeyHeader: NSMenuItem!
    private var hotkeyMenu: NSMenu!

    private static let presetKeys: [Int64] = [61, 54, 62, 63, 96, 97]   // Right Option/Command/Control, Fn, F5, F6

    private var hotkeyCode: Int64 {
        get { UserDefaults.standard.object(forKey: "hotkeyCode") as? Int64 ?? Hotkey.defaultKeyCode }
        set { UserDefaults.standard.set(newValue, forKey: "hotkeyCode") }
    }

    private var cleanupEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "cleanup") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "cleanup") }
    }

    private var floatingEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "floatingIcon") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "floatingIcon") }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        Vocabulary.ensureFile()
        dashboard.host = self
        overlay.position = iconPosition
        overlay.idleVisible = floatingEnabled
        recorder.onLevel = { [weak self] in self?.overlay.setLevel($0) }
        setIcon("mic")
        let menu = NSMenu()
        hotkeyHeader = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        let hotkeyRoot = NSMenuItem(title: "Hotkey", action: nil, keyEquivalent: "")
        hotkeyMenu = NSMenu(title: "Hotkey")
        hotkeyRoot.submenu = hotkeyMenu
        menu.addItem(hotkeyRoot)
        hotkey.keyCode = hotkeyCode
        rebuildHotkeyMenu()
        menu.addItem(.separator())
        for (title, action, key) in [("Insights…", #selector(showInsights), "i"),
                                     ("History…", #selector(showHistory), "y"),
                                     ("Settings…", #selector(showSettings), ",")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        cleanupItem = NSMenuItem(title: "AI cleanup", action: #selector(toggleCleanup), keyEquivalent: "")
        cleanupItem.target = self
        cleanupItem.state = cleanupEnabled ? .on : .off
        menu.addItem(cleanupItem)
        floatItem = NSMenuItem(title: "Floating icon", action: #selector(toggleFloating), keyEquivalent: "")
        floatItem.target = self
        floatItem.state = floatingEnabled ? .on : .off
        menu.addItem(floatItem)
        let positionRoot = NSMenuItem(title: "Icon position", action: nil, keyEquivalent: "")
        positionMenu = NSMenu(title: "Icon position")
        for pos in Overlay.Position.allCases {
            let item = NSMenuItem(title: pos.title, action: #selector(pickPosition(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = pos.rawValue
            positionMenu.addItem(item)
        }
        positionRoot.submenu = positionMenu
        menu.addItem(positionRoot)
        refreshPositionMenu()
        loginItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)
        let copyLast = NSMenuItem(title: "Copy last dictation", action: #selector(copyLast), keyEquivalent: "")
        copyLast.target = self
        menu.addItem(copyLast)
        let key = NSMenuItem(title: "Set Groq API key…", action: #selector(setKey), keyEquivalent: "")
        key.target = self
        menu.addItem(key)
        let vocab = NSMenuItem(title: "Edit vocabulary…", action: #selector(editVocab), keyEquivalent: "")
        vocab.target = self
        menu.addItem(vocab)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        statusItem.menu = menu

        // Menu-bar agents have no main menu, so Cmd+C/V/X/A don't work in our own dialogs without this.
        let mainMenu = NSMenu()
        let editRoot = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editRoot.submenu = edit
        mainMenu.addItem(editRoot)
        NSApp.mainMenu = mainMenu

        NSApp.activate(ignoringOtherApps: true)
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)

        hotkey.onStart = { [weak self] in self?.startRecording() }
        hotkey.onStop = { [weak self] in self?.finishRecording() }
        hotkey.onCancel = { [weak self] in self?.cancelRecording() }
        if !hotkey.install() {
            notify("Grant Input Monitoring in System Settings, then relaunch")
        }
        if Keychain.load() == nil { setKey() }
    }

    /// Idle ("mic") shows the WisprLite glyph; recording and processing keep system symbols as state feedback.
    private lazy var logoGlyph: NSImage? = {
        guard let url = Bundle.main.url(forResource: "menubar", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.size = NSSize(width: 18, height: 18)
        img.isTemplate = true
        return img
    }()

    private func setIcon(_ symbol: String) {
        overlay.setMode(symbol == "mic.fill" ? .listening : symbol == "ellipsis.circle" ? .processing : .idle)
        if symbol == "mic", let glyph = logoGlyph {
            statusItem.button?.image = glyph
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
    }

    private func startRecording() {
        guard !recording else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            // First use: this shows the system prompt, which is what registers us in the Microphone list.
            NSApp.activate(ignoringOtherApps: true)
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            return
        default:
            notify("Microphone access was denied. Open System Settings > Privacy & Security > Microphone, turn WisprLite on, then relaunch.")
            return
        }
        do { try recorder.start() } catch { notify("Mic error: \(error.localizedDescription)"); return }
        recording = true
        setIcon("mic.fill")
        Sounds.play(Sounds.start)
    }

    private func cancelRecording() {
        guard recording else { return }
        recording = false
        recorder.cancel()
        setIcon("mic")
    }

    private func finishRecording() {
        guard recording else { return }
        recording = false
        setIcon("ellipsis.circle")
        Sounds.play(Sounds.stop)
        guard let wav = recorder.stop() else { setIcon("mic"); return }
        guard recorder.lastPeak > 300 else {   // silence makes Whisper hallucinate "Thank you."
            setIcon("mic")
            // Quiet room noise (an accidental press) is dropped silently; only a truly dead mic gets a warning.
            guard recorder.lastPeak < 10 else { return }
            notify("The mic captured only silence (level \(recorder.lastPeak)). Check Microphone permission and the selected input device in System Settings > Sound > Input.")
            return
        }
        let cleanup = cleanupEnabled
        let peak = recorder.lastPeak
        let seconds = Double(max(wav.count - 44, 0)) / 32_000   // 16 kHz, 16-bit mono WAV
        Debug.saveLast(wav)
        Task {
            do {
                var text = try await Groq.transcribe(wav: wav)
                let raw = text
                if Vocabulary.isPromptEcho(text) {   // Whisper echoed its vocabulary hint: nothing was really said
                    Debug.log(peak: peak, raw: raw, cleaned: "(dropped: prompt echo)")
                    await MainActor.run { self.setIcon("mic") }
                    return
                }
                if !text.isEmpty && cleanup {
                    text = (try? await Groq.cleanup(text)) ?? text   // fall back to raw on failure
                }
                let final = text
                Debug.log(peak: peak, raw: raw, cleaned: final)
                await MainActor.run {
                    self.setIcon("mic")
                    guard !final.isEmpty else { return }
                    self.lastText = final
                    History.add(text: final, seconds: seconds)
                    self.dashboard.reload()
                    if Paster.hasPasteTarget() { Paster.paste(final) } else { self.overlay.showCard(final) }
                }
            } catch {
                await MainActor.run { self.setIcon("mic"); self.notify(error.localizedDescription) }
            }
        }
    }

    private func rebuildHotkeyMenu() {
        let current = hotkeyCode
        hotkeyHeader.title = "Hold or double-tap \(Hotkey.name(for: current)) to dictate"
        hotkeyMenu.removeAllItems()
        var codes = App.presetKeys
        if !codes.contains(current) { codes.append(current) }
        for code in codes {
            let item = NSMenuItem(title: Hotkey.name(for: code), action: #selector(pickHotkey(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(code)
            item.state = code == current ? .on : .off
            hotkeyMenu.addItem(item)
        }
        hotkeyMenu.addItem(.separator())
        let other = NSMenuItem(title: "Record another key…", action: #selector(recordHotkey), keyEquivalent: "")
        other.target = self
        hotkeyMenu.addItem(other)
    }

    private func setHotkey(_ code: Int64) {
        hotkeyCode = code
        hotkey.keyCode = code
        rebuildHotkeyMenu()
        dashboard.reload()
    }

    @objc private func pickHotkey(_ sender: NSMenuItem) {
        setHotkey(Int64(sender.tag))
    }

    @objc private func recordHotkey() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Press the key to use as the hotkey"
        alert.informativeText = "Any modifier (Option, Command, Control, Shift, Fn) or a key like F5. Esc or Cancel keeps the current one. The key still reaches the focused app, so a key you don't type with works best."
        alert.addButton(withTitle: "Cancel")
        hotkey.capture = { [weak self] code in
            self?.setHotkey(code)
            NSApp.abortModal()
        }
        alert.runModal()
        hotkey.capture = nil
    }

    @objc private func showInsights() { dashboard.show(.insights) }
    @objc private func showHistory() { dashboard.show(.history) }
    @objc private func showSettings() { dashboard.show(.settings) }

    @objc private func editVocab() {
        Vocabulary.ensureFile()
        NSWorkspace.shared.open(Vocabulary.url)
    }

    @objc private func toggleFloating() {
        floatingEnabled.toggle()
        floatItem.state = floatingEnabled ? .on : .off
        overlay.idleVisible = floatingEnabled
        dashboard.reload()
    }

    private var iconPosition: Overlay.Position {
        get { Overlay.Position(rawValue: UserDefaults.standard.string(forKey: "iconPosition") ?? "") ?? .bottom }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "iconPosition") }
    }

    private func refreshPositionMenu() {
        for item in positionMenu.items { item.state = (item.representedObject as? String) == iconPosition.rawValue ? .on : .off }
    }

    @objc private func pickPosition(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let pos = Overlay.Position(rawValue: raw) else { return }
        iconPosition = pos
        overlay.position = pos
        refreshPositionMenu()
        dashboard.reload()
    }

    @objc private func copyLast() {
        guard !lastText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastText, forType: .string)
    }

    private var launchAtLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @objc private func toggleLaunchAtLogin() { setLaunchAtLogin(!launchAtLoginEnabled) }

    @objc private func toggleCleanup() {
        cleanupEnabled.toggle()
        cleanupItem.state = cleanupEnabled ? .on : .off
        dashboard.reload()
    }

    @objc private func setKey() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Groq API key"
        alert.informativeText = "Free key from console.groq.com. Stored in your Keychain."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let v = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { Keychain.save(v) }
        }
    }

    private func notify(_ msg: String) {
        let a = NSAlert()
        a.messageText = "WisprLite"
        a.informativeText = msg
        a.runModal()
    }
}

extension App: DashboardHost {
    var isCleanupOn: Bool { cleanupEnabled }
    var isFloatingOn: Bool { floatingEnabled }
    var currentPosition: Overlay.Position { iconPosition }
    var hotkeyName: String { Hotkey.name(for: hotkeyCode) }
    var isLaunchAtLoginOn: Bool { launchAtLoginEnabled }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            notify("Couldn't \(on ? "enable" : "disable") launch at login: \(error.localizedDescription)")
        }
        if on, SMAppService.mainApp.status == .requiresApproval {
            notify("Approve WisprLite in System Settings > General > Login Items to finish enabling launch at login.")
        }
        loginItem.state = launchAtLoginEnabled ? .on : .off
        dashboard.reload()
    }

    func setCleanup(_ on: Bool) {
        cleanupEnabled = on
        cleanupItem.state = on ? .on : .off
    }

    func setFloating(_ on: Bool) {
        floatingEnabled = on
        floatItem.state = on ? .on : .off
        overlay.idleVisible = on
    }

    func setPosition(_ pos: Overlay.Position) {
        iconPosition = pos
        overlay.position = pos
        refreshPositionMenu()
    }

    func changeHotkey() { recordHotkey() }
    func openKeyDialog() { setKey() }
    func openVocabulary() { editVocab() }
}

extension App: NSMenuDelegate {
    // The user can change the login item in System Settings, so re-read it each time the menu opens.
    func menuWillOpen(_ menu: NSMenu) { loginItem.state = launchAtLoginEnabled ? .on : .off }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()

/// Keeps the last recording and a text log so accuracy problems can be traced to a stage.
enum Debug {
    private static let dir: URL = {
        let d = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/WisprLite")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func saveLast(_ wav: Data) {
        try? wav.write(to: dir.appendingPathComponent("last.wav"))
    }

    static func note(_ msg: String) {
        let url = dir.appendingPathComponent("log.txt")
        let line = "  \(msg)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        }
    }

    static func log(peak: Int, raw: String, cleaned: String) {
        let line = "\(Date()) peak=\(peak)\n  RAW:     \(raw)\n  CLEANED: \(cleaned)\n"
        let url = dir.appendingPathComponent("log.txt")
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
