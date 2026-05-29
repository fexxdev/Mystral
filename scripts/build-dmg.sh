#!/usr/bin/env bash
set -euo pipefail

# Build a Release Mystral.app, ad-hoc sign it, and package it as a DMG.
# Usage: ./scripts/build-dmg.sh [output_dir]
#
# Requirements: Xcode command line tools, hdiutil (built-in), create-dmg optional.

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:-$PROJECT_ROOT/dist}"
BUILD_DIR="$PROJECT_ROOT/.build-dmg"
APP_NAME="Mystral"
SCHEME="Mystral"
CONFIG="Release"

mkdir -p "$OUTPUT_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_ROOT/Mystral/Info.plist" 2>/dev/null || echo "1.0.0")
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

echo "==> Building ${APP_NAME} (${CONFIG}) v${VERSION}"
xcodebuild \
    -project "$PROJECT_ROOT/${APP_NAME}.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR/dd" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    build | tail -3

APP_PATH="$BUILD_DIR/dd/Build/Products/${CONFIG}/${APP_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "Build did not produce an .app at: $APP_PATH"
    exit 1
fi

echo "==> Ad-hoc re-signing (recursive, deep)"
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

STAGING="$BUILD_DIR/staging"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

cat > "$STAGING/READ ME FIRST.txt" <<'EOF'
Mystral - Fan control for Apple Silicon Macs

Installing
----------
1. Drag Mystral.app into the Applications folder.
2. Eject this DMG.
3. The first time you launch Mystral:
     - Right-click Mystral.app in /Applications
     - Choose "Open"
     - Click "Open" in the Gatekeeper dialog
   This is needed because Mystral is not yet signed with a Developer ID.
4. The first time Mystral runs it asks for your password once to install a
   small background helper (a launchd daemon) that controls the fans. After
   that the helper starts automatically and stays running - you are never
   asked for your password again. No kernel extension is required.

Notes
-----
- This is open-source software shipped without an Apple Developer ID.
  You can verify the build yourself: https://github.com/fexxdev/Mystral
- The app stores profiles in ~/Library/Application Support/Mystral.
- Reset everything in Settings > Reset All Settings.
- The fan helper is a launchd daemon kept alive by macOS. To remove it
  completely (e.g. after deleting Mystral.app), run in Terminal:
      sudo launchctl bootout system/com.fexxdev.Mystral.helper
      sudo rm /Library/LaunchDaemons/com.fexxdev.Mystral.helper.plist
EOF

DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
rm -f "$DMG_PATH"

echo "==> Creating DMG at $DMG_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"

codesign --force --sign - "$DMG_PATH" || true

rm -rf "$BUILD_DIR"

echo
echo "==> Done"
echo "DMG:  $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
echo
echo "Tell users: right-click → Open the first time to bypass Gatekeeper."
