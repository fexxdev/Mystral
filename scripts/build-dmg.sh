#!/usr/bin/env bash
set -euo pipefail

# Build a Release Mystral.app and package it as a DMG.
# Usage: ./scripts/build-dmg.sh [output_dir]
# Set MYSTRAL_SIGNING_IDENTITY to a Developer ID identity for a distributable release.
#
# Requirements: Xcode command line tools, hdiutil (built-in), create-dmg optional.

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:-$PROJECT_ROOT/dist}"
BUILD_DIR="$PROJECT_ROOT/.build-dmg"
APP_NAME="Mystral"
SCHEME="Mystral"
CONFIG="Release"
SIGNING_IDENTITY="${MYSTRAL_SIGNING_IDENTITY:--}"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    SIGNING_MODE="ad-hoc"
    GATEKEEPER_NOTE="Ad-hoc builds need a right-click on Mystral.app, then Open, on first launch."
    RELEASE_NOTE="This build is ad-hoc signed. Use a Developer ID identity for release distribution."
else
    SIGNING_MODE="Developer ID"
    GATEKEEPER_NOTE="This build is signed with ${SIGNING_IDENTITY}."
    RELEASE_NOTE="This build is signed with ${SIGNING_IDENTITY}. Notarize it before broad distribution."
fi

mkdir -p "$OUTPUT_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_ROOT/Mystral/Info.plist" 2>/dev/null || echo "1.0.0")
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
REINSTALL_NOTE=""
if [[ "$VERSION" == "1.1.4" ]]; then
    REINSTALL_NOTE="IMPORTANT — MANUAL REINSTALL REQUIRED
This release must be installed manually. Replace the existing Mystral.app in /Applications before using the in-app updater again."
fi

echo "==> Building ${APP_NAME} (${CONFIG}) v${VERSION}"
echo "==> Signing mode: ${SIGNING_MODE}"
xcodebuild \
    -project "$PROJECT_ROOT/${APP_NAME}.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR/dd" \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    build | tail -3

APP_PATH="$BUILD_DIR/dd/Build/Products/${CONFIG}/${APP_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "Build did not produce an .app at: $APP_PATH"
    exit 1
fi

BUNDLE_TYPE=$(/usr/libexec/PlistBuddy -c "Print :CFBundlePackageType" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)
if [[ "$BUNDLE_TYPE" != "APPL" ]]; then
    echo "Built app has invalid CFBundlePackageType: ${BUNDLE_TYPE:-missing}"
    exit 1
fi

echo "==> Signing app (${SIGNING_MODE})"
codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

STAGING="$BUILD_DIR/staging"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

cat > "$STAGING/READ ME FIRST.txt" <<EOF
Mystral - Fan control for Apple Silicon Macs

${REINSTALL_NOTE}

Installing
----------
1. Drag Mystral.app into the Applications folder.
2. Eject this DMG.
3. The first time you launch Mystral:
     - ${GATEKEEPER_NOTE}
4. The first time Mystral runs it asks for your password to install a
   root-owned background helper (a launchd daemon) that controls the fans.
   It asks again only when the helper build changes. No kernel extension is
   required.

Notes
-----
- ${RELEASE_NOTE}
  You can verify the source and release process: https://github.com/fexxdev/Mystral
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

echo "==> Signing DMG (${SIGNING_MODE})"
codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"
codesign --verify --strict --verbose=2 "$DMG_PATH"

rm -rf "$BUILD_DIR"

echo
echo "==> Done"
echo "DMG:  $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
echo
echo "$GATEKEEPER_NOTE"
