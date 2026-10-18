# Floating pill (`Overlay.swift`)

Read this for anything about the small pill on the screen edge: its look, size, animation, position, or the "Floating icon" toggle.

- A small non-activating, click-through `NSPanel` attached to a screen edge. Idle: thin, dim, partly tucked off the edge. Listening: pops out, grows, and nine thin bars glow with the live mic level (`Recorder.onLevel`, RMS scaled to 0...1). Processing: bars ripple. A 30 fps timer runs only while not idle, so idle cost stays about zero.
- **Position:** menu bar -> "Icon position" (Bottom default, Top, Left, Right), saved in `UserDefaults` key `iconPosition`. Top/bottom is a horizontal pill, left/right a vertical one. Sizes are the `idleLong/idleShort/activeLong/activeShort` constants.
- **Floating icon:** toggles the always-visible idle pill (`floatingIcon`); it still appears while recording.
- `setIcon` in `main.swift` drives the pill mode (`mic.fill` listening, `ellipsis.circle` processing, `mic` idle).
- The same settings are editable in the dashboard Settings tab (see `../dashboard/settings.md`).
