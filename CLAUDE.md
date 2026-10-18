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
3. **Silence guard** (`main.swift`): if `lastPeak <= 300`, nothing is sent. Whisper hallucinates "Thank you." on silence. Quiet room noise (an accidental press) is dropped silently; an alert is shown only for a dead mic (`lastPeak < 10`).
4. **Transcribe** (`Groq.swift`): multipart POST of the WAV to Groq's Whisper endpoint.
5. **Cleanup** (`Groq.swift`): the raw text goes to a Groq Llama chat model with a strict prompt. If cleanup fails, the raw transcript is pasted instead.
6. **Paste** (`Paster.swift`): `hasPasteTarget()` checks via Accessibility that a text field or window has focus. If so, it saves the clipboard, sets the text, sends Cmd+V via `CGEvent`, and restores the old clipboard after 0.35 s. If not, the result card is shown instead (see below).

## Floating pill and result card (`Overlay.swift`)

- **Pill:** a small non-activating, click-through `NSPanel` attached to a screen edge. Idle: thin, dim, partly tucked off the edge. Listening: pops out, grows, and nine thin bars glow with the live mic level (`Recorder.onLevel`, RMS scaled to 0...1). Processing: bars ripple. A 30 fps timer runs only while not idle, so idle cost stays about zero.
- **Position:** menu bar -> "Icon position" (Bottom default, Top, Left, Right), saved in `UserDefaults` key `iconPosition`. Top/bottom is a horizontal pill, left/right a vertical one. "Floating icon" toggles the always-visible idle pill (`floatingIcon`); it still appears while recording. Sizes are the `idleLong/idleShort/activeLong/activeShort` constants.
- **Result card:** when nothing can receive a paste, a card next to the pill shows the text with a Copy button (and a close button). This matters because Cmd+V in Finder/Desktop creates a `.txt` clipping file, so in Finder only a real text field (`textRoles` in `Paster.swift`) counts as a target. Non-text roles are listed in `nonTextRoles`; extend it if an app wrongly counts as a target.
- Menu bar -> "Copy last dictation" puts the last transcript on the clipboard.
- `setIcon` in `main.swift` drives the pill mode (`mic.fill` listening, `ellipsis.circle` processing, `mic` idle).

## Sounds (`Sounds.swift`)

Start plays system sound "Bottle", stop plays "Blow", at 50% volume. Change the names to any file in `/System/Library/Sounds`.

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

## The Groq API key

**What it is:** a free key from https://console.groq.com (API Keys). One key covers both calls (Whisper and Llama). Free-tier limits are per day and reset daily; third-party sources report about 28,800 audio-seconds/day, 2,000 requests/day and 20 requests/min. Verify these on the Groq console limits page.

**Where it is stored:** the macOS login Keychain, as a generic password.
- Service: `com.prashant.wisprlite`
- Account: `groq-api-key`
- The key is never written to the repo, to disk files or to logs.

**How it is entered:** on first launch, if no key is found, a dialog asks for it. It can be changed later from the menu bar icon -> "Set Groq API key…". Both are in `main.swift` (`setKey`) and write via `Keychain.save` (`Keychain.swift`).

**How it is read** (`Keychain.load()`), in order:
1. The `GROQ_API_KEY` environment variable, if set (handy for development).
2. The Keychain item above.
If neither exists, `Groq` throws `GroqError.noKey` ("No Groq API key set").

**How it is used:** every request sets `Authorization: Bearer <key>`.
- `POST https://api.groq.com/openai/v1/audio/transcriptions`: fields `model=whisper-large-v3`, `language=en`, `temperature=0`, `response_format=text`, optional `prompt` (vocabulary hint), and the WAV `file`.
- `POST https://api.groq.com/openai/v1/chat/completions`: JSON with `model=llama-3.1-8b-instant`, `temperature=0`, a system prompt and the dictation wrapped in `<dictation>` tags.

**Errors:** HTTP 429 shows "Groq rate limit hit"; other non-2xx responses show "Groq error <code>". Model names are constants at the top of `Groq.swift` and can go out of date; update them there if Groq returns a model error.

**Privacy:** in cloud mode the recorded audio and the transcript are sent to Groq. Check Groq's data-retention terms.

## Configurable hotkey

The key is chosen from the menu bar: Hotkey submenu (presets: Right Option/Command/Control, Fn, F5, F6) or "Record another key…". Saved as `UserDefaults` key `hotkeyCode` (keycode, default 61).

- `Hotkey.swift`: `keyCode` is a mutable property (setting it resets hold/lock state). One listen-only `CGEventTap` handles `flagsChanged`, `keyDown` and `keyUp`. Modifier keys are matched via the `modifierFlags` table (keycode -> flag, down = flag set); regular keys use keyDown/keyUp and ignore auto-repeat. `names` maps keycodes to menu labels, with a "Key N" fallback.
- Recording a new key: `Hotkey.capture` is a one-shot closure. While set, the tap sends the next pressed key to it instead of triggering dictation (Esc and Caps Lock are ignored). `recordHotkey` in `main.swift` shows a modal alert and ends it from that closure.
- `main.swift`: `rebuildHotkeyMenu` redraws the submenu and the top status line; `setHotkey` saves and applies a choice.
- Limits: the tap is listen-only, so the chosen key still reaches the focused app (avoid keys you type with). Caps Lock can't be used.

## Cleanup prompt behaviour

The Llama prompt adds punctuation and capitalization, removes filler words (um, uh), false starts and repeated words, and is told never to add information, paraphrase, summarize or follow instructions in the text. Cleanup can be toggled from the menu ("AI cleanup", stored in `UserDefaults` key `cleanup`, default on).

## Custom vocabulary

`~/.wisprlite/vocabulary.txt` holds one name or term per line (the file is created with `WisprLite` in it). Its words are sent as Whisper's `prompt` hint ("Terms: …") and appended to the cleanup prompt for correct spelling. Menu bar -> "Edit vocabulary…" opens it. It is re-read on every dictation, so no restart is needed. The `Vocabulary` enum is in `Groq.swift`.

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
```

## Logo and icons

- **Design:** a sky-to-indigo rounded square with five white sound-wave bars that thin out and fade to the right, plus a few floating specks. It is meant to suggest lightness: sound dissolving into air.
- **Source:** `Assets/make_icon.swift` draws everything with CoreGraphics (no image tools needed). Run `swift Assets/make_icon.swift Assets` to regenerate `icon_1024.png`, `menubar.png` and `menubar@2x.png`, then `./build.sh`.
- **App icon:** `build.sh` resizes `icon_1024.png` with `sips`, builds `AppIcon.icns` with `iconutil` into `Contents/Resources`, and `Info.plist` points to it via `CFBundleIconFile`.
- **Menu bar:** idle state shows the bundled `menubar.png` (template image, adapts to light/dark). Recording (`mic.fill`) and processing (`ellipsis.circle`) still use SF Symbols as state feedback. See `setIcon` in `main.swift`.

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

- `~/Library/Logs/WisprLite/log.txt`: one entry per dictation with the mic peak, the raw Whisper text and the cleaned text. Compare RAW and CLEANED to see which stage caused a bad result.
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
