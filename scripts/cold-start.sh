#!/usr/bin/env bash
set -euo pipefail

# Host-side cold-start measurement. Run under `doppler run --project conduit --config dev --`.
# Launches the app N times; each launch performs one cold connect and writes a report.
# Aggregates the first sample per launch.

source "$(dirname "$0")/lib/vm.sh"
source "$(dirname "$0")/lib/env.sh"

VM_SCRIPT="${VM_SCRIPT:-${VM_SCRIPT_DIR}/measure-connect.sh}"
MEASURE_URL="${MEASURE_URL:-${OPENCODE_TAILNET_URL:-}}"
if [[ -z "$MEASURE_URL" ]]; then
  echo "MEASURE_URL is not set; add OPENCODE_TAILNET_URL to .env (see .env.example)" >&2
  exit 2
fi
N="${N:-10}"

P="$(doppler run --project opencode-remote --config dev -- printenv OPENCODE_SERVER_PASSWORD)"

rm -f /tmp/opencode/cold-*.json
for i in $(seq 1 "$N"); do
  printf '%s\n' "$P" | vm_ssh \
    "SIMULATOR_UDID=${SIMULATOR_UDID} XCODE_DERIVED=${XCODE_DERIVED} MEASURE_URL=${MEASURE_URL} BUNDLE_ID=${BUNDLE_ID} SCENARIO=connect RUNS=1 SLEEP=8 bash ${VM_SCRIPT}" >/dev/null
  SSHPASS="$MACOS_SSH_PASSWORD" rsync -az \
    -e "${VM_RSYNC_SSH}" \
    "${VM_SSH_USER}@${VM_SSH_HOST}:/tmp/measure-report.json" "/tmp/opencode/cold-${i}.json" >/dev/null 2>&1 || true
done
unset P

python3 - <<'PY'
import glob, json
vals = []
for f in sorted(glob.glob('/tmp/opencode/cold-*.json')):
    try:
        d = json.load(open(f))
        if d['samples']:
            vals.append(d['samples'][0])
    except Exception:
        pass
vals.sort()
def pct(p, arr):
    rank = p / 100 * (len(arr) - 1)
    lo = int(rank)
    hi = min(lo + 1, len(arr) - 1)
    w = rank - lo
    return arr[lo] * (1 - w) + arr[hi] * w
print("cold runs:", len(vals))
if vals:
    print("cold: min %.1f  p50 %.1f  p95 %.1f  max %.1f ms"
          % (vals[0], pct(50, vals), pct(95, vals), vals[-1]))
PY
