#!/bin/bash
# Wrap the noribar SwiftPM executable into a minimal .app bundle.
#
# Why this is required (Spike A finding, carried into the product): the SF Symbol
# animation engine (RenderBox) crashes when driven from a bare executable that has no
# CFBundleIdentifier — it needs a real bundle. `swift run noribar` is fine for the
# --selftest (which only exercises the *pure* animation planner, not the live engine), but
# to see real on-screen symbol effects you MUST run the bundled app produced here.
#
# Usage:  ./bundle.sh [debug|release]   then   open noribar.app   (or ./bundle.sh && open noribar.app)
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
BIN=".build/${CONFIG}/noribar"
APP="noribar.app"

swift build -c "$CONFIG" >/dev/null

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/noribar"
# Bundle the sample configs so the app is self-contained (resolveConfig checks Resources).
cp config.lua "$APP/Contents/Resources/config.lua"
cp config-stress.lua "$APP/Contents/Resources/config-stress.lua"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>         <string>noribar</string>
    <key>CFBundleIdentifier</key>         <string>org.norikit.noribar</string>
    <key>CFBundleName</key>               <string>noribar</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.0</string>
    <key>LSMinimumSystemVersion</key>     <string>13.0</string>
    <!-- Accessory app: no Dock icon, not in Cmd-Tab. -->
    <key>LSUIElement</key>                <true/>
    <key>NSHighResolutionCapable</key>    <true/>
</dict>
</plist>
PLIST

# Ad-hoc codesign so TCC has a stable identity to remember (no notarization in M1 — Q8).
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built $APP — run:  open $APP   (or for the D6 stress run:  $APP/Contents/MacOS/noribar --stress)"
