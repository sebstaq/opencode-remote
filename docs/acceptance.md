# Acceptance criteria: connection

Every criterion must be runnable and measurable. Real connection means a physical iPhone over Tailscale against a real OpenCode server, not the simulator.

## Criteria

- **AC1, connect.** With a real Tailscale HTTPS URL and the server password, the app becomes `connected`, shows the server's actual version, the version gate accepts at least the minimum level and rejects older ones with both versions visible.
- **AC2, wrong password.** 401 maps to "Wrong password", and nothing is saved to the Keychain.
- **AC3, unreachable and TLS.** Unreachable host and TLS errors each show their respective failure screen, without crashing.
- **AC4, timing.** Cold and warm connections are measured on the real path and fall within the budgets in `connection.md` (p50 and p95).
- **AC5, reconnect.** Forced interruption (airplane mode or stopped server) yields `reconnecting` and then `connected`, time to recovery is measured, and no instruction runs twice.
- **AC6, device.** AC1 through AC5 run on a physical iPhone installed via Diawi, over Tailscale, against the real server.
- **AC7, security.** The password exists only in the Keychain and is never logged or printed.

## Test environments

- **Local fixture (no auth).** `scripts/serve-fixture.sh` starts `opencode serve` against an isolated directory for integration tests of the API and client. No Tailscale.
- **Real path.** `scripts/rig-host.sh up` starts `opencode serve` on the host on loopback with the server password from the environment, and enables Tailscale Serve so the server is reachable as `https://<host>.<tailnet>.ts.net/`. The client is the physical iPhone that is already on the tailnet.
- **Simulator.** Used for function (simctl and axe) against a local or forwarded server, never as the source of truth about latency.

## Rig

- `scripts/rig-host.sh up|down`. `up` requires `OPENCODE_SERVER_PASSWORD` to be present in the environment and refuses to start an unauthenticated server. `down` removes the Tailscale Serve configuration and stops the server.
- The password is provided by the user via the environment, is never printed and is never committed.

## Measurement

- All timing metrics follow the measurement points in `connection.md`. Results are reported as p50, p95 and max over at least 30 runs per scenario.
