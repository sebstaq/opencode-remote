#!/bin/bash
# Runs on the macOS VM: streams a fixed fixture into the app and counts missed
# display-link ticks from the FrameDropMonitor log. APP_DIR selects the app
# bundle (/tmp/ocapp-baseline = main, /tmp/ocapp-theme = streaming build).
set -uo pipefail
U=382C7A4A-977D-4FCF-935B-0A060C64B15F
BID=dev.sebstaq.opencode.OpenCodeRemote
AX=/usr/local/bin/axe
APP_DIR="${APP_DIR:-/tmp/ocapp-theme}"
DRAFT="Generera testdata: 250 rader med post N, id-N och status ok i ett kodblock. Inga kommentarer eller forklaringar."

xcrun simctl install "$U" "$APP_DIR/OpenCodeRemote.app"
xcrun simctl terminate "$U" "$BID" 2>/dev/null
sleep 1

LOG=/tmp/framedrop-$(date +%s).log
xcrun simctl spawn "$U" log stream \
  --predicate 'subsystem == "dev.sebstaq.opencode" AND category == "frameDrop"' \
  --style compact >"$LOG" 2>&1 &
LOGPID=$!
trap 'kill $LOGPID 2>/dev/null' EXIT
sleep 2

SIMCTL_CHILD_OPENCODE_UI_DRAFT="$DRAFT" \
xcrun simctl launch "$U" "$BID" >/dev/null
sleep 12
for i in 1 2 3; do
  $AX describe-ui --udid "$U" 2>/dev/null | grep -q '"Select a session"' && break
  xcrun simctl terminate "$U" "$BID" 2>/dev/null
  sleep 1
  SIMCTL_CHILD_OPENCODE_E2E_URL="https://sebastian-desktop.tailc833ee.ts.net" \
  SIMCTL_CHILD_OPENCODE_E2E_PASSWORD="test1234" \
  SIMCTL_CHILD_OPENCODE_E2E_NAME="Stream test" \
  SIMCTL_CHILD_OPENCODE_UI_MEASURE_FRAMES=1 \
  SIMCTL_CHILD_OPENCODE_UI_DRAFT="$DRAFT" \
  xcrun simctl launch "$U" "$BID" >/dev/null
  sleep 12
done
$AX describe-ui --udid "$U" 2>/dev/null | grep -q '"Select a session"' || { echo NEVER_CONNECTED; exit 1; }
$AX tap -x 30 -y 76 --udid "$U" --post-delay 2 >/dev/null 2>&1 || true
$AX tap -x 167 -y 225 --udid "$U" --post-delay 3 >/dev/null 2>&1 || true
READY=""
for i in $(seq 1 10); do
  $AX describe-ui --udid "$U" 2>/dev/null | grep -q '"composer.send"' && { READY=1; break; }
  sleep 1
done
[ -n "$READY" ] || { echo NO_SEND; exit 1; }
$AX tap --id composer.send --udid "$U" --post-delay 2 >/dev/null 2>&1 || { echo NO_SEND; exit 1; }

# Wait until the run finishes (send button replaces the stop button), max 120 s
DONE=""
for i in $(seq 1 120); do
  $AX describe-ui --udid "$U" 2>/dev/null | grep -q '"composer.stop"' || { DONE=1; break; }
  sleep 2
done
[ -n "$DONE" ] || echo "still-running"
sleep 2

python3 - "$LOG" <<'PY'
import re, sys
lines = open(sys.argv[1], errors="replace").read().splitlines()
drops = []
for line in lines:
    m = re.search(r"drop interval=([0-9.]+)s", line)
    if m:
        drops.append(float(m.group(1)))
gaps = sorted(d[0] - 1/60 for d in drops)
n = len(drops)
if n:
    def pct(p):
        i = min(int(p/100*(len(gaps)-1)), len(gaps)-1)
        return gaps[i]
    print("dropped_frames:", n)
    print("longest_gap_ms: %.0f" % (max(gaps)*1000))
    print("p95_gap_ms: %.0f" % (pct(95)*1000))
    print("median_gap_ms: %.0f" % (pct(50)*1000))
else:
    print("dropped_frames: 0")
PY
