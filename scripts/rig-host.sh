#!/usr/bin/env bash
set -euo pipefail

PORT="${OPENCODE_PORT:-4096}"
PID_FILE="${TMPDIR:-/tmp}/opencode-rig.pid"
LOG_FILE="${TMPDIR:-/tmp}/opencode-rig.log"

up() {
  if [[ -z "${OPENCODE_SERVER_PASSWORD:-}" ]]; then
    echo "OPENCODE_SERVER_PASSWORD is not set; refusing to expose an unauthenticated server" >&2
    exit 1
  fi
  local run_dir="${TMPDIR:-/tmp}/opencode-rig"
  mkdir -p "$run_dir/state" "$run_dir/data"
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "server already running (pid $(cat "$PID_FILE"))"
  else
    XDG_STATE_HOME="$run_dir/state" XDG_DATA_HOME="$run_dir/data" \
      opencode serve --hostname 127.0.0.1 --port "$PORT" --pure >"$LOG_FILE" 2>&1 &
    echo $! >"$PID_FILE"
    sleep 3
  fi
  local serve_output
  serve_output="$(tailscale serve --bg "$PORT" 2>&1)"
  if grep -qi "not enabled" <<<"$serve_output"; then
    echo "$serve_output" >&2
    echo "Enable Tailscale Serve for the tailnet, then rerun." >&2
    exit 1
  fi
  echo "$serve_output"
  tailscale serve status
}

down() {
  tailscale serve reset >/dev/null 2>&1 || true
  if [[ -f "$PID_FILE" ]]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
    rm -f "$PID_FILE"
  fi
  echo "rig down"
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  *)
    echo "usage: $0 up|down" >&2
    exit 2
    ;;
esac
