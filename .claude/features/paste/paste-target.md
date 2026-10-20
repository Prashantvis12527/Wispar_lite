# Paste-target detection (`Paster.swift`, `hasPasteTarget()`)

Read this when dictation pastes somewhere it shouldn't, or the result card fails to appear when nothing can take the text.

`hasPasteTarget()` decides between pasting (Cmd+V) and showing the result card (see `overlay/result-card.md`). It uses the Accessibility focused element of the frontmost app:

1. **Finder:** only a real text field (`textRoles`) counts, because Cmd+V on a selection or the Desktop creates a `.txt` clipping file.
2. **Known text roles** (`textRoles`: text field, text area, combo box, search field): paste.
3. **Known non-text roles** (`nonTextRoles`: lists, tables, buttons, images, scroll areas, desktop...): show the card.
4. **Unknown roles** (e.g. a browser's `AXWebArea` / `AXGroup` when focus is on the page but not the chat box): paste only if the element exposes `AXSelectedTextRange` or a settable `AXValue`, otherwise show the card.
5. **No focused element reported:** paste if the app has a focused window (Finder: card).
6. **Accessibility not granted:** assume a target and paste.

Rule of thumb: when unsure, show the card, so a dictation is never lost silently. The text is also always saved in History.

If an app wrongly shows the card (Electron apps, terminals), check its focused role and add it to `textRoles`. If an app wrongly pastes into nothing, add its role to `nonTextRoles`.
