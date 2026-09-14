#!/usr/bin/env bash
set -uo pipefail

read -r PW

UDID="${SIMULATOR_UDID:?set SIMULATOR_UDID}"
BID="${BUNDLE_ID:-dev.sebstaq.opencode.OpenCodeRemote}"
XCODE_DERIVED="${XCODE_DERIVED:?set XCODE_DERIVED}"
URL="${MEASURE_URL:?set MEASURE_URL}"
SCENARIO="${SCENARIO:-connect}"
RUNS="${RUNS:-20}"
SECONDS_WINDOW="${SECONDS_WINDOW:-0}"
SLEEP="${SLEEP:-25}"

APP=$(find "$XCODE_DERIVED/Build/Products" -name "OpenCodeRemote.app" -path "*iphonesimulator*" | head -1)
xcrun simctl terminate "$UDID" "$BID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP"

SIMCTL_CHILD_OPENCODE_MEASURE_URL="$URL" \
SIMCTL_CHILD_OPENCODE_MEASURE_PASSWORD="$PW" \
SIMCTL_CHILD_OPENCODE_MEASURE_RUNS="$RUNS" \
SIMCTL_CHILD_OPENCODE_MEASURE_SCENARIO="$SCENARIO" \
SIMCTL_CHILD_OPENCODE_MEASURE_SECONDS="$SECONDS_WINDOW" \
  xcrun simctl launch "$UDID" "$BID" >/dev/null

if [[ "${LAUNCH_ONLY:-0}" == "1" ]]; then
  echo "launched"
  exit 0
fi

sleep "$SLEEP"
CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BID" data 2>/dev/null)
cp "$CONTAINER/Documents/measure-report.json" /tmp/measure-report.json 2>/dev/null
echo "report=/tmp/measure-report.json"
