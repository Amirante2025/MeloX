#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PREVIEW="$ROOT/build/preview"
DERIVED_DATA="$ROOT/build/DerivedData-Preview"
DEVICE_ID=""

cleanup() {
  if [[ -n "$DEVICE_ID" ]]; then
    xcrun simctl shutdown "$DEVICE_ID" || true
    xcrun simctl delete "$DEVICE_ID" || true
  fi
}
trap cleanup EXIT
mkdir -p "$PREVIEW"

xcodebuild build \
  -quiet \
  -project "$ROOT/MeloX.xcodeproj" \
  -scheme MeloX \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="$(uname -m)" \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  DEVELOPMENT_TEAM=""

RUNTIME_ID="$(xcrun simctl list runtimes --json | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"]
            if r.get("isAvailable") and ".iOS-" in r["identifier"]]
if not runtimes:
    sys.exit("No available iOS simulator runtime")
print(max(runtimes, key=lambda r: tuple(map(int, r["version"].split("."))))["identifier"])
')"
DEVICE_ID="$(xcrun simctl create 'Music Preview' \
  com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro "$RUNTIME_ID")"
xcrun simctl boot "$DEVICE_ID"
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl ui "$DEVICE_ID" appearance light
xcrun simctl status_bar "$DEVICE_ID" override \
  --time '9:41' --batteryState charged --batteryLevel 100 \
  --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/MeloX.app"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")"
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID" \
  -melox.hasCompletedOnboarding YES \
  -melox.localization.language simplifiedChinese \
  -appReleaseNotes.lastPresentedVersion 99.0.0 \
  -appRecommendation.hasPresentedPrompt YES \
  -checksUpdatesOnLaunch NO \
  -melox.contentFeatures.showsPrivateMessagesButton NO \
  -melox.contentFeatures.showsSongRecognitionButton NO
sleep 10
xcrun simctl io "$DEVICE_ID" screenshot "$PREVIEW/Music-home.png"
