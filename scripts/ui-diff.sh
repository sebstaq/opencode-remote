#!/usr/bin/env bash
set -euo pipefail

# Host-side orchestrator: build the app, screenshot the sidebar fixture on the VM,
# render the wireframe at the same geometry, and print SSIM + write the overlay.
#
# Usage: scripts/ui-diff.sh [--no-build]
# Env:   UI_DIFF_OUT (default /srv/devops/personal/output/opencode-ui-review)
LOCAL="${LOCAL_REPO:-/srv/devops/opencode-remote}"
OUT="${UI_DIFF_OUT:-/srv/devops/personal/output/opencode-ui-review}"
WORK="/tmp/opencode/ui-diff"
BUILD=1
[ "${1:-}" = "--no-build" ] && BUILD=0

source "$(dirname "$0")/lib/vm.sh"
mkdir -p "$WORK"
"$LOCAL/scripts/vm-sync.sh" >/dev/null

if [ "$BUILD" = 1 ]; then
  echo "== build =="
  doppler run --project conduit --config dev -- sh -lc "
    export SSHPASS=\"\$MACOS_SSH_PASSWORD\"
    $VM_SSH '
      cd ${VM_REPO}
      \"${VM_XCODEGEN}\" generate >/dev/null 2>&1 || true
      xcodebuild -project OpenCodeRemote.xcodeproj -scheme OpenCodeRemote \
        -destination \"platform=iOS Simulator,name=iPhone 16\" \
        -skipPackagePluginValidation build 2>&1 | tail -3'
  "
fi

echo "== screenshot + wireframe (on VM) =="
doppler run --project conduit --config dev -- sh -lc "
  export SSHPASS=\"\$MACOS_SSH_PASSWORD\"
  $VM_SCP ${LOCAL}/scripts/ui/shot-sidebar.sh ${LOCAL}/scripts/ui/render-wireframe.swift ${VM_SSH_USER}@${VM_SSH_HOST}:/tmp/
  $VM_SSH 'SIMULATOR_UDID=${SIMULATOR_UDID} XCODE_DERIVED=${XCODE_DERIVED} bash /tmp/shot-sidebar.sh'
  $VM_SSH 'cd ${VM_REPO} && swift /tmp/render-wireframe.swift docs/wireframes/index.html /tmp/sidebar_wire.png'
  $VM_SCP ${VM_SSH_USER}@${VM_SSH_HOST}:/tmp/sidebar_app.png ${WORK}/sidebar_app.png
  $VM_SCP ${VM_SSH_USER}@${VM_SSH_HOST}:/tmp/sidebar_wire.png ${WORK}/wire_sidebar.png
"

echo "== diff =="
python3 "$LOCAL/scripts/ui/ssim.py" "$WORK/wire_sidebar.png" "$WORK/sidebar_app.png" "$OUT"
