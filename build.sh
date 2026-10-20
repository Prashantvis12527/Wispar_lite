#!/bin/bash
# Builds WisprLite.app (menu-bar agent) next to this script.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=WisprLite.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/WisprLite "$APP/Contents/MacOS/WisprLite"
# Logo: Assets/make_icon.swift draws it; build the .icns and menu-bar glyph into the bundle.
mkdir -p "$APP/Contents/Resources"
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz Assets/icon_1024.png --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz*2)) $((sz*2)) Assets/icon_1024.png --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp Assets/menubar@2x.png "$APP/Contents/Resources/menubar.png"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.prashant.wisprlite</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>WisprLite</string>
<key>CFBundleExecutable</key><string>WisprLite</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSMicrophoneUsageDescription</key><string>WisprLite records your voice while you hold the hotkey.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>WisprLite transcribes your voice on this Mac using Apple's on-device speech recognition. Audio is never sent to a server.</string>
</dict></plist>
PLIST
# A stable identity keeps macOS permissions (mic, accessibility) across rebuilds and restarts.
# Falls back to ad-hoc signing if the "WisprLite Local" certificate is missing.
ID=$(security find-identity -p codesigning | awk '/"WisprLite Local"/ {print $2; exit}')
codesign --force --sign "${ID:--}" "$APP"
echo "Built $APP"
