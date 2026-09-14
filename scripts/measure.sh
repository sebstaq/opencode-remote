#!/usr/bin/env bash
set -euo pipefail

# Host-side orchestrator. Run under `doppler run --project conduit --config dev --`
# so MACOS_SSH_PASSWORD is available, and with the server password in
# doppler project opencode-remote config dev.

source "$(dirname "$0")/lib/vm.sh"

VM_SCRIPT="${VM_SCRIPT:-${VM_SCRIPT_DIR}/measure-connect.sh}"
LOCAL_REPORT="${LOCAL_REPORT:-/tmp/opencode/measure-report.json}"
RUNS="${RUNS:-20}"
SLEEP="${SLEEP:-25}"

P="$(doppler run --project opencode-remote --config dev -- printenv OPENCODE_SERVER_PASSWORD)"
printf '%s\n' "$P" | vm_ssh "RUNS=${RUNS} SLEEP=${SLEEP} bash ${VM_SCRIPT}" >/dev/null
unset P

SSHPASS="$MACOS_SSH_PASSWORD" rsync -az \
  -e "${VM_RSYNC_SSH}" \
  "${VM_SSH_USER}@${VM_SSH_HOST}:/tmp/measure-report.json" "$LOCAL_REPORT"

python3 - "$LOCAL_REPORT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
s = d['samples']
warm = sorted(s[1:])
def pct(p, arr):
    rank = p / 100 * (len(arr) - 1)
    lo = int(rank)
    hi = min(lo + 1, len(arr) - 1)
    w = rank - lo
    return arr[lo] * (1 - w) + arr[hi] * w
print("scenario:", d['scenario'], "runs:", len(s))
print("cold (first): %.1f ms" % s[0])
if warm:
    print("warm: min %.1f  p50 %.1f  p95 %.1f  max %.1f ms"
          % (min(warm), pct(50, warm), pct(95, warm), max(warm)))
print("attempts ok: %d/%d"
      % (sum(1 for a in d['attempts'] if a['ok']), len(d['attempts'])))
PY
