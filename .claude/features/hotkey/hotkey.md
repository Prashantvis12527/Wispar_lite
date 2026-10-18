# Hotkey (`Hotkey.swift`)

Read this for the hotkey, hold / double-tap behaviour, or the "Record another key…" flow.

The key is chosen from the menu bar: Hotkey submenu (presets: Right Option/Command/Control, Fn, F5, F6) or "Record another key…". Saved as `UserDefaults` key `hotkeyCode` (keycode, default 61).

- `Hotkey.swift`: `keyCode` is a mutable property (setting it resets hold/lock state). One listen-only `CGEventTap` handles `flagsChanged`, `keyDown` and `keyUp`. Modifier keys are matched via the `modifierFlags` table (keycode -> flag, down = flag set); regular keys use keyDown/keyUp and ignore auto-repeat. `names` maps keycodes to menu labels, with a "Key N" fallback.
- Recording a new key: `Hotkey.capture` is a one-shot closure. While set, the tap sends the next pressed key to it instead of triggering dictation (Esc and Caps Lock are ignored). `recordHotkey` in `main.swift` shows a modal alert and ends it from that closure.
- `main.swift`: `rebuildHotkeyMenu` redraws the submenu and the top status line; `setHotkey` saves and applies a choice.
- Limits: the tap is listen-only, so the chosen key still reaches the focused app (avoid keys you type with). Caps Lock can't be used.
