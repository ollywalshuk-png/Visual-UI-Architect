#!/bin/bash
# Builds Visual UI Architect and wraps the release binary into a runnable
# macOS .app bundle — no Xcode required, just the Swift toolchain.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Visual UI Architect"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "▶ Building release…"
swift build --package-path "$ROOT" -c release --product VisualUIArchitect

BIN="$ROOT/.build/release/VisualUIArchitect"
[ -f "$BIN" ] || { echo "✗ Binary not found at $BIN"; exit 1; }

echo "▶ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/VisualUIArchitect"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Visual UI Architect</string>
    <key>CFBundleDisplayName</key><string>Visual UI Architect</string>
    <key>CFBundleIdentifier</key><string>com.visualuiarchitect.app</string>
    <key>CFBundleVersion</key><string>0.1.0</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>VisualUIArchitect</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "✓ Built: $APP"
echo "  Run with: open \"$APP\""
