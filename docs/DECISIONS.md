# Decisions and open questions

## Confirmed by the user

### Product

- The platform is **iPhone only**.
- The client is built natively in **Swift/SwiftUI** for iOS 17 and later.
- The working name is **OpenCode Remote** (the repository is called `opencode-remote`).
- The app assumes the user already has a working **OpenCode installation**.
- The ambition is **full agent work**: agent runs, questions, approvals, status, history and resuming after interruptions must all be handled from the phone.
- The MVP must be **App Store publishable**.

### Connection

- **Tailscale Serve** provides private HTTPS between the iPhone and the user's OpenCode installation.
- The server is protected with `OPENCODE_SERVER_PASSWORD` and basic authentication.
- Credentials are stored per connection in the **Keychain**. No account service and no host helper.
- Pairing in the MVP is **manual entry of URL and password**. No QR code and no script.
- Multiple connections (**Computers**) can be active at the same time. The MVP shows them separately; a combined view comes later.

### API and client

- Only OpenCode's HTTP API is used. No custom backend, no agent engine and no custom conversation database.
- The client calls the **documented legacy API surface**. Experimental `/api/*` and `/experimental/*` are not used in the MVP.
- The Swift client is **generated at build time** from a trimmed, pinned OpenAPI subset (swift-openapi-generator as a build plugin).
- **Version:** pin to the latest OpenCode at build time, allow newer servers, do not guarantee backwards compatibility for anything older than the current latest, and show a clear error for older or unknown versions (read from `/global/health`). Only endpoints present in the pinned spec are called.
- **Persistence:** all UI preferences (collapse state, last model and agent, last used computer, the open conversation) go through one `Preferences` store backed by UserDefaults, per computer where the choice belongs to one; no SQLite and no generic backend abstraction. Passwords stay in the Keychain. See `persistence.md`.
- **History pagination:** the timeline loads the newest page (`GET /session/:id/message?limit=50`) and a "load older" button follows the server's `X-Next-Cursor` response header back through history as `before`. The cursor is not in the pinned OpenAPI schema, so it is read in a client middleware; only the legacy endpoint and its documented `limit`/`before` parameters are used. No experimental cursor API.

### MVP scope (included)

- Add, edit and delete Computers (URL and password in Keychain).
- Open existing projects and create a new project where the API allows (a folder picker showing only directories, or a manual path).
- List, create, rename, abort and delete sessions.
- Choose agent and model.
- Send text and images (camera or library) as an instruction.
- Follow replies and tool status in real time.
- Answer questions and approvals (preliminary, see below).
- Show todos and child sessions read-only.
- Reconcile against the server when returning.

### MVP scope (not included)

- Diff and file viewing. Review happens in git/GitHub after the agent pushes.
- Manual file editing.
- Shell and terminal (`/session/:id/shell`, `/pty`).
- Session sharing, fork and revert/unrevert.
- Push notifications.
- Custom backend or host helper.
- Search field in the sidebar.

### IA and distribution

- **Sidebar and chat window** are the main surfaces; everything else is popups and overlays.
- Builds run on a **macOS VM**. The IPA is distributed via **Diawi** during development and via **TestFlight** toward the end of the MVP.
- Privacy: no telemetry or analytics, a privacy manifest with no data collection, no private APIs.
- CI signing (2026-09-16, verified in `dev-build`): a **persistent CI certificate + provisioning profile** as GitHub environment secrets, imported into a temporary keychain, xcodebuild signs offline. No ASC API calls during the build and no per-run certificate churn (per-run mint/retire stalls indefinitely against the ASC API via `-allowProvisioningUpdates`); GitHub's documented macOS signing pattern is followed. Renewal is manual: mint a new certificate/profile with the same names and refresh the secrets.

## Preliminary (must be investigated during implementation)

- The exact behaviour of the approval and question overlays (approve/deny/always, blocking degree).
- The scope of message rendering (reasoning, retry, compaction, token and cost counters).

## Open questions and to verify

- Can the legacy API surface open an arbitrary folder as a new project via the `directory` parameter on `POST /session`? Decided in the integration check.
- Does the trimmed OpenAPI subset generate clean Swift with Swift OpenAPI Generator without customizations?
- Final App Store name and bundle ID.
- The exact minimum OpenCode server version (the pin is decided at build time).
- Setting up Tailscale on the iPhone and host computer.

## Version base

The research was checked on 2026-09-13 against OpenCode **v1.18.30**, with source at commit `3104c1428ec91f809e5ab86631300de41eb6952e`. That is the version to pin until a newer one is verified.
