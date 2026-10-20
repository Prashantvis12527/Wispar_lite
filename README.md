<div align="center">

<img src="Assets/icon_1024.png" alt="WisprLite logo" width="128" height="128">

# WisprLite

**Hold a key, speak, release. Your words appear in whatever app you're using.**

A small, native push-to-talk dictation tool for macOS. It runs as a menu-bar agent with no window and no Dock icon. Speech is transcribed on your Mac with Apple's built-in model, so nothing large is bundled and your audio stays local.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift)
![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)
![Speech](https://img.shields.io/badge/speech-on--device-blue)

</div>

---

## Why WisprLite

Many dictation apps are large desktop programs with a heavy interface and a big memory footprint. WisprLite does one job: it turns speech into text in any app.

- **Lightweight.** It's a single native Swift binary. The audio engine exists only while you're recording, so idle cost is close to zero.
- **Works everywhere.** The text is pasted into the focused app: editors, browsers, chat, email, terminals.
- **Accurate first.** It transcribes what you said and doesn't rewrite it. Cleanup only fixes punctuation, capitalization and filler words.
- **Free to run.** Transcription is on-device. Optional AI cleanup works with a free-tier key from Groq or Gemini, or a key from Grok or Claude.
- **No dependencies.** It uses Apple frameworks only, with no third-party packages.

## Features

- **Push-to-talk or hands-free.** Hold the hotkey and release to paste. Double-tap to lock recording on, then tap once more to stop.
- **Configurable hotkey.** Pick a preset (Right Option, Right Command, Right Control, Fn, F5, F6) or record any other key.
- **Optional AI cleanup.** Choose Groq, Grok, Claude or Gemini to add punctuation and remove "um", "uh", false starts and repeated words. It never adds, paraphrases or summarizes, and only text is sent. You can turn it off.
- **Custom vocabulary.** Add names and technical terms to a text file so they're spelled correctly.
- **Safe paste.** Your clipboard is saved and restored after pasting. If no text field has focus, a result card with a Copy button is shown instead.
- **Silence protection.** Silent or near-silent recordings are dropped before transcription.
- **Floating pill and sounds.** A small overlay and start/stop sounds show recording state. The pill can be hidden.
- **Launch at login.** A toggle in Settings starts WisprLite when you log in.
- **Dashboard.** Words per minute, total words, a streak heatmap and a searchable history of past dictations.
- **Private by design.** Speech is transcribed on your Mac with Apple's on-device model, so your audio is never sent anywhere. An API key, if you add one, is stored in the macOS Keychain, and only the text goes to that provider for cleanup. History stays on your machine.

## How it works

```
Hotkey  →  Record mic  →  Apple on-device speech (speech to text)  →  optional AI cleanup  →  Paste into focused app
```

1. A listen-only global event tap watches for your hotkey.
2. The microphone is recorded as 16 kHz mono audio and kept in memory.
3. The audio is transcribed on your Mac by Apple's Speech framework (SpeechAnalyzer on macOS 26+). It is never uploaded.
4. If AI cleanup is on and you added a key, the text (not the audio) goes to your chosen provider (Groq, Grok, Claude or Gemini) with a strict cleanup prompt. If cleanup fails, the raw transcript is pasted instead.
5. The result is pasted with a synthesized Cmd+V.

## Requirements

- macOS 14 (Sonoma) or later, Apple Silicon or Intel
- Swift toolchain (Xcode or Command Line Tools) to build from source
- Optional: an API key for AI cleanup from Groq (free), Grok (xAI), Claude (Anthropic) or Gemini (Google). Without one, dictation runs on-device with no cleanup.

## Install

WisprLite is built from source. There's no prebuilt release yet.

```bash
git clone https://github.com/Prashantvis12527/Wispar_lite.git
cd Wispar_lite
./build.sh
open WisprLite.app
```

Always launch the `.app` with `open` or by double-clicking it. Running the binary inside `Contents/MacOS` makes macOS attribute the permissions to Terminal instead.

### Code signing

`build.sh` signs the app with a local self-signed certificate named **WisprLite Local**. macOS ties permissions to the code signature, so a stable identity stops it from asking for permissions again after every rebuild. If the certificate isn't in your login Keychain, the script falls back to ad-hoc signing and the permissions will reset on each rebuild. See [`CLAUDE.md`](CLAUDE.md) for how to create the certificate.

## Setup

1. Launch the app. A menu-bar icon appears.
2. Pick a provider and paste its API key when prompted, or skip and use the raw transcript. You can add, test, update or remove keys later in **Settings** (menu: **AI provider & key…**).
3. Grant the permissions macOS asks for. On macOS 14 to 25 it also asks for **Speech Recognition**.

   | Permission | Why it's needed |
   |---|---|
   | **Microphone** | To record your voice |
   | **Accessibility** | To send the paste keystroke and detect the focused field |
   | **Input Monitoring** | To detect the global hotkey |

## Usage

| Action | Result |
|---|---|
| Hold the hotkey (≥ 0.35 s), speak, release | Text is pasted |
| Double-tap the hotkey, speak, tap once more | Hands-free dictation, text is pasted |
| Single quick tap | Ignored, and the recording is discarded |

The default hotkey is **Right Option**. Change it from the menu bar under **Hotkey**.

### Custom vocabulary

Rare words, product names and acronyms are easy for speech models to mishear. List them in `~/.wisprlite/vocabulary.txt`, one per line, or open the file from the menu with **Edit vocabulary…**. The file is re-read on every dictation, so there's no need to restart.

## Privacy

- Audio is always transcribed on your Mac and is never uploaded.
- If you turn on AI cleanup, only the transcript text goes to the provider you chose. Review that provider's data and retention terms before using it with sensitive content. With cleanup off, nothing leaves your Mac.
- Your API keys are kept in the macOS Keychain and are never written to disk files or logs.
- History is stored locally at `~/.wisprlite/history.jsonl`. You can delete entries from the dashboard.
- There is no analytics or telemetry.

## Project structure

```
Sources/WisprLite/
  main.swift       App delegate, menu bar, permissions, orchestration
  Hotkey.swift     Global hotkey with hold and double-tap detection
  Recorder.swift   Microphone capture to 16 kHz mono WAV
  Local.swift      On-device speech to text (Apple Speech framework)
  Providers.swift  Optional AI cleanup providers (Groq, Grok, Claude, Gemini)
  SelfTest.swift   Terminal check of one provider (no audio)
  Vocabulary.swift Custom vocabulary file
  Paster.swift     Paste-target check, clipboard-safe paste
  Overlay.swift    Floating pill and result card
  Sounds.swift     Start and stop sounds
  Keychain.swift   API key storage
  History.swift    Local history and statistics
  Dashboard.swift  Insights, History and Settings window
```

Per-feature design notes live in [`.claude/features/`](.claude/features), and [`CLAUDE.md`](CLAUDE.md) has the full project overview.

## Limitations

- English only.
- The hotkey tap is listen-only, so the chosen key still reaches the focused app. Choose a key you don't type with. Caps Lock can't be used.
- Transcription works offline. AI cleanup needs an internet connection.
- The first run may download Apple's English speech model.

## Contributing

Issues and pull requests are welcome. For a bigger change, please open an issue first so we can talk it through. Before submitting, check that `./build.sh` succeeds and test a full dictation end to end.

## Acknowledgements

- Apple's Speech framework for on-device speech recognition
- [Groq](https://groq.com), [xAI](https://x.ai), [Anthropic](https://www.anthropic.com) and [Google](https://ai.google.dev) for optional text cleanup
