# Measurements: connection

All measurements run in the simulator in the macOS VM against a real OpenCode server over Tailscale (`https://<machine>.<tailnet>.ts.net`, configured in `.env`, see `.env.example`), with the server password. The app measures itself with `URLSessionTaskMetrics` and `os_signpost`, and every attempt is logged with a timestamp.

## Definitions

- **Cold connection**: the first connection in a process, new `URLSession`, full DNS/TCP/TLS.
- **Warm connection**: subsequent connections on the same session, keep-alive and TLS reuse.
- **Resume**: the app returns to the foreground and verifies the connection immediately.
- **Reconnect**: time from the interruption being detected to the connection being restored.

## Results (2026-09-13)

| Measurement | Result |
|---|---|
| Cold connection (10 launches) | min 557.1 ms, p50 640.2 ms, p95 795.8 ms, max 854.4 ms |
| Warm connection | min 11.8 ms, p50 52.7 ms, p95 103.8 ms, max 147.1 ms |
| Resume from background | ~16 ms |
| Reconnect (15 drops) | min 513.7 ms, p50 529.4 ms, max 665.2 ms |
| Successful attempts | 20/20 (connect), 15/15 (reconnect) |

Cold connection is dominated by TLS (DNS and TCP are negligible compared to Tailscale). Resume is effectively free because TCP/TLS is reused.

## Budgets and status

| Scenario | Target (p50 / p95) | Status |
|---|---|---|
| Cold connection | < 1 s / < 2 s | within target |
| Warm connection | < 100 ms / < 300 ms | within target |
| Resume | < 100 ms / < 300 ms | within target |
| Interruption detection | < 2 s | heartbeat 2 s |
| Reconnect after reachable again | < 1 s / < 3 s | within target (p50 0.55 s) |

## How the measurement runs

```sh
doppler run --project conduit --config dev -- scripts/measure.sh
```

Assumes `SIMULATOR_UDID`, `XCODE_DERIVED` and `MEASURE_URL` in the VM's environment (set in the `scripts/vm/measure-connect.sh` invocation), and the password via Doppler (`conduit/dev` for SSH, `opencode-remote/dev` for the server).

## Remaining

Reconnect is measured in isolation as the gap from the last failed attempt to the first successful one, i.e. the app's own delay after the server becomes reachable again (bounded by the backoff cap of 0.5 s). Cold start is measured over multiple app launches, reconnect over multiple drops. Resume is measured manually; automating background/foreground is a minor remaining task and does not affect the architecture.
