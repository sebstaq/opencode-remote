#!/bin/bash
set -uo pipefail
U=382C7A4A-977D-4FCF-935B-0A060C64B15F
BID=dev.sebstaq.opencode.OpenCodeRemote
AX=/usr/local/bin/axe
xcrun simctl install "$U" /tmp/ocapp-theme/OpenCodeRemote.app
xcrun simctl terminate "$U" "$BID" 2>/dev/null
sleep 1
xcrun simctl ui "$U" appearance light
SIMCTL_CHILD_OPENCODE_E2E_URL="http://10.0.2.2:4098" \
SIMCTL_CHILD_OPENCODE_E2E_PASSWORD="test1234" \
SIMCTL_CHILD_OPENCODE_E2E_NAME="Theme rig" \
xcrun simctl launch "$U" "$BID" >/dev/null
sleep 9
$AX tap -x 30 -y 76 --udid "$U" --post-delay 2
/usr/local/bin/axe describe-ui --udid "$U" > /tmp/ui-theme.json 2>&1
ROWY=$(python3 /tmp/find-row.py)
echo "ROWY=$ROWY"
$AX tap -x 167 -y "$ROWY" --udid "$U" --post-delay 3
xcrun simctl io "$U" screenshot /tmp/shots/theme-1-light.png
xcrun simctl ui "$U" appearance dark
sleep 3
xcrun simctl io "$U" screenshot /tmp/shots/theme-2-dark.png
xcrun simctl ui "$U" appearance light
echo THEME_SHOTS_DONE
