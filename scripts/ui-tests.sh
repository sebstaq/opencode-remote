#!/usr/bin/env bash
set -uo pipefail

# Runs XCUITest with the reliability steps this environment needs:
#   - only one simulator booted (a second one makes the AX handshake flaky)
#   - accessibility enabled in the simulator (see prepare-sim.sh)
#   - retry when the runner fails to initialise ("AX loaded notification")
#
# Usage: scripts/ui-tests.sh ["iPhone 17"] [-only-testing:...]
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:-iPhone 17}"
shift || true

UDID="$(xcrun simctl list devices available | sed -n "s/^ *$NAME (\([0-9A-Fa-f-]\{36\}\)).*/\1/p" | head -1)"
if [ -z "$UDID" ]; then
  echo "no simulator named '$NAME'" >&2
  exit 1
fi

for other in $(xcrun simctl list devices booted | sed -n 's/.*(\([0-9A-Fa-f-]\{36\}\)).*/\1/p'); do
  if [ "$other" != "$UDID" ]; then
    xcrun simctl shutdown "$other" >/dev/null 2>&1 || true
  fi
done

cd "$ROOT"
source "$ROOT/scripts/lib/env.sh"
export OPENCODE_E2E_URL="${OPENCODE_E2E_URL:-}"
export OPENCODE_E2E_PASSWORD="${OPENCODE_E2E_PASSWORD:-}"
if [[ -z "$OPENCODE_E2E_URL" ]]; then
  echo "note: OPENCODE_E2E_URL is not set; live-server tests will be skipped (.env, see .env.example)"
fi

for attempt in 1 2 3; do
  echo "== UI tests, attempt $attempt ($NAME) =="
  "$ROOT/scripts/prepare-sim.sh" "$NAME" >/dev/null 2>&1 || true

  output="$(xcodebuild test -project OpenCodeRemote.xcodeproj -scheme OpenCodeRemote \
    -destination "platform=iOS Simulator,id=$UDID" -skipPackagePluginValidation "$@" 2>&1)"

  if grep -q "TEST SUCCEEDED" <<<"$output"; then
    echo "UI tests passed"
    exit 0
  fi

  if grep -q "Failed to initialize for UI testing" <<<"$output"; then
    echo "runner failed to initialise (AX); rebooting simulator and retrying"
    xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
    sleep 3
    xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
    xcrun simctl spawn "$UDID" defaults write com.apple.Accessibility AccessibilityEnabled -bool YES >/dev/null 2>&1 || true
    xcrun simctl spawn "$UDID" defaults write com.apple.Accessibility ApplicationAccessibilityEnabled -bool YES >/dev/null 2>&1 || true
    continue
  fi

  grep -E "Test Case .*(passed|failed)|error:|TEST (SUCCEEDED|FAILED)" <<<"$output" | tail -25
  exit 1
done

echo "UI tests failed after retries (AX)" >&2
exit 1
