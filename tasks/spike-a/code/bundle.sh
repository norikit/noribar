#!/bin/bash
# Wrap the SwiftPM executable into a minimal .app bundle.
# Finding from the spike: the SF Symbol animation engine (RenderBox) crashes when run
# from a bare executable with no CFBundleIdentifier — it needs a real bundle.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-debug}"
BIN=".build/${CONFIG}/SpikeA"
APP="SpikeA.app"

swift build -c "$CONFIG" >/dev/null

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/SpikeA"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>      <string>SpikeA</string>
    <key>CFBundleIdentifier</key>      <string>org.norikit.noribar.spike-a</string>
    <key>CFBundleName</key>            <string>SpikeA</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.0</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <!-- Accessory app: no Dock icon, not in Cmd-Tab. -->
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

# Ad-hoc codesign so TCC (Screen Recording etc.) has a stable identity to remember.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built $APP"
