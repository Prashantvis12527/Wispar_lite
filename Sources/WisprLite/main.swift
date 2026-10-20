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

    /// Which provider does AI cleanup. Defaults to Groq so existing installs behave as before.
    private var aiProvider: Provider {
        get { Provider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? "") ?? .groq }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "aiProvider") }
    }

    private var lastCleanupAlert = ""

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
        let key = NSMenuItem(title: "AI provider & key…", action: #selector(showSettings), keyEquivalent: "")
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
        if Provider.allCases.allSatisfy({ Keychain.load($0) == nil }) && !UserDefaults.standard.bool(forKey: "onboarded") { runOnboarding() }
        refreshSpeechAssets()
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
        let provider = aiProvider
        var cleanup = cleanupEnabled
        if cleanup && Keychain.load(provider) == nil {
            cleanup = false
            promptForKeyForCleanup()
        }
        let peak = recorder.lastPeak
        let seconds = Double(max(wav.count - 44, 0)) / 32_000   // 16 kHz, 16-bit mono WAV
        Debug.saveLast(wav)
        Task {
            do {
                var text = try await self.transcribeOnDevice(wav)
                let raw = text
                var cleanupError: Error?
                if !text.isEmpty && cleanup {
                    do { text = try await Cleanup.run(text, provider: provider) }
                    catch {   // keep the raw transcript; report below, after it has been pasted
                        cleanupError = error
                        Debug.note("\(provider.title) cleanup failed: \(error.localizedDescription)")
                    }
                }
                let final = text
                let failure = cleanupError
                Debug.log(peak: peak, raw: raw, cleaned: final)
                await MainActor.run {
                    self.setIcon("mic")
                    guard !final.isEmpty else { return }
                    self.lastText = final
                    History.add(text: final, seconds: seconds)
                    self.dashboard.reload()
                    if Paster.hasPasteTarget() { Paster.paste(final) } else { self.overlay.showCard(final) }
                    if let e = failure { self.reportCleanupFailure(e, provider: provider) }
                }
            } catch {
                await MainActor.run {
                    self.setIcon("mic")
                    self.notify("\(error.localizedDescription)\n\nYour recording is saved at ~/Library/Logs/WisprLite/last.wav.")
                }
            }
        }
    }

    // MARK: On-device speech model

    /// "installed", "downloadable", ... as last seen; refreshed at launch and after an install.
    private var speechAssets: Local.Assets = .installed

    private func refreshSpeechAssets() {
        Task {
            let a = await Local.assets()
            await MainActor.run { self.speechAssets = a; self.dashboard.reload() }
        }
    }

    /// Transcribes on this Mac. If Apple's English model is missing, offers the one-time system install and then
    /// transcribes the same recording, so the dictation that triggered the prompt isn't lost.
    private func transcribeOnDevice(_ wav: Data) async throws -> String {
        do { return try await Local.transcribe(wav: wav) }
        catch LocalError.assetsMissing {
            guard await askToInstallSpeechModel() else { throw LocalError.assetsMissing }
            try await Local.installAssets()
            refreshSpeechAssets()
            return try await Local.transcribe(wav: wav)
        }
    }

    @MainActor private func askToInstallSpeechModel() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Install Apple's English speech model?"
        alert.informativeText = "WisprLite transcribes on this Mac with Apple's speech model. It isn't installed yet. macOS downloads it once (no audio is sent anywhere), then dictation works offline."
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Not now")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func installSpeechModel() {
        Task {
            guard await askToInstallSpeechModel() else { return }
            do { try await Local.installAssets() } catch { await MainActor.run { self.notify("Couldn't install the speech model: \(error.localizedDescription)") } }
            refreshSpeechAssets()
        }
    }

    /// Transient failures (rate limit, network, 5xx) are only logged; problems the user can fix get one alert per distinct message.
    private func reportCleanupFailure(_ error: Error, provider: Provider) {
        guard let e = error as? ProviderError, e.isConfigProblem else { return }
        let msg = e.localizedDescription
        guard msg != lastCleanupAlert else { return }
        lastCleanupAlert = msg
        DispatchQueue.main.async {
            self.notify("AI cleanup with \(provider.title) failed: \(msg).\n\nYour dictation was pasted without cleanup. Check the key or provider in Settings.")
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
        setCleanup(!cleanupEnabled)
        cleanupItem.state = cleanupEnabled ? .on : .off
        dashboard.reload()
    }

    // MARK: AI provider and key (optional)

    /// Dialog with an optional provider picker and a secure key field. Returns nil if cancelled.
    private func askForKey(title: String, info: String, primary: String, cancel: String,
                           provider: Provider, chooseProvider: Bool) -> (Provider, String)? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: primary)
        alert.addButton(withTitle: cancel)
        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        for p in Provider.allCases { picker.addItem(withTitle: p.title) }
        picker.selectItem(at: Provider.allCases.firstIndex(of: provider) ?? 0)
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        let hint = NSTextField(wrappingLabelWithString: "")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        let sync = { [unowned picker] in
            let p = Provider.allCases[picker.indexOfSelectedItem]
            hint.stringValue = p.consoleHint + " Stored in your Keychain. Only transcribed text is sent, for AI cleanup."
        }
        sync()
        let handler = PickerHandler(sync)   // strong reference: NSControl targets are weak
        picker.target = handler
        picker.action = #selector(PickerHandler.changed)
        let views: [NSView] = chooseProvider ? [picker, field, hint] : [field, hint]
        alert.informativeText = info
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 320, height: chooseProvider ? 110 : 80)
        for v in views { v.widthAnchor.constraint(equalToConstant: 320).isActive = true }
        alert.accessoryView = stack
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return (Provider.allCases[picker.indexOfSelectedItem], field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// First launch: choose a provider and enter a key, or skip and dictate with on-device recognition only.
    private func runOnboarding() {
        let result = askForKey(
            title: "Welcome to WisprLite",
            info: "Dictation always runs on this Mac with Apple's speech recognition; your audio never leaves it. Add an API key to also clean up the text (punctuation, filler words), or skip and use the raw transcript. You can add a key later in Settings.",
            primary: "Save key", cancel: "Skip, no AI cleanup", provider: aiProvider, chooseProvider: true)
        UserDefaults.standard.set(true, forKey: "onboarded")
        if let (p, key) = result, !key.isEmpty { storeKey(key, for: p) }
    }

    /// Add or update the key for a provider. Saving is followed by a live test so a typo is caught at once.
    @objc private func setKey() { editKey(for: aiProvider, chooseProvider: Keychain.loadStored(aiProvider) == nil) }

    private func editKey(for current: Provider, chooseProvider: Bool) {
        let had = Keychain.loadStored(current) != nil
        guard let (p, key) = askForKey(
            title: had ? "Update \(current.title) API key" : "Add an API key",
            info: had ? "Leave blank to keep the current key." : "",
            primary: "Save", cancel: "Cancel", provider: current, chooseProvider: chooseProvider),
              !key.isEmpty else { return }
        storeKey(key, for: p)
    }

    private func storeKey(_ key: String, for p: Provider) {
        guard Keychain.save(p, key) else {
            notify("Couldn't save the key to your Keychain.")
            return
        }
        aiProvider = p
        UserDefaults.standard.set(true, forKey: "onboarded")
        dashboard.reload()
        Task {
            let problem = await Cleanup.test(p, key: key)
            await MainActor.run {
                if let problem { self.notify("The \(p.title) key was saved, but the test failed.\n\n\(problem)") }
            }
        }
    }

    /// Tests the selected provider's key (or its environment variable) with a real cleanup call.
    func testKey() {
        let p = aiProvider
        guard let key = Keychain.load(p) else { promptToAddKey("There's no \(p.title) API key to test yet."); return }
        Task {
            let problem = await Cleanup.test(p, key: key)
            await MainActor.run { self.notify(problem ?? "The \(p.title) API key works.") }
        }
    }

    func removeKey() {
        let p = aiProvider
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Remove the \(p.title) API key?"
        alert.informativeText = "It's deleted from your Keychain. AI cleanup will be unavailable until you add a key again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Keychain.delete(p)
        dashboard.reload()
    }

    private func promptToAddKey(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "API key needed"
        alert.informativeText = message
        alert.addButton(withTitle: "Add key…")
        alert.addButton(withTitle: "Not now")
        if alert.runModal() == .alertFirstButtonReturn { editKey(for: aiProvider, chooseProvider: true) }
    }

    /// AI cleanup was requested but the selected provider has no key: say so, rather than silently pasting uncleaned text.
    /// This dictation is pasted without cleanup; the alert is deferred so it doesn't delay the transcription.
    private func promptForKeyForCleanup() {
        let p = aiProvider
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "AI cleanup needs an API key"
            alert.informativeText = "No \(p.title) key is set, so this dictation was pasted without cleanup. Add a key (Grok, Claude, Gemini or Groq) to turn punctuation and filler-word cleanup on, or turn cleanup off to stop seeing this."
            alert.addButton(withTitle: "Add key…")
            alert.addButton(withTitle: "Turn off AI cleanup")
            alert.addButton(withTitle: "Dismiss")
            switch alert.runModal() {
            case .alertFirstButtonReturn: self.editKey(for: p, chooseProvider: true)
            case .alertSecondButtonReturn:
                self.cleanupEnabled = false
                self.cleanupItem.state = .off
                self.dashboard.reload()
            default: break
            }
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
    var hasKey: Bool { Keychain.load(aiProvider) != nil }
    var currentProvider: Provider { aiProvider }
    var transcriptionDetail: String {
        switch speechAssets {
        case .installed: return "\(Local.engineName). Audio never leaves your Mac."
        case .downloadable: return "Apple's English speech model isn't installed yet"
        case .downloading: return "Apple's English speech model is downloading"
        case .unsupported: return "On-device English speech recognition isn't available on this Mac"
        }
    }
    var needsSpeechModel: Bool { speechAssets == .downloadable }

    func setProvider(_ p: Provider) {
        aiProvider = p
        lastCleanupAlert = ""
        dashboard.reload()
    }

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
        if on && Keychain.load(aiProvider) == nil {
            cleanupEnabled = false
            cleanupItem.state = .off
            promptToAddKey("AI cleanup uses a hosted model (Grok, Claude, Gemini or Groq), so it needs an API key.")
            dashboard.reload()
            return
        }
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
    func changeKey() { editKey(for: aiProvider, chooseProvider: false) }
    func openVocabulary() { editVocab() }
}

extension App: NSMenuDelegate {
    // The user can change the login item in System Settings, so re-read it each time the menu opens.
    func menuWillOpen(_ menu: NSMenu) { loginItem.state = launchAtLoginEnabled ? .on : .off }
}

/// Target for the provider popup inside the key dialog.
final class PickerHandler: NSObject {
    private let onChange: () -> Void
    init(_ onChange: @escaping () -> Void) { self.onChange = onChange }
    @objc func changed() { onChange() }
}

// `WisprLite --selftest <groq|xai|anthropic|gemini>`: exercises one provider from the terminal, then exits.
if let i = CommandLine.arguments.firstIndex(of: "--selftest") {
    SelfTest.run(CommandLine.arguments.dropFirst(i + 1).first ?? "")
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--bench") {
    SelfTest.bench(Array(CommandLine.arguments.dropFirst(i + 1)))
    exit(0)
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
