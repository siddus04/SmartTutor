#!/usr/bin/env bash
set -euo pipefail

PROJECT="SmartTutor.xcodeproj"
SCHEME="SmartTutor"
CONFIGURATION="Debug"
DERIVED_DATA=".derivedData"
UDID="B1101260-B56C-4187-A7C1-734BB5481E12"   # optionally pass SIM_UDID=... ./run-ios-sim.sh

die(){ echo "❌ $*" >&2; exit 1; }

open -a Simulator >/dev/null 2>&1 || true

# UDID is hardcoded above; keep this block only if you want auto-detect when UDID=""
if [[ -z "$UDID" ]]; then
  UDID="$(xcrun simctl list devices booted | awk -F '[()]' '/Booted/{print $2; exit}')"
fi
[[ -n "$UDID" ]] || die "UDID not set"

# Ensure simulator is booted and ready
echo "📱 Booting simulator (if needed): $UDID"
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b

DEST="platform=iOS Simulator,id=$UDID"


echo "🔨 Building..."
rm -rf "$DERIVED_DATA"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" -sdk iphonesimulator -destination "$DEST" -derivedDataPath "$DERIVED_DATA" build | sed 's/^/   /'

APP_PATH="$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphonesimulator/${SCHEME}.app"
[[ -d "$APP_PATH" ]] || die "App not found at $APP_PATH"

EXEC=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Info.plist")
[[ -f "$APP_PATH/$EXEC" ]] || die "Missing bundle executable: $APP_PATH/$EXEC"

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")

echo "📦 Installing..."
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP_PATH"

echo "🚀 Launching..."
xcrun simctl launch "$UDID" "$BUNDLE_ID" | sed 's/^/   /'

echo "✅ Done."
