# Result card (`Overlay.swift`, `Paster.swift`)

Read this for anything about the card shown when a dictation can't be pasted: its content, buttons, countdown ring, auto-dismiss, or what counts as a paste target.

- When nothing can receive a paste, a card next to the pill shows the text with a Copy button and a close button. Copy closes it after about a second.
- **Auto-dismiss:** a ring around the close button drains over 10 s (`cardLifetime`), then the card fades out. A 10 Hz timer (`startCardTimer`) drives both the ring and the countdown, and it pauses while the mouse is over the card. The text is still saved in History.
- **Paste target:** Cmd+V in Finder/Desktop creates a `.txt` clipping file, so in Finder only a real text field (`textRoles` in `Paster.swift`) counts as a target. Non-text roles are listed in `nonTextRoles`; extend it if an app wrongly counts as a target.
- **Unknown roles** (e.g. a browser's `AXWebArea`/`AXGroup` when focus is on the page but not the chat box) only count as a target if the element exposes `AXSelectedTextRange` or a settable `AXValue`; otherwise the card shows.
- Menu bar -> "Copy last dictation" puts the last transcript on the clipboard.
