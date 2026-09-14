#!/usr/bin/env bash
set -euo pipefail

# Build a signed IPA on the VM and upload it to Diawi, printing the install link.
#
# Signing uses the App Store Connect API key stored in Doppler project
# `opencode-remote` (ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY). This script
# installs it on the VM and runs the build with -allowProvisioningUpdates plus
# -authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID, which
# is Apple's supported headless automatic-signing path (no Apple ID account).
#
# Usage: scripts/diawi.sh
LOCAL="${LOCAL_REPO:-/srv/devops/opencode-remote}"
WORK="/tmp/opencode/diawi"
CONFIG="${CONFIG:-Debug}"

source "$(dirname "$0")/lib/vm.sh"
source "$(dirname "$0")/lib/env.sh"
mkdir -p "$WORK"
"$LOCAL/scripts/vm-sync.sh" >/dev/null

doppler run --project conduit --config dev -- sh -lc "
  export SSHPASS=\"\$MACOS_SSH_PASSWORD\"
  $VM_SSH 'bash ${VM_SCRIPT_DIR}/base-sync.sh' >/dev/null
"

echo "== install ASC credentials on the VM =="
tmp="$(mktemp -d)"
chmod 700 "$tmp"
doppler secrets download --project opencode-remote --config dev --no-file --format json >"$tmp/asc.json"
python3 - "$tmp/asc.json" "$tmp" <<'PY'
import json, pathlib, sys
data = json.load(open(sys.argv[1]))
out = pathlib.Path(sys.argv[2])
key_id = data["ASC_KEY_ID"]
(out / "key-id").write_text(key_id + "\n")
(out / "issuer-id").write_text(data["ASC_ISSUER_ID"] + "\n")
(out / f"AuthKey_{key_id}.p8").write_text(data["ASC_PRIVATE_KEY"])
PY
rm -f "$tmp/asc.json"
chmod 600 "$tmp"/AuthKey_*.p8
chmod 644 "$tmp"/key-id "$tmp"/issuer-id

doppler run --project conduit --config dev -- sh -lc "
  export SSHPASS=\"\$MACOS_SSH_PASSWORD\"
  SSH_BASE=\"sshpass -e ssh -o StrictHostKeyChecking=no -o PubkeyAuthentication=no -p ${VM_SSH_PORT} base@${VM_SSH_HOST}\"
  SCP_BASE=\"sshpass -e scp -q -o StrictHostKeyChecking=no -o PubkeyAuthentication=no -P ${VM_SSH_PORT}\"
  \$SSH_BASE 'mkdir -p \$HOME/.config/opencode-remote/app-store-connect && chmod 700 \$HOME/.config/opencode-remote \$HOME/.config/opencode-remote/app-store-connect'
  \$SCP_BASE ${tmp}/key-id ${tmp}/issuer-id ${tmp}/AuthKey_*.p8 base@${VM_SSH_HOST}:.config/opencode-remote/app-store-connect/
  \$SSH_BASE 'find \$HOME/.config/opencode-remote/app-store-connect -name \"AuthKey_*.p8\" -exec chmod 600 {} +'
"
rm -rf "$tmp"

echo "== build (CONFIG=$CONFIG) =="
TEAM="${DEVELOPMENT_TEAM:-$(doppler run --project opencode-remote --config dev -- printenv DEVELOPMENT_TEAM 2>/dev/null || true)}"
if [ -z "$TEAM" ]; then
  echo "DEVELOPMENT_TEAM is not set; add it to .env or the Doppler project (see .env.example)"
  exit 2
fi
doppler run --project conduit --config dev -- sh -lc "
  export SSHPASS=\"\$MACOS_SSH_PASSWORD\"
  SSH_BASE=\"sshpass -e ssh -o StrictHostKeyChecking=no -o PubkeyAuthentication=no -p ${VM_SSH_PORT} base@${VM_SSH_HOST}\"
  SCP_BASE=\"sshpass -e scp -q -o StrictHostKeyChecking=no -o PubkeyAuthentication=no -P ${VM_SSH_PORT}\"
  printf '%s\n' \"\$MACOS_SSH_PASSWORD\" | \$SSH_BASE 'DEVELOPMENT_TEAM=${TEAM} CONFIG=${CONFIG} bash ${VM_REPO_BASE}/scripts/vm/base-build.sh' | tail -8
  IPA=\$(\$SSH_BASE 'ls -1t /tmp/opencode-build/*/export/OpenCodeRemote.ipa | head -1')
  \$SCP_BASE base@${VM_SSH_HOST}:\"\$IPA\" ${WORK}/OpenCodeRemote.ipa
"

if [ ! -s "$WORK/OpenCodeRemote.ipa" ]; then
  echo "no IPA fetched"
  exit 1
fi
echo "IPA: $(du -h "$WORK/OpenCodeRemote.ipa" | cut -f1)"

echo "== upload to Diawi =="
doppler run --project conduit --config dev -- \
  python3 "$LOCAL/scripts/ui/diawi.py" "$WORK/OpenCodeRemote.ipa"
