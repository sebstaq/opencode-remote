#!/usr/bin/env bash
# Seeds one session on a fixture server with enough messages to exercise the
# "load older" paging: `noReply` appends a user message without invoking a
# model, so this is fast and needs no provider.
#
# Usage: scripts/seed-pagination.sh [base-url] [count]
set -euo pipefail

URL="${1:-http://127.0.0.1:4099}"
COUNT="${2:-60}"
AUTH="${3:-}"

CURL=(curl -s)
[ -n "$AUTH" ] && CURL+=(-u "$AUTH")

SID="$(
  "${CURL[@]}" -X POST "$URL/session" \
    -H 'content-type: application/json' \
    -d '{"title":"Pagination seed"}' \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])'
)"
echo "pagination session: $SID"

for i in $(seq 1 "$COUNT"); do
  n="$(printf '%03d' "$i")"
  "${CURL[@]}" -X POST "$URL/session/$SID/message" \
    -H 'content-type: application/json' \
    -d "{\"parts\":[{\"type\":\"text\",\"text\":\"marker $n\"}],\"noReply\":true}" \
    -o /dev/null
done

# Sanity: the newest page must advertise a cursor, or paging will not show.
cursor="$(
  "${CURL[@]}" -D - "$URL/session/$SID/message?limit=50" -o /dev/null \
    | tr -d '\r' | awk 'tolower($1)=="x-next-cursor:" {print $2}'
)"
if [ -z "$cursor" ]; then
  echo "seeded $COUNT messages but no X-Next-Cursor was returned" >&2
  exit 1
fi
echo "seeded $COUNT messages (cursor present)"
