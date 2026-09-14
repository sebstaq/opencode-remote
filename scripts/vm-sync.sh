#!/usr/bin/env bash
set -euo pipefail

LOCAL="${LOCAL_REPO:-/srv/devops/opencode-remote}"
source "$(dirname "$0")/lib/vm.sh"

doppler run --project conduit --config dev -- sh -lc "
  export SSHPASS=\"\$MACOS_SSH_PASSWORD\"
  rsync -az --delete \
    --exclude '.build' \
    --exclude '.swiftpm' \
    --exclude 'DerivedData' \
    --exclude '*.xcodeproj' \
    --exclude 'App/Info.plist' \
    -e '${VM_RSYNC_SSH}' \
    '${LOCAL}/' '${VM_SSH_USER}@${VM_SSH_HOST}:${VM_REPO}/'
"
