# Groq API key and requests (`Groq.swift`, `Keychain.swift`)

Read this for the key, Keychain storage, rate limits, model names, or the API calls.

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
