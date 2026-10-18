#!/bin/bash
# Builds WisprLite.app (menu-bar agent) next to this script.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=WisprLite.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/WisprLite "$APP/Contents/MacOS/WisprLite"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.prashant.wisprlite</string>
<key>CFBundleName</key><string>WisprLite</string>
<key>CFBundleExecutable</key><string>WisprLite</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSMicrophoneUsageDescription</key><string>WisprLite records your voice while you hold the hotkey.</string>
</dict></plist>
PLIST
# A stable identity keeps macOS permissions (mic, accessibility) across rebuilds and restarts.
# Falls back to ad-hoc signing if the "WisprLite Local" certificate is missing.
ID=$(security find-identity -p codesigning | awk '/"WisprLite Local"/ {print $2; exit}')
codesign --force --sign "${ID:--}" "$APP"
echo "Built $APP"
