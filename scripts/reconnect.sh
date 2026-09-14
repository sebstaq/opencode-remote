#!/usr/bin/env bash
set -euo pipefail

# Host-side reconnect measurement. Run under `doppler run --project conduit --config dev --`.
# Drops the rig server, brings it back, and reports the app-added reconnect latency
# (gap from the last failed attempt to the first successful one), bounded by the
# reconnect backoff. No cross-clock comparison needed.

source "$(dirname "$0")/lib/vm.sh"
source "$(dirname "$0")/lib/env.sh"

VM_SCRIPT="${VM_SCRIPT:-${VM_SCRIPT_DIR}/measure-connect.sh}"
LOCAL_REPORT="${LOCAL_REPORT:-/tmp/opencode/measure-report.json}"
MEASURE_URL="${MEASURE_URL:-${OPENCODE_TAILNET_URL:-}}"
if [[ -z "$MEASURE_URL" ]]; then
  echo "MEASURE_URL is not set; add OPENCODE_TAILNET_URL to .env (see .env.example)" >&2
  exit 2
fi
PORT="${OPENCODE_PORT:-4096}"
PID_FILE="${TMPDIR:-/tmp}/opencode-rig.pid"

P="$(doppler run --project opencode-remote --config dev -- printenv OPENCODE_SERVER_PASSWORD)"

printf '%s\n' "$P" | vm_ssh \
  "SIMULATOR_UDID=${SIMULATOR_UDID} XCODE_DERIVED=${XCODE_DERIVED} MEASURE_URL=${MEASURE_URL} BUNDLE_ID=${BUNDLE_ID} LAUNCH_ONLY=1 SCENARIO=reconnect SECONDS_WINDOW=210 bash ${VM_SCRIPT}" >/dev/null
unset P

sleep 6
DROPS="${DROPS:-15}"
for _ in $(seq 1 "$DROPS"); do
  kill "$(cat "$PID_FILE")" 2>/dev/null || true
  sleep 4
  doppler run --project opencode-remote --config dev -- "$(dirname "$0")/rig-host.sh" up >/dev/null 2>&1
  for _ in $(seq 1 30); do
    code=$(curl -s -o /dev/null -w '%{http_code}' -m 3 "http://127.0.0.1:${PORT}/global/health" || true)
    [[ "$code" == "401" ]] && break
    sleep 0.5
  done
  sleep 3
done
sleep 4

vm_ssh "C=\$(xcrun simctl get_app_container ${SIMULATOR_UDID} ${BUNDLE_ID} data 2>/dev/null); cp \"\$C/Documents/measure-report.json\" /tmp/measure-report.json" >/dev/null 2>&1 || true

SSHPASS="$MACOS_SSH_PASSWORD" rsync -az \
  -e "${VM_RSYNC_SSH}" \
  "${VM_SSH_USER}@${VM_SSH_HOST}:/tmp/measure-report.json" "$LOCAL_REPORT"

python3 - "$LOCAL_REPORT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
attempts = d['attempts']
gaps = []
last_fail = None
for a in attempts:
    if a['ok']:
        if last_fail is not None:
            gaps.append((a['date'] - last_fail) * 1000)
        last_fail = None
    else:
        last_fail = a['date']
print("attempts:", len(attempts), "failures:", sum(1 for a in attempts if not a['ok']))
if gaps:
    gaps.sort()
    print("reconnect (last failure -> success): min %.1f  p50 %.1f  max %.1f ms"
          % (gaps[0], gaps[len(gaps) // 2], gaps[-1]))
else:
    print("no recovery gap recorded")
PY
