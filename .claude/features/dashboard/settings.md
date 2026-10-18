# Settings tab

Rows: Hotkey (Change…), AI cleanup, Floating icon, Icon position, Save dictation text, Clear history and stats, Groq API key, Vocabulary.

- Built in `makeSettings` in `Dashboard.swift` from small helpers (`group`, `setting`, `toggle`, `button`). To add a setting, add a row there and, if the app owns the state, a method on `DashboardHost` implemented in the `App` extension in `main.swift`.
- Changing a setting in the menu or here reloads the other (`dashboard.reload()`).
