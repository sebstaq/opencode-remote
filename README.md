# OpenCode on iPhone

Plan for a native iPhone client for people who already have OpenCode installed. The app should give full access to agent work from the iPhone, built with Swift/SwiftUI and as little bespoke infrastructure as possible.

## Current status

The project is in planning and `opencode-remote` is the working name for the repository. The research was checked on 2026-09-13 against OpenCode **v1.18.30**, with source at commit `3104c1428ec91f809e5ab86631300de41eb6952e`. It shows that a direct iPhone client against the OpenCode server is feasible, but no app, server connection, Tailscale path or runtime verification has been done yet.

The first planned flow is iPhone → private HTTPS via Tailscale Serve → the user's existing OpenCode installation. A custom backend stays out of the core flow until a concrete requirement justifies it.

## Documents

- [Decisions and open questions](docs/DECISIONS.md)
- [Connection spec](docs/connection.md)
- [Structure and tooling](docs/structure.md)
- [Acceptance criteria: connection](docs/acceptance.md)
- [Measurements](docs/measurements.md)
- [Next steps](docs/NEXT_STEPS.md)
- [Research base](docs/research/README.md)

The research distinguishes between the documented legacy API surface and the experimental `/api/*` surface. Which surface to support first is decided by a scoped integration check against the chosen server version.

## Scope

Current work covers product planning and technical verification. It does not include implementing the iPhone app, running a new cloud service, or changing the user's OpenCode and network environment.
