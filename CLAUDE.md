# WisprLite: project overview

A lightweight macOS push-to-talk dictation tool. Hold a hotkey, speak, release, and the transcribed text is pasted into whatever app has focus.

**What it solves:** voice dictation tools are often heavy desktop apps with large memory footprints and a lot of UI. WisprLite does one job, turning speech into text in any app, as a small native Swift menu-bar agent with no window, no Dock icon and no bundled speech model. Transcription and cleanup are done by Groq's hosted models, so nothing large is loaded locally.

**Priorities, in order:** (1) low memory use, (2) accurate transcription of what was actually said, (3) light cleanup (punctuation, filler words). No paid services, English only, latest macOS only.

## How it works (pipeline)

```
Hotkey (default Right Option)  ->  record mic  ->  Groq Whisper (speech to text)
                                  ->  Groq Llama (light cleanup)  ->  paste into focused app
```

1. **Hotkey** (`Hotkey.swift`): user-selectable (menu bar -> Hotkey; presets or "Record another key…"), default Right Option (keycode 61). Stored in `UserDefaults` key `hotkeyCode`. Watched globally via a listen-only `CGEventTap` on `flagsChanged` (modifiers) and `keyDown`/`keyUp` (regular keys like F5).
   - Hold >= 0.35 s then release: push-to-talk, finish and paste.
   - Double-tap within 0.5 s: recording locks on; one more tap stops and pastes.
   - A single short tap is ignored and discards the recording.
2. **Record** (`Recorder.swift`): `AVAudioEngine` microphone tap, converted with `AVAudioConverter` to 16 kHz mono 16-bit PCM, wrapped as an in-memory WAV. The engine exists only while recording, so idle cost is about zero. `lastPeak` stores the loudest sample.
3. **Silence guard** (`main.swift`): if `lastPeak <= 300`, nothing is sent. A transcript that is only an echo of the vocabulary hint is also dropped. Whisper hallucinates "Thank you." on silence. Quiet room noise (an accidental press) is dropped silently; an alert is shown only for a dead mic (`lastPeak < 10`).
4. **Transcribe** (`Groq.swift`): multipart POST of the WAV to Groq's Whisper endpoint.
5. **Cleanup** (`Groq.swift`): the raw text goes to a Groq Llama chat model with a strict prompt. If cleanup fails, the raw transcript is pasted instead.
6. **Paste** (`Paster.swift`): `hasPasteTarget()` checks via Accessibility that a text field or window has focus. If so, it saves the clipboard, sets the text (with a leading space if it would glue onto the previous word, see `.claude/features/paste/paste.md`), sends Cmd+V via `CGEvent`, and restores the old clipboard after 0.35 s. If not, the result card is shown instead (see `.claude/features/overlay/result-card.md`).

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
| Hotkey, hold / double-tap, recording a new key | `hotkey/hotkey.md` |
| Groq key, Keychain, rate limits, model names, API calls | `groq/api-key.md` |
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
| Speech to text | Groq cloud, `whisper-large-v3` |
| Cleanup | Groq cloud, `llama-3.1-8b-instant` |
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
  Assets/                    logo: make_icon.swift draws icon_1024.png and the menubar glyph (re-run: swift Assets/make_icon.swift Assets)
  Sources/WisprLite/
    main.swift               App delegate, menu bar (logo glyph + state icons), permissions, orchestration, Debug logging
    Hotkey.swift             global hotkey (configurable) hold / double-tap detection
    Recorder.swift           mic capture -> 16 kHz mono WAV, peak and live level
    Groq.swift               Groq Whisper + Llama calls, Vocabulary
    Paster.swift             paste-target check, clipboard-safe Cmd+V paste
    Overlay.swift            floating pill (edge-attached, glowing bars) and result card with Copy
    Sounds.swift             start/stop feedback sounds
    Keychain.swift           API key storage and lookup
    History.swift            append-only ~/.wisprlite/history.jsonl, plus Stats (WPM, total words, streaks)
    Dashboard.swift          Insights / History / Settings window (built on open, freed on close)
```

## Permissions (all required)

- **Microphone:** to record. If not yet decided, the app requests it; if denied, an alert explains how to fix it.
- **Accessibility:** to send the Cmd+V paste.
- **Input Monitoring:** for the global hotkey. Without it, the hotkey does nothing and no "Tink" plays.

## Signing, and why it matters

`build.sh` signs the app with a local self-signed certificate named **"WisprLite Local"** (in the login Keychain). macOS ties permissions to the app's code signature. With plain ad-hoc signing, the signature changed on rebuilds and macOS forgot the permissions and kept asking, so the stable identity fixes this. If the certificate is missing, `build.sh` falls back to ad-hoc signing (`-`), and permissions will reset again.

To recreate the certificate, make a self-signed code-signing cert (EKU `codeSigning`, CN `WisprLite Local`), export it with `openssl pkcs12 -export -legacy`, and import it with `security import ... -T /usr/bin/codesign`.

## Build and run

```
./build.sh                        # builds WisprLite.app next to the script
open WisprLite.app                # run it (always launch the .app, never the raw binary)
```

Launch via `open` or double-click on the `.app`. Running the binary inside `Contents/MacOS` makes macOS attribute permissions to Terminal instead.

If permissions get stuck: `tccutil reset All com.prashant.wisprlite`, relaunch, and re-grant.

## Debugging

- `~/Library/Logs/WisprLite/log.txt`: one entry per dictation with the mic peak, the raw Whisper text and the cleaned text. Compare RAW and CLEANED to see which stage caused a bad result. `paste app=...` lines show how the leading-space decision was made.
- `~/Library/Logs/WisprLite/last.wav`: the most recent recording, playable in any audio app.
- RAM check: `footprint $(pgrep WisprLite)`.

## Gotchas learned along the way

- A "Thank you" output with every dictation means silent audio reached Whisper (mic permission missing or no input). The peak check now catches this.
- Menu-bar agents have no main menu, so Cmd+V/C/X/A didn't work in the app's own dialogs until an Edit menu was added in `main.swift`.
- Made-up or rare words (like the app's own name) are mis-heard by Whisper. Add them to the vocabulary file.
- Whisper models, and Llama model names on Groq, change over time. Update the constants in `Groq.swift` if calls fail.

## Not built yet

- Offline fallback (Apple on-device speech recognition).
- Launch at login.
- Gemini free-tier fallback.
- Notarization or a real Developer ID signature (not needed for personal use).
