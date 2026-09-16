#!/usr/bin/env bash
set -euo pipefail

PORT="${OPENCODE_FIXTURE_PORT:-4096}"
RUN_DIR="${TMPDIR:-/tmp}/opencode-remote-fixture-${PORT}"

rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR/state" "$RUN_DIR/data" "$RUN_DIR/project"

git -C "$RUN_DIR/project" init -q
printf 'fixture\n' > "$RUN_DIR/project/README.md"
git -C "$RUN_DIR/project" add -A
git -C "$RUN_DIR/project" -c user.email=fixture@local -c user.name=fixture commit -qm fixture

echo "fixture project: $RUN_DIR/project"
echo "listening on 127.0.0.1:$PORT (isolated state and data)"

exec env \
  XDG_STATE_HOME="$RUN_DIR/state" \
  XDG_DATA_HOME="$RUN_DIR/data" \
  opencode serve --port "$PORT" --hostname 127.0.0.1 --pure
