#!/bin/bash
# Builds Pulse.app (Release) and packages it into a .dmg for dragging into
# /Applications, without needing to go through Xcode's Organizer UI.
#
# Usage:
#   ./build_dmg.sh                 # use whichever Team is already set in Xcode
#   ./build_dmg.sh ABCDE12345      # override with a specific Team ID
#
# Requires full Xcode (not just the Command Line Tools) - this builds a
# macOS app + WidgetKit extension, which needs the macOS SDK bundled with
# Xcode.app itself.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Pulse"
SCHEME="Pulse"
PROJECT="Pulse.xcodeproj"
BUILD_DIR="build"
DIST_DIR="dist"
TEAM_ID="${1:-}"

if ! xcodebuild -version >/dev/null 2>&1; then
    echo "error: xcodebuild isn't usable. Install Xcode from the App Store" >&2
    echo "       (Command Line Tools alone can't build a macOS app + widget extension)," >&2
    echo "       then run: sudo xcode-select -s /Applications/Xcode.app" >&2
    exit 1
fi

echo "== Cleaning previous build/dist output =="
rm -rf "$BUILD_DIR" "$DIST_DIR"

echo "== Building $APP_NAME (Release) =="
xcodebuild_args=(
    -project "$PROJECT"
    -scheme "$SCHEME"
    -configuration Release
    -derivedDataPath "$BUILD_DIR"
    -allowProvisioningUpdates
    CODE_SIGN_STYLE=Automatic
    clean build
)
if [ -n "$TEAM_ID" ]; then
    xcodebuild_args+=(DEVELOPMENT_TEAM="$TEAM_ID")
fi
xcodebuild "${xcodebuild_args[@]}"

APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "error: build succeeded but $APP_PATH is missing - check the log above." >&2
    exit 1
fi

echo "== Staging DMG contents =="
mkdir -p "$DIST_DIR/dmg-src"
cp -R "$APP_PATH" "$DIST_DIR/dmg-src/"

DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
rm -f "$DMG_PATH"

if command -v create-dmg >/dev/null 2>&1; then
    echo "== Creating DMG with create-dmg =="
    create-dmg \
        --volname "$APP_NAME" \
        --window-size 500 320 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 120 150 \
        --app-drop-link 380 150 \
        "$DMG_PATH" \
        "$DIST_DIR/dmg-src" || true
fi

if [ ! -f "$DMG_PATH" ]; then
    echo "== Creating DMG with hdiutil =="
    ln -sf /Applications "$DIST_DIR/dmg-src/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$DIST_DIR/dmg-src" -ov -format UDZO "$DMG_PATH"
fi

rm -rf "$DIST_DIR/dmg-src"

echo ""
echo "Done: $DIST_DIR/$APP_NAME.dmg"
echo "Mount it, drag Pulse.app to Applications, then launch it from there."
