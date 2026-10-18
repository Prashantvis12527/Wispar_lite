import AppKit
import AVFoundation

final class App: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let hotkey = Hotkey()
    private let recorder = Recorder()
    private var recording = false
    private var cleanupItem: NSMenuItem!

    private var cleanupEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "cleanup") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "cleanup") }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        Vocabulary.ensureFile()
        setIcon("mic")
        let menu = NSMenu()
        menu.addItem(withTitle: "Hold or double-tap Right Option to dictate", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        cleanupItem = NSMenuItem(title: "AI cleanup", action: #selector(toggleCleanup), keyEquivalent: "")
        cleanupItem.target = self
        cleanupItem.state = cleanupEnabled ? .on : .off
        menu.addItem(cleanupItem)
        let key = NSMenuItem(title: "Set Groq API key…", action: #selector(setKey), keyEquivalent: "")
        key.target = self
        menu.addItem(key)
        let vocab = NSMenuItem(title: "Edit vocabulary…", action: #selector(editVocab), keyEquivalent: "")
        vocab.target = self
        menu.addItem(vocab)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

    private func setIcon(_ symbol: String) {
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
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
        NSSound(named: "Tink")?.play()
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
        NSSound(named: "Pop")?.play()
        guard let wav = recorder.stop() else { setIcon("mic"); return }
        guard recorder.lastPeak > 300 else {   // silence makes Whisper hallucinate "Thank you."
            setIcon("mic")
            notify("The mic captured only silence (level \(recorder.lastPeak)). Check Microphone permission and the selected input device in System Settings > Sound > Input.")
            return
        }
        let cleanup = cleanupEnabled
        let peak = recorder.lastPeak
        Debug.saveLast(wav)
        Task {
            do {
                var text = try await Groq.transcribe(wav: wav)
                let raw = text
                if !text.isEmpty && cleanup {
                    text = (try? await Groq.cleanup(text)) ?? text   // fall back to raw on failure
                }
                let final = text
                Debug.log(peak: peak, raw: raw, cleaned: final)
                await MainActor.run {
                    self.setIcon("mic")
                    if !final.isEmpty { Paster.paste(final) }
                }
            } catch {
                await MainActor.run { self.setIcon("mic"); self.notify(error.localizedDescription) }
            }
        }
    }

    @objc private func editVocab() {
        Vocabulary.ensureFile()
        NSWorkspace.shared.open(Vocabulary.url)
    }

    @objc private func toggleCleanup() {
        cleanupEnabled.toggle()
        cleanupItem.state = cleanupEnabled ? .on : .off
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
