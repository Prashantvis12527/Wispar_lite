# Settings tab

Rows: Hotkey (Change…), AI cleanup, Launch at login, Floating icon, Icon position, Save dictation text, Clear history and stats, AI provider, API key, Transcription (read-only status), Vocabulary.

- Built in `makeSettings` in `Dashboard.swift` from small helpers (`group`, `setting`, `toggle`, `button`). To add a setting, add a row there and, if the app owns the state, a method on `DashboardHost` implemented in the `App` extension in `main.swift`.
- Changing a setting in the menu or here reloads the other (`dashboard.reload()`).
- Launch at login uses `SMAppService.mainApp` (state lives in the OS, not `UserDefaults`). It registers the app at its current path, so move `WisprLite.app` to its final location before enabling. The menu item is re-read from the live status each time the menu opens.

- AI provider is a popup (Groq, Grok, Claude, Gemini). The key row below it is for the selected provider: Add… when no key exists, otherwise Update…, Test and Remove…. See `groq/api-key.md`.
