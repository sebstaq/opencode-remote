#!/usr/bin/env bash
set -euo pipefail

# Runs on the macOS VM. Screenshots the sidebar rendered with the wireframe fixture.
SIMULATOR_UDID="${SIMULATOR_UDID:-6424C025-2006-4270-8C5B-619E4D74085F}"
XCODE_DERIVED="${XCODE_DERIVED:-/Users/w3/Library/Developer/Xcode/DerivedData/OpenCodeRemote-fkgcsynjxhpjokewsyypoxdmpmqe}"
BUNDLE_ID="${BUNDLE_ID:-dev.sebstaq.opencode.OpenCodeRemote}"
OUT="${OUT:-/tmp/sidebar_app.png}"
APP="${XCODE_DERIVED}/Build/Products/Debug-iphonesimulator/OpenCodeRemote.app"

xcrun simctl boot "$SIMULATOR_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_UDID" -b >/dev/null
xcrun simctl status_bar "$SIMULATOR_UDID" override \
  --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 || true
xcrun simctl install "$SIMULATOR_UDID" "$APP"
xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" 2>/dev/null || true
SIMCTL_CHILD_OPENCODE_UI_FIXTURE=wireframe xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null
sleep 3
xcrun simctl io "$SIMULATOR_UDID" screenshot "$OUT" >/dev/null
echo "$OUT"
