#!/usr/bin/env bash
set -euo pipefail

# Programmatic color fidelity check: builds the app on w3, captures light+dark
# simulator screenshots on w1 against the seeded "Theme tokens" session on the
# rig server (port 4098 on the host), and reports CIEDE2000 per semantic
# element against the reference tokens measured from the reference screenshots
# (see scripts/ui/theme_colors.py REFERENCE).
#
# Usage: scripts/theme-diff.sh [--no-build]
# Exits non-zero if any element fails.

LOCAL="${LOCAL_REPO:-/srv/devops/opencode-remote}"
WORK="/tmp/opencode/theme-diff"
BUILD=1
[ "${1:-}" = "--no-build" ] && BUILD=0

cd "$LOCAL"
mkdir -p "$WORK"
./scripts/vm-sync.sh >/dev/null

if [ "$BUILD" = 1 ]; then
  echo "== build (w3) =="
  doppler run --project conduit --config dev -- sh -lc 'export SSHPASS="$MACOS_SSH_PASSWORD"; sshpass -e ssh -o StrictHostKeyChecking=no -p 2222 w3@localhost "
    export DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer
    cd /Users/w3/opencode-remote
    /Users/w3/tools/xcodegen/xcodegen/bin/xcodegen generate >/dev/null 2>&1 || true
    xcodebuild -project OpenCodeRemote.xcodeproj -scheme OpenCodeRemote \
      -destination \"platform=iOS Simulator,name=iPhone 17,OS=26.2\" \
      -skipPackagePluginValidation -derivedDataPath /tmp/dd-theme build 2>&1 | grep -E \"error:\" | head -5
    rm -rf /tmp/ocapp-theme && mkdir -p /tmp/ocapp-theme
    cp -R /tmp/dd-theme/Build/Products/Debug-iphonesimulator/OpenCodeRemote.app /tmp/ocapp-theme/
    echo THEME_BUILD_OK"'
fi

echo "== ship app to w1 + capture =="
doppler run --project conduit --config dev -- sh -lc 'export SSHPASS="$MACOS_SSH_PASSWORD"; rm -rf /tmp/theme-diff-app; mkdir -p /tmp/theme-diff-app; sshpass -e scp -q -o StrictHostKeyChecking=no -P 2222 -r "w3@localhost:/tmp/ocapp/OpenCodeRemote.app" /tmp/theme-diff-app/ && sshpass -e ssh -o StrictHostKeyChecking=no -p 2222 w1@localhost "rm -rf /tmp/ocapp-theme && mkdir -p /tmp/ocapp-theme" && sshpass -e scp -q -o StrictHostKeyChecking=no -P 2222 -r /tmp/theme-diff-app/OpenCodeRemote.app w1@localhost:/tmp/ocapp-theme/ && sshpass -e scp -q -o StrictHostKeyChecking=no -P 2222 scripts/ui/theme-capture.sh scripts/ui/find-row.py w1@localhost:/tmp/ && sshpass -e ssh -o StrictHostKeyChecking=no -p 2222 w1@localhost "bash /tmp/theme-capture.sh 2>&1 | tail -1"'
doppler run --project conduit --config dev -- sh -lc 'export SSHPASS="$MACOS_SSH_PASSWORD"; sshpass -e scp -q -o StrictHostKeyChecking=no -P 2222 "w1@localhost:/tmp/shots/theme-1-light.png" "w1@localhost:/tmp/shots/theme-2-dark.png" /tmp/opencode/theme-diff/'

echo "== measure =="
python3 scripts/ui/theme_colors.py "$WORK/theme-1-light.png" "$WORK/theme-2-dark.png"
