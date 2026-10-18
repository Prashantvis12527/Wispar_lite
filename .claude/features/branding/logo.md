# Logo and icons

- **Design:** a sky-to-indigo rounded square with five white sound-wave bars that thin out and fade to the right, plus a few floating specks. It is meant to suggest lightness: sound dissolving into air.
- **Source:** `Assets/make_icon.swift` draws everything with CoreGraphics (no image tools needed). Run `swift Assets/make_icon.swift Assets` to regenerate `icon_1024.png`, `menubar.png` and `menubar@2x.png`, then `./build.sh`.
- **App icon:** `build.sh` resizes `icon_1024.png` with `sips`, builds `AppIcon.icns` with `iconutil` into `Contents/Resources`, and `Info.plist` points to it via `CFBundleIconFile`.
- **Menu bar:** idle state shows the bundled `menubar.png` (template image, adapts to light/dark). Recording (`mic.fill`) and processing (`ellipsis.circle`) still use SF Symbols as state feedback. See `setIcon` in `main.swift`.
