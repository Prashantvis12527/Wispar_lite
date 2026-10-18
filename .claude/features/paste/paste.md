# Pasting text (`Paster.swift`)

Read this for how dictated text lands in the focused app: clipboard handling and the spacing between consecutive dictations. Paste-target detection is in `overlay/result-card.md`.

- **Mechanism:** `Paster.paste` saves the clipboard, sets the text, sends Cmd+V via `CGEvent`, and restores the old clipboard after 0.35 s.
- **Leading space:** so consecutive dictations don't glue together ("word" + "Next" -> "wordNext"), `needsLeadingSpace()` decides whether to prepend one space.
  1. It reads the character before the caret through Accessibility (`characterBeforeCaret`: `AXSelectedTextRange` + `AXValue`). If that character is not whitespace or an opening bracket/quote/`/`/`-`, a space is added.
  2. A caret at position 0 counts as unknown (apps like VS Code report it unreliably), as does any app that exposes no text.
  3. Fallback when unknown: add a space if the last paste was in the same app (bundle id) within 120 s (`lastPasteApp`, `lastPasteEnd`).
  - Tradeoff: clearing a field and dictating again in the same app within 2 minutes can add a stray leading space.
- **Not handled:** capitalization of a chunk that continues an unfinished sentence.
- Each paste logs a `paste app=... -> space=...` line to `~/Library/Logs/WisprLite/log.txt` (`Debug.note`), showing which path decided.
- **Prompt-echo guard:** with near-silent audio Whisper can echo its vocabulary hint (e.g. "WisprLite."). `Vocabulary.isPromptEcho` drops such results in `main.swift` before cleanup, so nothing is pasted. See `groq/cleanup-and-vocabulary.md`.
