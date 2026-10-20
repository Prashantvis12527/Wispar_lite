# Result card (`Overlay.swift`, `Paster.swift`)

Read this for anything about the card shown when a dictation can't be pasted: its content, buttons, countdown ring, auto-dismiss, or what counts as a paste target.

- When nothing can receive a paste, a card next to the pill shows the text with a Copy button and a close button. Copy closes it after about a second.
- **Auto-dismiss:** a ring around the close button drains over 10 s (`cardLifetime`), then the card fades out. A 10 Hz timer (`startCardTimer`) drives both the ring and the countdown, and it pauses while the mouse is over the card. The text is still saved in History.
- **Paste target:** whether the card shows is decided by `hasPasteTarget()`; see `paste/paste-target.md`.
- Menu bar -> "Copy last dictation" puts the last transcript on the clipboard.
