# AI providers, API keys and requests (`Providers.swift`, `Keychain.swift`)

Read this for provider choice, key storage, onboarding, rate limits, model names, or the API calls.

**Providers:** Groq, Grok (xAI), Claude (Anthropic), Gemini (Google). All keys are optional.

| Provider | Does | Cleanup endpoint | Auth | Model constant (`Provider.cleanupModel`) |
|---|---|---|---|---|
| Groq | cleanup | `POST api.groq.com/openai/v1/chat/completions` | `Authorization: Bearer` | `openai/gpt-oss-20b` |
| Grok (xAI) | cleanup | `POST api.x.ai/v1/responses` | `Authorization: Bearer` | `grok-4.20-0309-non-reasoning` |
| Claude | cleanup | `POST api.anthropic.com/v1/messages` | `x-api-key` + `anthropic-version: 2023-06-01` | `claude-haiku-5-5` |
| Gemini | cleanup | `POST generativelanguage.googleapis.com/v1beta/models/<model>:generateContent` | `x-goog-api-key` header (never in the URL) | `gemini-3.5-flash-lite` |

Groq gates models per organization: `llama-3.1-8b-instant` and `llama-3.3-70b-versatile` returned 404 and the gpt-oss models 403 "blocked at the organization level" on a free account (2026-10-20); an admin enables a model at console.groq.com/settings/limits. 403 is reported as "denied access" with Groq's message, not as a bad key. `--selftest` accepts `WL_MODEL_GROQ=<id>` (and `_XAI`, `_ANTHROPIC`, `_GEMINI`) to try another model. Model names change over time; update them in `Provider.cleanupModel` if calls fail. Settings -> Test makes a real cleanup call, so a stale model name shows up there.

**Test status**
- Groq: cleanup request rewritten in an earlier change; not re-run live. (Groq no longer does speech to text.)
- Gemini: **confirmed working** with a real key (tested from the app's Settings, 2026-10-20).
- Grok: **not yet tested with a real key** (`--selftest xai` once a key is saved).
- Claude: **not tested with a live key.** Written from the official docs. Verified without a key: URLs, headers and the 401/400 auth-error path respond as expected on the real servers, and the response parser handles the documented shapes (`--selftest parse`). Still needs a live check for Claude: a successful generation, the model name, and whether adaptive thinking on Haiku 5.5 adds noticeable latency.

**Where keys are stored:** the macOS login Keychain, as generic passwords. Service `com.prashant.wisprlite`; account `groq-api-key` (unchanged), `xai-api-key`, `anthropic-api-key`, `gemini-api-key`. Keys are never written to the repo, disk files or logs.

**How a key is read** (`Keychain.load(provider)`): the provider's environment variable first (`GROQ_API_KEY`, `XAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`), then the Keychain.

**Which service does what**
- Transcription: always on-device (`Local.swift`, see `transcription/on-device.md`). No provider ever receives audio.
- Cleanup: the provider chosen in Settings (`UserDefaults` key `aiProvider`, default Groq so existing installs are unchanged). If cleanup fails, the raw transcript is pasted. Problems the user can fix (bad key, wrong model; 4xx other than 429) show one alert per distinct message after pasting; transient ones (429, 5xx, network) are only logged to `log.txt`.

**Onboarding and managing keys**
- First launch with no key for any provider and `onboarded` unset: a dialog with a provider picker and key field, "Save key" or "Skip, no AI cleanup". Skip is remembered.
- Settings -> Setup (also menu bar -> "AI provider & key…"): provider popup, then Add / Update / Test / Remove for the selected provider. Saving a key tests it right away and reports a failure.
- AI cleanup requested without a key for the selected provider (dictating with cleanup on, or switching it on): an alert explains it, with "Add key…", "Turn off AI cleanup" and "Dismiss". The dictation is still pasted, uncleaned.

**Self-test:** `WisprLite.app/Contents/MacOS/WisprLite --selftest groq|xai|anthropic|gemini|parse` runs one provider from the terminal (list-models check, then a sample cleanup with timing) using its env var or Keychain key, prints results only, and exits. Safe to run directly because it never records audio. A fake key (`XAI_API_KEY=fake`) probes URLs and error handling without an account.

**Errors:** `ProviderError` (`Providers.swift`) carries the provider name; 401/403 read "rejected the API key", 429 "rate limit hit", others "<provider> error <code>: <message>". xAI answers a bad key with 400 (message "Incorrect API key"), Gemini with 400 `API_KEY_INVALID` (mapped to the same "rejected" message).

**Groq limits:** free tier is per day and resets daily; third-party sources report about 28,800 audio-seconds/day, 2,000 requests/day and 20 requests/min. Verify on the Groq console limits page.

**Privacy:** only the transcript text is sent to the chosen provider, never audio. Without any key nothing leaves the Mac. Check each provider's data-retention terms.
