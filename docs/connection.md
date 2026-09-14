# Connection: states, measurement points, budgets and reconnect

## Purpose

Describes how the app connects to a **Computer** (an OpenCode server), what "connected" means, exactly what is measured, which budgets we are aiming for and how reconnect works. Applies to the first implementation slice (Add computer, session list, chat) and is the basis for the measurement and optimization work.

## Concepts

- **Computer:** a connection profile, i.e. a Tailscale HTTPS URL plus the server password in the Keychain.
- **Connection:** an active HTTP session with keep-alive against a Computer.
- **Projects and sessions:** server model according to `DECISIONS.md`.
- A Computer is a machine and never a project.

## States and transitions

States: `idle`, `connecting`, `connected`, `reconnecting`, `offline`.

- `idle` → `connecting`: the user saves or opens a Computer, or the app starts with a selected Computer (prefetch).
- `connecting` → `connected`: `/global/health` answers 200 and the version is supported.
- `connecting` → `offline`: error (unreachable, TLS, 401, version too low or timeout).
- `connected` → `reconnecting`: the network drops, a call fails or the SSE stream breaks.
- `reconnecting` → `connected`: health and version OK again.
- `reconnecting` → `offline`: after max attempts, or on a non-recoverable error (401, version too low).
- `offline` → `connecting`: manual "Try again" or the network coming back via `NWPathMonitor`.

Invariant: **"connected" is not the same as "data loaded"**.

## Definitions

- **Connected:** the latest health call answered 200 and the version is at least the pinned minimum.
- **Data loaded:** projects and sessions for the active Computer have been fetched since the last connection.
- **Server as source of truth:** the server owns sessions and run status. We cache nothing as truth.

## Connection sequence (Add computer to connected)

1. Parse the URL. Only `https` is accepted, `http` is rejected.
2. Validate that the password field is not empty.
3. `GET /global/health` with basic authentication and a timeout.
4. Parse `{ healthy, version }` and compare against the pinned minimum version.
5. On success: save the profile in the Keychain, mark `connected` and then fetch projects and sessions.
6. On failure: map to the error type, show it in the form and save nothing.

Measurement points (monotonic timestamps):

- `t0`, the user taps Save or the prefetch starts
- `t_dns`, `t_tcp`, `t_tls` (start/end per phase)
- `t_request_sent`
- `t_ttfb`, first byte
- `t_response_end`
- `t_health_parsed`
- `t_version_ok`
- `t_sessions_loaded`
- `t_connected` = `t_version_ok`
- `t_ready` = `t_sessions_loaded`

## Instrumentation

- `URLSessionTaskMetrics` per task: DNS, TCP, TLS, TTFB and total.
- `os_signpost` (Points of Interest) per state transition and milestone, as intervals.
- A ring buffer in the app with measurement records (state, milestone, milliseconds) that can be exported in debug and TestFlight for p50/p95.
- The measurement layer wraps the generated client; it does not live inside it.

## Budgets (proposals, to be adjusted)

Warm connections (keep-alive and TLS reuse), over Tailscale:

- health TTFB: p50 < 120 ms, p95 < 300 ms
- time to `connected`: p50 < 300 ms, p95 < 800 ms
- time to `ready`: p50 < 700 ms, p95 < 1.5 s

Cold connections (no session or keep-alive):

- `connected`: p50 < 800 ms, p95 < 2 s
- `ready`: p50 < 1.5 s, p95 < 3 s

Reconnect after forced interruption:

- time to `connected` again: p50 < 1 s, p95 < 3 s on the first attempt
- no double instructions; a sent message may never run twice

A local server (loopback or simulator) is used as the baseline to separate network cost from Tailscale cost.

## Reconnect policy

- `NWPathMonitor`: on `satisfied`, try to reconnect immediately. On `unsatisfied`, go to `reconnecting` or `offline`.
- Backoff: 0.5 s, 1 s, 2 s, 4 s, 8 s as the cap, with roughly 20 percent jitter. Reset after a successful connection.
- SSE (`/event`): keep the stream open. On break, reconnect with backoff and always run a resync (status, messages and pending decisions) after reconnecting.
- Foreground: on app start and on returning, the connect sequence and a resync run. A reopened socket may not alone count as proof that everything has been fetched.
- Non-recoverable (401 or version too low): stay in `offline` and require user action.

## Optimization requirements

- One `URLSession` per Computer with keep-alive, and TLS session resumption.
- Parallelize independent calls (projects, sessions, status) after `connected`; avoid sequential round trips.
- Prefetch: at app start, connect immediately to the most recently used Computer without blocking the UI.
- Keep SSE open instead of polling.
- Do not fetch the entire history unnecessarily. Take the latest and paginate backwards.
- Use HTTP/2 if the server offers it (Tailscale Serve and OpenCode), otherwise keep-alive.

## Error catalogue and UI

- Invalid or non-https URL: inline in the form.
- Unreachable or timeout: "Can't reach the computer".
- TLS error: same failure screen with different text.
- 401: "Wrong password".
- Version too low: "Server version not supported", with both versions visible.

The errors map to the failure screens in the wireframe.

## Measurement method

- Functional checks in the simulator (simctl and axe), but that is not the truth about latency.
- Latency truth on a physical iPhone via Diawi against a real Tailscale-connected OpenCode server.
- Repeated runs: at least 30 per scenario, report p50, p95 and max.
- Scenarios: cold start, warm start, reconnect after airplane mode, reconnect after server restart, plus latency and packet loss via Network Link Conditioner or `tc netem`.
- Baseline against a local server to isolate the Tailscale cost.

## Open questions

- Exact budgets. The numbers above are proposals.
- The actual cost of the Tailscale Serve hop. Must be measured.
- Whether HTTP/2 is offered via Tailscale Serve and OpenCode.
- Timeout values for health and the reconnect cap.
- How much history is fetched initially.
