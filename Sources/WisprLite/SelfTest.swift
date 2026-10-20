import Foundation
import Darwin

/// Terminal check of one provider's integration, using its key from the environment or Keychain.
/// Prints results only (never the key). A fake key is a useful probe: it proves the URL, headers and
/// error shape are right even without a real account.
enum SelfTest {
    static func run(_ name: String) {
        if name == "parse" { parseCheck(); return }
        guard let p = Provider(rawValue: name) else {
            print("usage: WisprLite --selftest groq|xai|anthropic|gemini|parse"); return
        }
        guard let key = Keychain.load(p) else {
            print("\(p.title): no key in \(p.envVar) or Keychain"); return
        }
        let done = DispatchSemaphore(value: 0)
        Task {
            print("\(p.title) model: \(p.cleanupModel)")
            print("verify (list models): \(await Cleanup.verify(p, key: key) ?? "OK")")
            let sample = "um so i think we should uh meet at three pm tomorrow no wait thursday"
            let t0 = Date()
            do {
                let out = try await Cleanup.run(sample, provider: p, key: key)
                print("cleanup OK in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
                print("  in : \(sample)\n  out: \(out)")
            } catch {
                print("cleanup FAILED: \(error.localizedDescription)")
            }
            done.signal()
        }
        done.wait()
    }
}

extension SelfTest {
    /// Offline: feeds each provider's documented response shape (plus the odd cases) to the parser.
    static func parseCheck() {
        let cases: [(Provider, String, String?)] = [
            (.groq, #"{"choices":[{"message":{"role":"assistant","content":"Hello."}}]}"#, "Hello."),
            (.xai, #"{"object":"response","status":"completed","output":[{"type":"reasoning","summary":[]},{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Hello."}]}]}"#, "Hello."),
            (.anthropic, #"{"type":"message","content":[{"type":"thinking","thinking":"hmm"},{"type":"text","text":"Hello."}],"stop_reason":"end_turn"}"#, "Hello."),
            (.gemini, #"{"candidates":[{"content":{"parts":[{"thought":true,"text":"hmm"},{"text":"Hello."}],"role":"model"}}]}"#, "Hello."),
            (.gemini, #"{"promptFeedback":{"blockReason":"SAFETY"}}"#, nil),
            (.anthropic, #"{"type":"message","content":[]}"#, nil),
        ]
        var bad = 0
        for (p, json, want) in cases {
            let got = Cleanup.extract(p, Data(json.utf8))
            let ok = got == want
            if !ok { bad += 1 }
            print("\(ok ? "ok  " : "FAIL") \(p.rawValue): \(got ?? "nil")")
        }
        print(bad == 0 ? "all parse cases passed" : "\(bad) parse case(s) failed")
    }
}

extension SelfTest {
    /// `--bench <engine> <file.wav>...`: one engine per process so peak memory is attributable.
    /// Prints a TSV line per file (ms, text) then the process's own footprint. Reads WAVs only, never records.
    static func bench(_ args: [String]) {
        if args.first == "install" {   // one-time install of Apple's English model via the system asset manager
            let done = DispatchSemaphore(value: 0)
            Task {
                print("before: \(await Local.assets())")
                do { try await Local.installAssets() } catch { print("install error: \(error)") }
                print("after: \(await Local.assets())")
                done.signal()
            }
            done.wait(); return
        }
        guard let name = args.first, let engine = Local.Engine(rawValue: name) else {
            print("usage: WisprLite --bench auto|speechTranscriber|dictationTranscriber|sfSpeech file.wav..."); return
        }
        let done = DispatchSemaphore(value: 0)
        Task {
            print("engine=\(name) start_footprint_mb=\(footprintMB())")
            print("assets=\(await Local.assets())")
            for path in args.dropFirst() {
                guard let wav = FileManager.default.contents(atPath: path) else { print("missing\t\(path)"); continue }
                let t0 = Date()
                do {
                    let text = try await Local.transcribe(wav: wav, engine: engine)
                    print("ok\t\(Int(Date().timeIntervalSince(t0) * 1000))\t\((path as NSString).lastPathComponent)\t\(text)")
                } catch {
                    print("err\t\(Int(Date().timeIntervalSince(t0) * 1000))\t\((path as NSString).lastPathComponent)\t\(error.localizedDescription)")
                }
            }
            print("end_footprint_mb=\(footprintMB()) peak_footprint_mb=\(peakFootprintMB())")
            done.signal()
        }
        done.wait()
    }

    /// Highest physical footprint this process has reached, in MB.
    static func peakFootprintMB() -> Int {
        var ru = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &ru) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
        }
        return rc == 0 ? Int(ru.ri_lifetime_max_phys_footprint / 1_048_576) : -1
    }

    /// Physical footprint of this process (what Activity Monitor's Memory column and `footprint` report), in MB.
    static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }
}
