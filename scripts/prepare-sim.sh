#!/usr/bin/env bash
set -euo pipefail

# UI tests drive the simulator through accessibility. On iOS 26 simulators the
# accessibility defaults are not enabled out of the box, so the XCTest runner
# never receives the "AX loaded" notification and fails to initialise with
# "Timed out waiting for AX loaded notification". Enable them and reboot once.
#
# Usage: scripts/prepare-sim.sh ["iPhone 17"]
NAME="${1:-iPhone 17}"

UDID="$(xcrun simctl list devices available | sed -n "s/^ *$NAME (\([0-9A-Fa-f-]\{36\}\)).*/\1/p" | head -1)"
if [ -z "$UDID" ]; then
  echo "no simulator named '$NAME'" >&2
  exit 1
fi

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

enabled="$(xcrun simctl spawn "$UDID" defaults read com.apple.Accessibility AccessibilityEnabled 2>/dev/null || echo 0)"
if [ "$enabled" = "1" ]; then
  echo "simulator already prepared: $NAME ($UDID)"
  exit 0
fi

xcrun simctl spawn "$UDID" defaults write com.apple.Accessibility AccessibilityEnabled -bool YES
xcrun simctl spawn "$UDID" defaults write com.apple.Accessibility ApplicationAccessibilityEnabled -bool YES
xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
sleep 1
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
echo "prepared simulator for UI tests: $NAME ($UDID)"
