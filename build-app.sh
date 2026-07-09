#!/bin/bash
# Builds Vigie.app from the SwiftPM executable and installs it into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Vigie.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp .build/release/Vigie "$APP/Contents/MacOS/Vigie"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Vigie</string>
    <key>CFBundleIdentifier</key><string>app.vigie.menubar</string>
    <key>CFBundleName</key><string>Vigie</string>
    <key>CFBundleDisplayName</key><string>Vigie</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

mkdir -p ~/Applications
rm -rf ~/Applications/Vigie.app
cp -R "$APP" ~/Applications/Vigie.app

echo "✓ Vigie installée : ~/Applications/Vigie.app"
