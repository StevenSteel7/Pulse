#!/bin/bash
# Rebuilds Pulse + PulseWidget from scratch after a code change, wiping every
# stale cache that has previously caused WidgetKit to keep showing an old
# build, then launches the fresh app and verifies everything lines up.
#
# What it does, in order:
#   1. Quits any running Pulse / PulseWidget processes.
#   2. Moves stale caches to ~/.Trash (recoverable, nothing is deleted):
#        - old Xcode DerivedData for this project
#        - the shared snapshot.json (app-side + legacy Application Support)
#        - the app's and widget's HTTP/URL caches
#      settings.json (your server config) is always left in place.
#   3. Bumps CURRENT_PROJECT_VERSION in project.yml by 1 and regenerates
#      Pulse.xcodeproj with xcodegen, so the app and widget both report a
#      newer build number than whatever WidgetKit last cached.
#   4. Runs `xcodebuild clean build` for the Pulse scheme (app + widget
#      extension embedded, signed).
#   5. Registers the fresh app with Launch Services and launches it, which
#      also kicks the widget onto the new build (PulseMonitor's first poll
#      calls WidgetCenter.reloadTimelines within ~5s of launch).
#   6. Verifies: build number, code signature, and that exactly one Pulse
#      process is running (no duplicate cache writers).
#
# Usage:
#   ./refresh_build.sh                 # Debug build (matches day-to-day dev)
#   ./refresh_build.sh "" Release      # Release build
#   ./refresh_build.sh ABCDE12345      # override Team ID
#   ./refresh_build.sh ABCDE12345 Release
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Pulse"
WIDGET_PROC_NAME="PulseWidget"
SCHEME="Pulse"
PROJECT_YML="project.yml"
PROJECT="Pulse.xcodeproj"
BUILD_DIR="build"
TEAM_ID_OVERRIDE="${1:-}"
CONFIGURATION="${2:-Debug}"
BUNDLE_ID_APP="com.stevensteel.pulse"
BUNDLE_ID_WIDGET="com.stevensteel.pulse.widget"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

if ! xcodebuild -version >/dev/null 2>&1; then
    echo "error: xcodebuild isn't usable. Install Xcode from the App Store" >&2
    echo "       then run: sudo xcode-select -s /Applications/Xcode.app" >&2
    exit 1
fi
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: xcodegen not found. Install with: brew install xcodegen" >&2
    exit 1
fi

TEAM_ID="$TEAM_ID_OVERRIDE"
if [ -z "$TEAM_ID" ]; then
    TEAM_ID=$(grep -m1 "DEVELOPMENT_TEAM:" "$PROJECT_YML" | awk '{print $2}')
fi

echo "== Quitting running Pulse / PulseWidget processes =="
killall "$APP_NAME" >/dev/null 2>&1 || true
pkill -f "$WIDGET_PROC_NAME.appex" >/dev/null 2>&1 || true
sleep 1

echo "== Moving stale caches to Trash (settings.json is preserved) =="
TRASH_DIR="$HOME/.Trash/Pulse-cache-cleanup.$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 6)"
mkdir -p "$TRASH_DIR"

move_to_trash() {
    local src="$1"
    if [ -e "$src" ]; then
        mkdir -p "$TRASH_DIR/$(dirname "${src#$HOME/}")"
        mv "$src" "$TRASH_DIR/${src#$HOME/}" 2>/dev/null || mv "$src" "$TRASH_DIR/"
        echo "   moved: $src"
    fi
}

# Stale DerivedData from Xcode GUI builds of this project.
for d in "$HOME/Library/Developer/Xcode/DerivedData/Pulse-"*; do
    move_to_trash "$d"
done

# Shared snapshot (current + legacy location) - settings.json stays put.
APP_GROUP_DIR="$HOME/Library/Group Containers/${TEAM_ID}.${BUNDLE_ID_APP}"
move_to_trash "$APP_GROUP_DIR/snapshot.json"
move_to_trash "$HOME/Library/Application Support/Pulse/snapshot.json"

# App + widget HTTP/URL caches.
move_to_trash "$HOME/Library/Caches/$BUNDLE_ID_APP"
move_to_trash "$HOME/Library/Caches/$BUNDLE_ID_WIDGET"
move_to_trash "$HOME/Library/HTTPStorages/$BUNDLE_ID_APP"
move_to_trash "$HOME/Library/HTTPStorages/$BUNDLE_ID_WIDGET"

echo "   recoverable at: $TRASH_DIR"

echo "== Bumping build number =="
CURRENT_BUILD=$(grep -m1 "CURRENT_PROJECT_VERSION:" "$PROJECT_YML" | sed -E 's/.*"([0-9]+)".*/\1/')
NEW_BUILD=$((CURRENT_BUILD + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION: \"$CURRENT_BUILD\"/CURRENT_PROJECT_VERSION: \"$NEW_BUILD\"/" "$PROJECT_YML"
echo "   $CURRENT_BUILD -> $NEW_BUILD"

echo "== Regenerating $PROJECT with xcodegen =="
xcodegen generate

echo "== Clean signed build ($CONFIGURATION) =="
rm -rf "$BUILD_DIR"
xcodebuild_args=(
    -project "$PROJECT"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -derivedDataPath "$BUILD_DIR"
    -allowProvisioningUpdates
    CODE_SIGN_STYLE=Automatic
    clean build
)
if [ -n "$TEAM_ID" ]; then
    xcodebuild_args+=(DEVELOPMENT_TEAM="$TEAM_ID")
fi
xcodebuild "${xcodebuild_args[@]}"

APP_PATH="$BUILD_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "error: build succeeded but $APP_PATH is missing - check the log above." >&2
    exit 1
fi

echo "== Registering and launching $APP_NAME.app =="
"$LSREGISTER" -f "$APP_PATH"
open "$APP_PATH"
sleep 2

echo ""
echo "== Verifying =="
APP_BUILD=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleVersion)
WIDGET_APPEX="$APP_PATH/Contents/PlugIns/$WIDGET_PROC_NAME.appex"
WIDGET_BUILD=$(defaults read "$WIDGET_APPEX/Contents/Info.plist" CFBundleVersion)
echo "App build number:    $APP_BUILD"
echo "Widget build number: $WIDGET_BUILD"

if codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
    echo "Code signature:      valid"
else
    echo "Code signature:      INVALID - check codesign output" >&2
fi

APP_PROC_COUNT=$(pgrep -x "$APP_NAME" | wc -l | tr -d ' ')
echo "Running $APP_NAME processes: $APP_PROC_COUNT"
if [ "$APP_PROC_COUNT" != "1" ]; then
    echo "warning: expected exactly 1 running process, found $APP_PROC_COUNT" >&2
fi

if pgrep -f "$WIDGET_PROC_NAME.appex" >/dev/null 2>&1; then
    echo "Widget extension:    running"
else
    echo "Widget extension:    not running yet (WidgetKit starts it on demand - open the widget or wait a few seconds)"
fi

echo ""
echo "Done. Pulse.app relaunched from: $APP_PATH"
echo "The running app polls SIXDX every 5s and nudges WidgetCenter.reloadTimelines"
echo "on each successful poll, so both widget layouts pick up the new build within"
echo "a few seconds without any manual action."
