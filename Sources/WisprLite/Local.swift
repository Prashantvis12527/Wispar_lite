import AVFoundation
import Speech

enum LocalError: LocalizedError {
    case denied
    case unavailable
    case assetsMissing
    var errorDescription: String? {
        switch self {
        case .denied: return "Speech Recognition access was denied. Open System Settings > Privacy & Security > Speech Recognition and turn WisprLite on."
        case .unavailable: return "On-device English speech recognition isn't available on this Mac."
        case .assetsMissing: return "Apple's on-device English speech model isn't installed. Open Settings > Transcription and choose Install."
        }
    }
}

/// On-device transcription with Apple's Speech framework. Audio never leaves the Mac: the macOS 26+ path
/// uses SpeechAnalyzer/SpeechTranscriber (models are system assets, held by Apple's speech service, not this
/// process) and the macOS 14-25 path forces `requiresOnDeviceRecognition`.
enum Local {
    enum Engine: String { case auto, speechTranscriber, dictationTranscriber, sfSpeech }

    static let locale = Locale(identifier: "en-US")

    static var engineName: String {
        if #available(macOS 26.0, *) { return "Apple SpeechAnalyzer (on-device)" }
        return "Apple Speech Recognition (on-device)"
    }

    static func transcribe(wav: Data, engine: Engine = .auto) async throws -> String {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("wisprlite-\(UUID().uuidString).wav")
        try wav.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        if #available(macOS 26.0, *), engine != .sfSpeech {
            return try await analyzerTranscribe(file: file, dictation: engine == .dictationTranscriber)
        }
        return try await legacyTranscribe(file: file)
    }

    // MARK: Asset status (macOS 26+)

    enum Assets { case installed, downloadable, downloading, unsupported }

    /// Whether the English model needed by SpeechTranscriber is on this Mac. Always `.installed` before macOS 26,
    /// where on-device support is a property of the recognizer instead.
    static func assets() async -> Assets {
        if #available(macOS 26.0, *) {
            guard SpeechTranscriber.isAvailable, let loc = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { return .unsupported }
            switch await AssetInventory.status(forModules: [SpeechTranscriber(locale: loc, preset: .transcription)]) {
            case .installed: return .installed
            case .downloading: return .downloading
            case .supported: return .downloadable
            case .unsupported: return .unsupported
            @unknown default: return .unsupported
            }
        }
        return SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition == true ? .installed : .unsupported
    }

    /// One-time install of Apple's English model through the system's asset manager (no audio is involved).
    static func installAssets() async throws {
        guard #available(macOS 26.0, *) else { return }
        let t = SpeechTranscriber(locale: locale, preset: .transcription)
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) { try await req.downloadAndInstall() }
    }

    // MARK: macOS 26+: SpeechAnalyzer

    @available(macOS 26.0, *)
    private static func analyzerTranscribe(file: URL, dictation: Bool) async throws -> String {
        guard let loc = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { throw LocalError.unavailable }
        let module: any SpeechModule
        let results: Task<String, Error>
        if dictation {
            let t = DictationTranscriber(locale: loc, preset: .shortDictation)
            module = t
            results = Task { var s = ""; for try await r in t.results { s += String(r.text.characters) }; return s }
        } else {
            let t = SpeechTranscriber(locale: loc, preset: .transcription)
            module = t
            results = Task { var s = ""; for try await r in t.results { s += String(r.text.characters) }; return s }
        }
        guard await AssetInventory.status(forModules: [module]) == .installed else { results.cancel(); throw LocalError.assetsMissing }

        // whileInUse: Apple's speech service drops the model as soon as this analyzer finishes.
        let analyzer = SpeechAnalyzer(modules: [module], options: .init(priority: .userInitiated, modelRetention: .whileInUse))
        let words = Vocabulary.words()   // best effort: Apple's analyzer accepts but largely ignores these hints
        if !words.isEmpty {
            let ctx = AnalysisContext()
            ctx.contextualStrings[.general] = words
            do { try await analyzer.setContext(ctx) } catch { Debug.note("speech context not applied: \(error)") }
        }
        do {
            let audio = try AVAudioFile(forReading: file)
            if try await analyzer.analyzeSequence(from: audio) != nil {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } else {
                await analyzer.cancelAndFinishNow()
            }
            return try await results.value.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            results.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    // MARK: macOS 14-25: SFSpeechRecognizer, forced on-device

    private static func legacyTranscribe(file: URL) async throws -> String {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { _ in c.resume() } }
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { throw LocalError.denied }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else { throw LocalError.unavailable }
        let request = SFSpeechURLRecognitionRequest(url: file)
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.contextualStrings = Vocabulary.words()
        return try await withCheckedThrowingContinuation { c in
            var done = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !done else { return }
                if let result, result.isFinal {
                    done = true
                    c.resume(returning: result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines))
                } else if let error {
                    done = true
                    c.resume(throwing: error)
                }
            }
        }
    }
}
