# WisprLite: project overview

A lightweight macOS push-to-talk dictation tool. Hold a hotkey, speak, release, and the transcribed text is pasted into whatever app has focus.

**What it solves:** voice dictation tools are often heavy desktop apps with large memory footprints and a lot of UI. WisprLite does one job, turning speech into text in any app, as a small native Swift menu-bar agent with no window, no Dock icon and no bundled speech model. Transcription uses Apple's on-device speech model, held by a system helper that only exists while you dictate; optional text cleanup is done by a hosted model (Groq, Grok, Claude or Gemini).

**Priorities, in order:** (1) low memory use, (2) accurate transcription of what was actually said, (3) light cleanup (punctuation, filler words). Audio is always transcribed on-device. No paid services, English only, latest macOS only.

## How it works (pipeline)

```
Hotkey (default Right Option)  ->  record mic  ->  Apple on-device speech (speech to text)
                                  ->  optional AI cleanup (Groq/Grok/Claude/Gemini, text only)  ->  paste into focused app
```

1. **Hotkey** (`Hotkey.swift`): user-selectable (menu bar -> Hotkey; presets or "Record another key…"), default Right Option (keycode 61). Stored in `UserDefaults` key `hotkeyCode`. Watched globally via a listen-only `CGEventTap` on `flagsChanged` (modifiers) and `keyDown`/`keyUp` (regular keys like F5).
   - Hold >= 0.35 s then release: push-to-talk, finish and paste.
   - Double-tap within 0.5 s: recording locks on; one more tap stops and pastes.
   - A single short tap is ignored and discards the recording.
2. **Record** (`Recorder.swift`): `AVAudioEngine` microphone tap, converted with `AVAudioConverter` to 16 kHz mono 16-bit PCM, wrapped as an in-memory WAV. The engine exists only while recording, so idle cost is about zero. `lastPeak` stores the loudest sample.
3. **Silence guard** (`main.swift`): if `lastPeak <= 300`, nothing is sent. Quiet room noise (an accidental press) is dropped silently; an alert is shown only for a dead mic (`lastPeak < 10`).
4. **Transcribe** (`Local.swift`): on-device only, Apple `SpeechAnalyzer`/`SpeechTranscriber` on macOS 26+ (`SFSpeechRecognizer`, forced on-device, before that). Audio never leaves the Mac. See `transcription/on-device.md`.
5. **Cleanup** (`Providers.swift`, optional): the raw text (never audio) goes to the chosen provider (Groq, Grok, Claude or Gemini) with a strict prompt. If cleanup fails, the raw transcript is pasted instead.
6. **Paste** (`Paster.swift`): `hasPasteTarget()` checks via Accessibility that an editable text element has focus (see `.claude/features/paste/paste-target.md`). If so, it saves the clipboard, sets the text (with a leading space if it would glue onto the previous word, see `.claude/features/paste/paste.md`), sends Cmd+V via `CGEvent`, and restores the old clipboard after 0.35 s. If not, the result card is shown instead (see `.claude/features/overlay/result-card.md`).

## Where the details live

Before editing a feature, read only the file that matches the task. Paths are under `.claude/features/`.

| If the task is about... | Read |
|---|---|
| The floating pill: look, animation, size, position, floating-icon toggle | `overlay/pill.md` |
| The result card: Copy, close button, countdown ring, auto-dismiss, paste-target detection | `overlay/result-card.md` |
| The dashboard window in general | `dashboard/README.md` |
| Words per minute, total words, streak heatmap | `dashboard/insights.md` |
| Past dictations list, Copy/Delete, history file | `dashboard/history.md` |
| The Settings tab | `dashboard/settings.md` |
| Pasting, spacing between dictations, clipboard restore | `paste/paste.md` |
| Deciding paste vs. result card (`hasPasteTarget`, focus roles, browsers, Finder) | `paste/paste-target.md` |
| Speech to text: engine, English model asset, RAM, latency, accuracy, benchmark | `transcription/on-device.md` |
| Hotkey, hold / double-tap, recording a new key | `hotkey/hotkey.md` |
| Providers (Groq/Grok/Claude/Gemini), keys, Keychain, onboarding, model names, API calls, self-test | `groq/api-key.md` |
| Cleanup prompt, AI cleanup toggle, vocabulary file | `groq/cleanup-and-vocabulary.md` |
| Start/stop sounds | `sounds/sounds.md` |
| App icon, menu-bar glyph | `branding/logo.md` |

When you add a feature, give it a file here and add a row to this table instead of writing it up in this overview.

## Tech stack

| Layer | Choice |
|---|---|
| Language | Swift 6.3 toolchain, Swift 5 language mode (`swift-tools-version:5.9`) |
| Build | SwiftPM (`Package.swift`) plus `build.sh`, which hand-assembles `WisprLite.app` |
| UI | AppKit menu-bar agent (`LSUIElement`, `NSStatusItem`), no windows |
| Audio | `AVFoundation` (`AVAudioEngine`, `AVAudioConverter`) |
| Hotkey | `CoreGraphics` `CGEventTap` (listen-only) |
| Paste | `NSPasteboard` plus synthesized `CGEvent` Cmd+V |
| Speech to text | Apple Speech framework, on-device (`SpeechAnalyzer` on macOS 26+) |
| Cleanup (optional) | Groq `openai/gpt-oss-20b`, xAI `grok-4.20-0309-non-reasoning`, Anthropic `claude-haiku-5-5` or Google `gemini-3.5-flash-lite` (user's choice; constants in `Provider.cleanupModel`) |
| Network | `URLSession`, no third-party dependencies |
| Secrets | macOS Keychain |
| Target | macOS 14+, built and tested on macOS 27 / Apple Silicon |

No external packages. The only dependencies are Apple frameworks.

## File map

```
wispar_flow/
  Package.swift              SwiftPM manifest (one executable target, macOS 14+)
  build.sh                   builds release binary, creates WisprLite.app, builds AppIcon.icns, writes Info.plist, signs it
  CLAUDE.md                  this file (project overview for AI assistants)
  README.md                  public GitHub README (install, setup, usage, privacy); no troubleshooting section, debugging notes live here
  Assets/                    logo: make_icon.swift draws icon_1024.png and the menubar glyph (re-run: swift Assets/make_icon.swift Assets)
  Sources/WisprLite/
    main.swift               App delegate, menu bar (logo glyph + state icons), permissions, orchestration, Debug logging
    Hotkey.swift             global hotkey (configurable) hold / double-tap detection
    Recorder.swift           mic capture -> 16 kHz mono WAV, peak and live level
    Vocabulary.swift         user vocabulary file (~/.wisprlite/vocabulary.txt)
    Providers.swift          Provider enum (Groq/Grok/Claude/Gemini), Cleanup calls, key verify/test, ProviderError
    SelfTest.swift           --selftest terminal check of one provider (no audio)
    Local.swift              on-device speech to text (SpeechAnalyzer / SFSpeechRecognizer), speech-model asset check and install
    Paster.swift             paste-target check, clipboard-safe Cmd+V paste
    Overlay.swift            floating pill (edge-attached, glowing bars) and result card with Copy
    Sounds.swift             start/stop feedback sounds
    Keychain.swift           per-provider API key storage and lookup
    History.swift            append-only ~/.wisprlite/history.jsonl, plus Stats (WPM, total words, streaks)
    Dashboard.swift          Insights / History / Settings window (built on open, freed on close)
```

## Permissions

- **Microphone (required):** to record. If not yet decided, the app requests it; if denied, an alert explains how to fix it.
- **Speech Recognition:** only on macOS 14-25 (the SFSpeechRecognizer fallback). Not needed on macOS 26+.
- **Accessibility (required):** to send the Cmd+V paste.
- **Input Monitoring (required):** for the global hotkey. Without it, the hotkey does nothing and no "Tink" plays.

## Signing, and why it matters

`build.sh` signs the app with a local self-signed certificate named **"WisprLite Local"** (in the login Keychain). macOS ties permissions to the app's code signature. With plain ad-hoc signing, the signature changed on rebuilds and macOS forgot the permissions and kept asking, so the stable identity fixes this. If the certificate is missing, `build.sh` falls back to ad-hoc signing (`-`), and permissions will reset again.

To recreate the certificate, make a self-signed code-signing cert (EKU `codeSigning`, CN `WisprLite Local`), export it with `openssl pkcs12 -export -legacy`, and import it with `security import ... -T /usr/bin/codesign`.

## Build and run

```
./build.sh                        # builds WisprLite.app next to the script
open WisprLite.app                # run it (always launch the .app, never the raw binary)
```

Launch via `open` or double-click on the `.app`. Running the binary inside `Contents/MacOS` makes macOS attribute permissions to Terminal instead.

Terminal helpers (neither records audio; both are documented in `groq/api-key.md` and `transcription/on-device.md`):

```
WisprLite.app/Contents/MacOS/WisprLite --selftest groq|xai|anthropic|gemini|parse   # one provider's key, endpoint and cleanup call
WisprLite.app/Contents/MacOS/WisprLite --bench speechTranscriber file.wav...        # on-device engine latency, RAM, text
```

Use `open -n -W --stdout out.tsv WisprLite.app --args --bench sfSpeech ...` for the `sfSpeech` engine so macOS can show its permission prompt. A provider's env var (`GROQ_API_KEY`, `XAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`) overrides its Keychain key.

If permissions get stuck: `tccutil reset All com.prashant.wisprlite`, relaunch, and re-grant.

## Debugging

- `~/Library/Logs/WisprLite/log.txt`: one entry per dictation with the mic peak, the raw on-device transcript and the cleaned text. Compare RAW and CLEANED to see which stage caused a bad result. `paste app=...` lines show how the leading-space decision was made.
- `~/Library/Logs/WisprLite/last.wav`: the most recent recording, playable in any audio app.
- RAM check: `footprint $(pgrep WisprLite)`.

## Gotchas learned along the way

- Silent audio can make speech engines invent text, so the peak check drops near-silent recordings before transcribing.
- Menu-bar agents have no main menu, so Cmd+V/C/X/A didn't work in the app's own dialogs until an Edit menu was added in `main.swift`.
- Made-up or rare words (like the app's own name) are mis-heard locally, and Apple's analyzer largely ignores vocabulary hints (see `transcription/on-device.md`). The vocabulary file still helps AI cleanup spell them.
- Model names on every provider change over time. Update `Provider.cleanupModel` if calls fail. Providers also gate models per account: on a free Groq account `llama-3.1-8b-instant` returned 404 and the gpt-oss models 403 until enabled in the org settings. A 403 shows as "denied access" with the provider's message; only 401 means a bad key.
- `SpeechTranscriber.installedLocales` can list a language whose model is not installed. Trust `AssetInventory.status` (`Local.assets()`) instead.
- `--bench sfSpeech` aborts if run directly from Terminal (no Speech permission attribution); launch it through `open`.
- Launch at login registers the app at its current path (`SMAppService.mainApp`). Move `WisprLite.app` to its final location before enabling it. See `.claude/features/dashboard/settings.md`.

## Not built yet

- Live testing of the Grok and Claude integrations with real keys (Gemini is confirmed working; Groq works once its model is enabled in the Groq console). Status is tracked in `groq/api-key.md`.
- Benchmarking the macOS 14-25 `SFSpeechRecognizer` fallback, and comparing local accuracy against Whisper.
- Notarization or a real Developer ID signature (not needed for personal use).
