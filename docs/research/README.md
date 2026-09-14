# OpenCode on iPhone – decision base

Research date: 2026-09-13. The direction is a native iPhone app in Swift/SwiftUI for people who already have OpenCode installed. The app should be usable for driving agent work fully. Tailscale is accepted initially; a custom backend should be limited to what a concrete requirement actually needs.

## Overall assessment

**We have support for moving forward with a directly connected iPhone client without a custom cloud backend for the core flow.** OpenCode already provides sessions, agent runs, history and APIs for interaction. The mobile app's significant work is the interface, handling of events, reconnection and correctly rendering the server's state. This is feasibility based on documentation and source code, not a finished or physically verified iPhone integration. [OpenCode's server API](https://opencode.ai/docs/server/).

The first connection path is **iPhone → private HTTPS via Tailscale Serve → OpenCode on the user's computer/server**. It requires Tailscale on both devices, the right tailnet and an approved VPN configuration on the iPhone. Tailscale Serve is an existing proxy on the host computer; we do not need to write our own equivalent. OpenCode can listen on loopback and use its server password. [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve), [Tailscale on iOS](https://tailscale.com/docs/install/ios).

## What we need to own

| Need | Existing support | Our responsibility / possible extra component |
|---|---|---|
| Agent runs, files, projects and history | The user's OpenCode installation | Native UI and API client |
| Encrypted private remote connection | Tailscale and Serve HTTPS | Connection profile, Keychain and clear error handling |
| Continuing after the phone loses the network | Server-side execution and readable state | Reconnection, reconciliation and avoiding duplicate instructions |
| The same in-progress work from computer and phone | Multiple clients can talk to OpenCode | Connect to the same running server; do not assume two separate processes share active execution |
| Notification when something happens while the app is closed | Apple's APNs for remote notifications | An event source on the computer and a trusted APNs sender; a separately possible add-on service |
| Removing the Tailscale app requirement | User-managed HTTPS or SSH are possible paths | More connection work; not automatically our own cloud service |
| Simple pairing and revoking a single phone | Not a documented OpenCode v1 flow | A small helper process on the computer could own device permissions if it is the only external path to the loopback-bound OpenCode |
| Connection without network configuration across different NATs/networks | Not solved by a QR code or authentication alone | Investigate an existing connection service or relay service if this becomes a requirement |

Details and primary sources: [connection and security](connection.md), [lifecycle and reconnection](lifecycle.md).

No custom database for conversations, account service or agent engine is needed for the proposed first flow. Local storage of connection profiles, drafts and any cache are app features. Tailscale and the model providers remain external dependencies: no custom cloud operation does not mean the whole solution is standalone from services.

## The flow we need to design

We need a coherent flow from connection and project selection to a new or existing conversation, agent/model choice, instruction with any attachment, ongoing tool activity, agent questions and approvals, review of changes and the next instruction. The project's files and commands run on the host computer. All questions and approvals needed for work to proceed must be available in the phone's UI.

The feature review found direct support for these core parts, including readable pending questions/approvals and the session's diff. A few limits affect UI planning: attachments are sent as part of the instruction rather than to a separate upload service, and dedicated buttons for e.g. git commit/push have no corresponding REST routes of their own and would need to use the host computer's existing command paths. That is not in itself a reason to build a new backend. [Version-locked API schema](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/sdk/openapi.json).

**Full agent usage is the decided ambition.** How extensive manual code editing, terminal and display of running web pages we want is not yet a product decision. The API review therefore separates direct API capabilities from things the agent can do with its existing tools, and from possible extra services. See the [feature map](api.md).

## Interruptions are part of normal usage

The phone should be able to leave the app without the app itself having to keep the agent alive. That does not mean a shut down or sleeping host computer can keep working, or that a server restart automatically resumes a job.

When the app returns it needs to fetch current messages, run status and pending questions/approvals. A reopened live connection may not alone be treated as proof that everything that happened during the interruption has been fetched. An instruction whose delivery is unclear should be checked against the server before being sent again. The behaviour for the chosen API surface and server version is described in the [lifecycle report](lifecycle.md).

The legacy event stream has no replay marker; the app needs to combine live events with reconciliation against the readable server state. The source tree also contains a newer experimental protocol with stored event history and protection against identical repeated instructions. It is a relevant possibility for later integration testing, but an installation answering on an `/api` address does not prove it runs the new execution engine. [Protocol detection](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/app/src/utils/server-protocol.ts), [newer session contract](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/protocol/src/groups/session.ts).

Notifications are a separate add-on: our recommendation is to first make active usage and returning to the app correct. Adding APNs later does not change the need for OpenCode as the execution environment. It is not decided that we build a notification service in the first version. [Apple's APNs documentation](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns).

## The API version must be chosen deliberately

The base uses release **v1.18.30**, whose tag resolved to **3104c1428ec91f809e5ab86631300de41eb6952e**. The release contains both legacy routes and a new experimental `/api/*` surface; they must not be mixed as if they were a single unchanging contract. The new surface is explicitly described as experimental in the source. [Release](https://github.com/anomalyco/opencode/releases/tag/v1.18.30), [API definition](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/protocol/src/api.ts).

The documented legacy surface is our first candidate. The minimum supported OpenCode version is decided after a small integration check, not by assuming every already-installed version behaves the same. We do not need to support every historical version from the start.

Swift can speak HTTP directly. Apple's OpenAPI generator is one possible way to get typed calls, but it is not yet verified that OpenCode's schema works without customizations; a limited hand-written client is also possible. We have not chosen the dependency or the minimum iOS version. [Swift and compatibility](compatibility.md).

## Next steps the base justifies

We can now design the app's core flow while a later, scoped integration check probes the risks that affect the UI. That check needs a disposable test installation and a physical iPhone; it is not part of this documentation and source-code review.

| Check | What must be true |
|---|---|
| Connection and project | Right server, right folder and right conversation shown; wrong version or permission gives an understandable error |
| Execution and screen lock | An accepted instruction can continue on the host computer when the phone leaves the app |
| Return | The UI shows the server's current history and status without missing or duplicate messages |
| Pending decisions | Questions and approvals that arrived during absence can be answered |
| Uncertain delivery | A network drop after a sent message does not lead to an unintended double run |
| Computer and phone | Both can follow the same session on the same server; a decision is not answered twice |
| Review | Attachments, tool results and diffs render correctly and can be tied to the right instruction |
| Server disappears | The phone distinguishes disconnection from aborted execution and updates the state after returning |

## Base and limitation

Three Luna agents reviewed the functional APIs, iOS/lifecycle and secure connection respectively. The main agent reviewed version choice, Swift options and the conclusions, and compiled this base. All technical conclusions in the reports have sources or are marked as proposals/untested assumptions. We have not started the user's OpenCode, changed Tailscale, read private sessions, called any model or implemented the app.

- [Feature map and API gaps](api.md)
- [iOS, sessions and reconnection](lifecycle.md)
- [Secure connection and the smallest possible future addition](connection.md)
- [Swift, API versions and existing reference clients](compatibility.md)
