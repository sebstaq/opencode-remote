#!/usr/bin/env bash
set -uo pipefail

# Runs the live permission E2E (PermissionLiveE2ETests) on the VM's booted
# simulator. Needs `.env` with OPENCODE_E2E_URL / OPENCODE_E2E_PASSWORD (see
# .env.example) and a prepared simulator (scripts/prepare-sim.sh).
#
# Set OPENCODE_PERMISSION_SHOTS=0 to skip screenshots (on by default here).

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/lib/env.sh"

if [[ -z "${OPENCODE_E2E_URL:-}" ]]; then
  echo "OPENCODE_E2E_URL is not set (.env)" >&2
  exit 2
fi

UDID="$(xcrun simctl list devices booted | sed -n 's/.*(\([0-9A-Fa-f-]\{36\}\)).*/\1/p' | head -1)"
if [[ -z "$UDID" ]]; then
  echo "no booted simulator" >&2
  exit 2
fi
echo "using simulator $UDID"

# project.yml owns the scheme's test environment; regenerate so env mappings
# added there are picked up.
XCODEGEN="${XCODEGEN:-/Users/w3/tools/xcodegen/xcodegen/bin/xcodegen}"
if [[ -x "$XCODEGEN" ]]; then
  "$XCODEGEN" generate >/dev/null
fi

export OPENCODE_PERMISSION_SHOTS="${OPENCODE_PERMISSION_SHOTS:-1}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-26.3.0.app/Contents/Developer}"

xcodebuild test \
  -project OpenCodeRemote.xcodeproj \
  -scheme OpenCodeRemote \
  -destination "id=$UDID" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  -only-testing:OpenCodeRemoteUITests/PermissionLiveE2ETests
