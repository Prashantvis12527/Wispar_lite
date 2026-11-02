# Floating pill (`Overlay.swift`)

Read this for anything about the small pill on the screen edge: its look, size, animation, position, or the "Floating icon" toggle.

- A small non-activating, click-through `NSPanel` attached to a screen edge. Idle: thin, dim, partly tucked off the edge. Listening: pops out, grows, and nine thin bars glow with the live mic level (`Recorder.onLevel`, RMS scaled to 0...1). Processing: bars ripple. A 30 fps timer runs only while not idle, so idle cost stays about zero.
- **Hover and click:** the panel takes mouse events (it never becomes key, so the focused app keeps focus). Hovering pops the idle pill out (smooth ease-out, no bounce) and shows a still waveform (`hovering` / `PillView.hover`); after 0.35 s a small hint appears beside it ("Click to dictate" / "Click to stop and paste"). Hover ends only when the cursor leaves `hoverZone` (small and big pill together, stretched to the screen edge), polled by `hoverWatch`; this stops the pop-in/pop-out flicker when the cursor sits at the very screen edge, where the panel changes size under it. Clicking it starts a dictation (like a hotkey double-tap lock); clicking again stops and pastes. Clicks are ignored while processing. Wired via `Overlay.onClick` -> `pillClicked()` in `main.swift`.
- **Position:** menu bar -> "Icon position" (Bottom default, Top, Left, Right), saved in `UserDefaults` key `iconPosition`. Top/bottom is a horizontal pill, left/right a vertical one. Sizes are the `idleLong/idleShort/activeLong/activeShort` constants.
- **Floating icon:** toggles the always-visible idle pill (`floatingIcon`); it still appears while recording.
- `setIcon` in `main.swift` drives the pill mode (`mic.fill` listening, `ellipsis.circle` processing, `mic` idle).
- The same settings are editable in the dashboard Settings tab (see `../dashboard/settings.md`).
