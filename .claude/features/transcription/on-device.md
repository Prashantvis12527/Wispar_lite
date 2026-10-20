# On-device transcription (`Local.swift`)

Read this for speech-to-text: engine choice, the English model asset, memory, latency, accuracy, known limits.

**Rule:** audio is transcribed on this Mac with Apple's Speech framework and never sent anywhere. Only the finished *text* can leave, and only to the AI-cleanup provider the user chose. There is no cloud transcription and no bundled or downloaded third-party model.

## Engines
- **macOS 26+ (primary):** `SpeechAnalyzer` + `SpeechTranscriber` (`.transcription` preset, `modelRetention: .whileInUse`). The recorded WAV is fed with `analyzeSequence(from:)` after the hotkey is released, then `finalizeAndFinishThroughEndOfInput()`. No Speech Recognition permission is needed.
- **macOS 14-25 (fallback):** `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` (needs the Speech Recognition permission). Not benchmarked: it needs the permission prompt answered and there was no macOS 14-25 machine. Treat as unverified.
- `DictationTranscriber` is also wired (`--bench dictationTranscriber`) but not used: worse on every measure below.
- The deployment target stays macOS 14, so SpeechAnalyzer code is behind `#available(macOS 26.0, *)`.

## The language asset
SpeechTranscriber needs Apple's English model, managed by the OS (`AssetInventory`). Note `SpeechTranscriber.installedLocales` listed en_US even when `AssetInventory.status` said `downloadable`, so trust the status. `Local.assets()` reads it; at launch the app checks it, and if missing offers a one-time system install (`Local.installAssets()`, the "Install…" button in Settings -> Transcription). If a dictation finds the model missing, the app offers the install and then transcribes the same recording, so nothing is lost. After install, dictation works fully offline.

## Measured on this Mac (macOS 27.0.1, Apple Silicon), 2026-10-20
Corpus: 40 TTS clips (8 sentences x 5 voices, ~4.7 s) plus the same 40 with 10 dB white noise, plus one real human recording (12 s). TTS is cleaner than real speech, so absolute accuracy is flattered; the comparison between engines is the useful part.

| | SpeechTranscriber | DictationTranscriber |
|---|---|---|
| WER, clean TTS | **8.7%** | 14.4% |
| WER, noisy TTS (10 dB) | **21.1%** | 25.2% |
| Latency, warm (median / p90 / max) | **140 / 157 / 214 ms** | 285 / 1098 / 2283 ms |
| Latency, cold single dictation (6 runs) | 137-609 ms | not measured |
| WisprLite process footprint | 2 MB idle, 6-7 MB peak | same |
| Apple's helper (`localspeechrecognition`) | peak footprint ~57 MB, RSS ~69 MB | ~60 MB, RSS ~95 MB |

- **RAM:** the model lives in Apple's `localspeechrecognition` helper, not in WisprLite. The helper does not exist when idle, starts on demand (~0.2 s) and is gone about a second after the dictation ends. So idle cost is ~0 and peak is ~57 MB system-wide for the duration of one transcription.
- **Offline:** the benchmark ran with all network denied (`sandbox-exec (deny network*)`), and `lsof` showed zero network sockets on both WisprLite and the helper during a run. Caveat: the sandbox applies to WisprLite, not to Apple's helper; the zero-sockets check covers the helper.
- **Real recording** (vs Whisper large-v3 output as reference, not ground truth): SpeechTranscriber kept the disfluency ("uh"), and heard "WisprLite" as "with polite"; DictationTranscriber got "WisprLite" right but dropped the first word.
- **Not measured:** Whisper large-v3 on the same corpus (no Groq key available), and SFSpeech. Expect Whisper to be more accurate than SpeechTranscriber; this change trades some accuracy for privacy and zero idle RAM.

## Known limits
- **Custom vocabulary is largely ignored.** `AnalysisContext.contextualStrings` is accepted without error but made no difference in tests for either transcriber (set via `setContext` or at init). Rare names ("WisprLite") are often misheard locally. If AI cleanup is on, the provider is told the vocabulary and can correct spelling when the misheard form is close.
- Punctuation and capitalization are added by SpeechTranscriber, but "uh/um" can survive; cleanup removes them.
- Unsupported locale/English variant: `Local.locale` is fixed to en-US.

## Benchmark tool
`WisprLite.app/Contents/MacOS/WisprLite --bench speechTranscriber|dictationTranscriber|sfSpeech file.wav...` prints one TSV line per file (ms, text) and the process footprint. `--bench install` installs the English model. `sfSpeech` must be launched via `open -n -W --stdout out.tsv WisprLite.app --args --bench sfSpeech ...` so macOS can attribute the Speech permission to the app. Run one engine per process so memory is attributable.
