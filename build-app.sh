#!/bin/bash
# Builds GraphingApp and wraps it into a double-clickable macOS .app bundle.
# No Xcode required — uses Swift Package Manager + a hand-rolled bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

APP_NAME="GraphingApp"
DISPLAY_NAME="Graphing App"
CONFIG="${1:-release}"   # pass "debug" for a faster build

echo "▶ Building ($CONFIG)…"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="$ROOT/dist/$APP_NAME.app"

echo "▶ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>${DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key>          <string>${DISPLAY_NAME}</string>
    <key>CFBundleExecutable</key>           <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>           <string>com.maxgomez.graphingapp</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleShortVersionString</key>   <string>0.1.0</string>
    <key>CFBundleVersion</key>              <string>1</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key>       <string>14.0</string>
    <key>NSPrincipalClass</key>             <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>      <true/>
    <key>LSApplicationCategoryType</key>    <string>public.app-category.productivity</string>
</dict>
</plist>
PLIST

echo "▶ Ad-hoc code-signing…"
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"

echo "✓ Built: $APP"
