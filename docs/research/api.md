# OpenCode iPhone API research

Checked 2026-09-13 against the current official documentation and the released
v1.18.30 source. The release tag resolves to commit
3104c1428ec91f809e5ab86631300de41eb6952e; all source links below pin that
commit. This is a static research report. No running OpenCode installation,
private configuration, or endpoint was touched, and no live API call was
tested.

## Decision

An iPhone SwiftUI client can cover the requested OpenCode workflow without a
custom application backend. It can speak HTTP JSON plus SSE directly to
opencode serve, and use a ticketed WebSocket only for a persistent terminal
PTY. Tailscale can provide the private network path; the OpenCode server still
needs its own HTTP Basic authentication when exposed beyond loopback.

For compatibility planning, treat the documented legacy surface (/project,
/session, /event, /vcs, and related routes) and the newer /api/* surface as
separate contracts. The release contains 51 /api paths in its 162-path
OpenAPI document, and its source labels that surface "Experimental HttpApi
surface for selected instance routes." The target server must be probed at
runtime to choose the contract: route definitions in a release’s source or
OpenAPI do not prove that a running installation serves those handlers.

## Coverage matrix

| Capability | Release route(s) | Coverage and client implication |
|---|---|---|
| Health and project context | GET /global/health, GET /path, GET /project/current; experimental GET /api/health, GET /api/location | Full bootstrap. Legacy health returns {healthy, version}. /api/health only reports readiness; /api/location resolves a directory/workspace location. Probe and record the server version before selecting an adapter. |
| Projects | GET /project, GET /project/current, POST /project/git/init, PATCH /project/:projectID, GET /project/:projectID/directories | Full project listing/current project, Git initialization, metadata update, and known-directory listing in the release source. The public server guide only documents list/current, so use the release OpenAPI/source for the extra operations. |
| Session list/create | GET /session, POST /session | Full legacy flow. List supports project/path/search/root/start/limit filtering; create accepts optional parent/title and is scoped to the current instance/workspace. The /api/session variant adds location/project/directory filters, opaque cursors, explicit agent/model/location on create, and ordered pagination. |
| Session tree and lifecycle | GET /session/:id, /children, /status, /todo; POST /fork, /abort, /summarize, /revert, /unrevert; DELETE /session/:id | Full session browsing, child-session tree, status, todo, fork, abort, compaction, revert, restore, and deletion. Fork creates a new session from a message; the source does not equate that operation with a Task-created child/subagent run. Task-produced child sessions can be observed through /children when present. |
| Prompts, commands, and direct shell | POST /session/:id/message, /prompt_async, /command, /shell | Full prompt/agent workflow. Prompt body can choose agent, {providerID,modelID}, system/format/variant and parts. Sync waits for a response; async returns 204 and requires events/message reads. /command runs a configured slash command. /shell is a direct server-side shell operation wrapped in the selected agent/session context; it does not require an LLM decision to execute the command. |
| Attachments | Prompt parts[] with type:"file" (legacy) or /api prompt.files[] | Supported in JSON, but there is no upload endpoint. Legacy file input is {mime, filename?, url, source?}; a phone should send a data URL for content/media. file: URLs refer to the server filesystem and cannot refer to an iPhone-local file. Text data URLs become readable text; image/media handling depends on model/provider support and server image limits. This needs a real-device interoperability test. |
| Agents and subagents | GET /agent; experimental GET /api/agent; prompt agent and agent/subtask parts | The API exposes configured agents. The selected agent is passed by name/ID on a prompt; structured agent/subtask parts let the model use configured child agents. There is no stable direct child-agent invocation endpoint: child invocation is agent-mediated through the Task/tool loop, while /children and message parts expose the resulting tree. A mode: subagent agent may only be launchable by an allowed parent/task policy. |
| Models/providers | GET /provider, GET /config/providers; experimental GET /api/model, GET /api/provider | Full discovery of available/connected providers and models. Model IDs are provider/model pairs in the documented API; the prompt can override a session model. /api returns location-scoped model/provider records. Provider OAuth and credential routes exist, but exposing provider setup in a phone client is an optional high-risk feature rather than a prerequisite for an existing installation. |
| Tool catalog and execution | GET /experimental/tool/ids, GET /experimental/tool?provider=&model=; prompt loop | Tool discovery is explicitly experimental. There is no general "execute tool by ID" endpoint. The model invokes built-in, custom, and MCP tools from a prompt according to its agent permissions. The app must render tool-call/result parts and react to permission/question events. |
| Questions | GET /question, POST /question/:requestID/reply, /reject; experimental /api/question/request and session-scoped question routes | Full approval UI: list pending questions, show question/options, reply with ordered answer arrays, or reject. /api additionally scopes requests to a session and returns native typed records. |
| Permissions | GET /permission, POST /permission/:requestID/reply; deprecated POST /session/:id/permissions/:permissionID; experimental /api/permission/* and /api/session/:id/permission/* | Full approval UI. Legacy reply uses response (and older remember shape in the documented route); /api uses reply plus optional message and supports saved-permission inspection/removal. Permission is evaluated server-side from agent/session rules, so the phone is responding to requests, not replacing policy evaluation. |
| Session diff and Git view | GET /session/:id/diff; GET /vcs/status, /vcs/diff, /vcs/diff/raw; POST /vcs/apply | Full read-only diff/status display and raw patch retrieval. The direct VCS mutation is raw patch application and requires a Git project. There is no REST commit, branch, merge, push, or pull endpoint in the release contract. |
| Git actions and terminal | Agent /shell; /pty list/create/get/update/delete plus /pty/:id/connect-token and WebSocket /pty/:id/connect | Git commit/push/etc. are possible through the agent’s bash tool or a direct PTY shell. PTY is the right primitive for an interactive terminal; its connect token is short-lived/single-use and the WebSocket carries terminal input/output. The iPhone must handle WebSocket reconnect and PTY lifetime explicitly. |
| Editor, worktrees, and web preview | GET /file, /file/content, /find*, /file/status; POST /vcs/apply; experimental /experimental/worktree (list/create/delete/reset) | File read/list/search/status and patch application are exposed; agent edit/write/apply_patch tools provide editing through a prompt. Worktree CRUD/reset exists but is explicitly experimental. No dedicated web-preview, browser, or port-forward route was found in the release OpenAPI/source, so that capability is unverified and needs an acceptance test rather than a presumed backend. |
| Live updates and replay | Legacy GET /event and /global/event SSE; experimental GET /api/event; /api/session/:id/event SSE and /history | Legacy SSE exposes the bus event stream and starts with server.connected; it is enough for prompt progress, tool parts, permissions, questions, and file/session updates when combined with message reads. /api adds typed native events, durable aggregate sequence metadata, finite history, and replay-then-follow session SSE, which is materially better for reconnect but is experimental in this release. Do not merge the two event schemas blindly. |

## Agent and subagent semantics

The official agent documentation distinguishes primary agents from subagents and
defines primary, subagent, and all modes. It also states that the agent’s
permission policy controls tools and that task permission controls which child
agents a parent may invoke. This means the app should list agents, display the
currently selected agent, send the selected ID/name on prompts, and preserve
agent/subtask/tool parts when rendering history. It must also expose pending
permission and question requests, because an agent can pause while waiting for a
human response.

The legacy prompt schema accepts text, file, agent, and subtask input parts.
What is absent is a stable direct child-agent invocation endpoint. A phone can
ask a primary agent to use a configured subagent through prompt content or
structured parts, then observe the child session through events and /children.

## Recommended native flow

1. Connect to the Tailscale address, send Basic Auth, call /global/health, then
   resolve the project/path and list agents/providers/models.
2. Establish the legacy event stream with buffering, read the selected session's
   messages/status/pending requests, and reconcile buffered events with that
   snapshot. Legacy SSE has no replay cursor. Repeat reconciliation after every
   reconnect; subscribing before a request does not guarantee lossless delivery.
   See [lifecycle.md](lifecycle.md) for the race-aware design proposal.
3. Create or reuse a session, send a text/file prompt with explicit agent/model
   when selected, and treat prompt_async plus events as the long-running path.
   Read the message record after completion or reconnection rather than relying
   on one HTTP response body.
4. For approval events, show the exact tool/resource/request and post the user’s
   reply. For diffs, use session/VCS diff endpoints; for Git commit/push or a
   true interactive shell, use agent /shell or the ticketed PTY WebSocket.
5. Keep the actual V2 runtime as a later, separately tested integration candidate.
   A response from an /api route is not sufficient: the official detector can
   classify a healthy-only /api/health response as V1. Do not implement two
   adapters just because both contracts appear in the source tree; select the
   initial supported runtime after the focused integration check described in
   [lifecycle.md](lifecycle.md).

## Crucial gaps and risks

- No upload API exists. Data URLs are the practical attachment transport, but
  payload size, image normalization, model media support, and reverse-proxy
  limits are untested here.
- No dedicated commit/push/branch/merge route exists. VCS apply is itself a
  Git operation; the remaining actions can be commands executed on the host.
  Agent-invoked bash uses the configured tool policy. Direct shell, patch and
  PTY routes must not be assumed to pass through that same agent approval path;
  verify their behavior separately if exposing dedicated action buttons.
- Tool discovery endpoints are experimental and catalog-only; tool execution is
  part of the model loop. A client cannot safely reconstruct all tool behavior
  from a tool-ID list alone.
- The /api/* protocol is present in the release OpenAPI and source but is
  explicitly annotated experimental. That source presence does not establish
  that a running target exposes the routes. Where served, it uses different
  envelopes ({data: ...}), location query objects, durable sequence/history, and
  different permission/question payloads from legacy routes.
- The release OpenAPI contains generated TypeScript/JavaScript SDK material only;
  no official Swift SDK was found. SwiftUI needs a small typed HTTP/SSE/WebSocket
  client generated from or mapped to the release OpenAPI. The SSE wire format and
  ticketed PTY WebSocket need device-level tests.
- This report did not test a live OpenCode server, a Tailscale path, Basic Auth,
  provider-specific media, editor writes, worktree lifecycle, web preview,
  permission/question pause-and-resume, or PTY WebSocket behavior. Those remain
  explicit acceptance tests.

## Sources

Official current documentation (read 2026-09-13):

- Server/API overview: https://opencode.ai/docs/server/
- Agents and modes: https://opencode.ai/docs/agents
- Tools: https://opencode.ai/docs/tools/
- Permissions: https://opencode.ai/docs/permissions/
- Models/providers: https://opencode.ai/docs/models/ and https://opencode.ai/docs/providers

Released v1.18.30, immutable commit 3104c1428ec91f809e5ab86631300de41eb6952e:

- Release server guide and documented route list: [server.mdx](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/web/src/content/docs/server.mdx)
- Complete generated release contract (OpenAPI 3.1, 162 paths): [packages/sdk/openapi.json](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/sdk/openapi.json)
- HTTP API assembly and experimental annotation: [httpapi/api.ts](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/opencode/src/server/routes/instance/httpapi/api.ts) and [protocol/api.ts](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/protocol/src/api.ts)
- Legacy session routes and payloads: [httpapi/groups/session.ts](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/opencode/src/server/routes/instance/httpapi/groups/session.ts) and [session/prompt.ts](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/opencode/src/session/prompt.ts)
- /api session, history, durable SSE, and prompt contract: [protocol/groups/session.ts](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/protocol/src/groups/session.ts)
- /api agents/models/providers/files: [protocol/groups/agent.ts](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/protocol/src/groups/agent.ts), [model.ts](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/protocol/src/groups/model.ts), [provider.ts](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/protocol/src/groups/provider.ts), [fs.ts](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/protocol/src/groups/fs.ts)
- Questions and permissions: [question.ts](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/protocol/src/groups/question.ts), [permission.ts](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/protocol/src/groups/permission.ts), and [legacy permission/question groups](https://github.com/anomalyco/opencode/tree/3104c1428ec91f809e5ab86631300de41eb6952e/packages/opencode/src/server/routes/instance/httpapi/groups)
- VCS and PTY: [httpapi/groups/instance.ts](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/opencode/src/server/routes/instance/httpapi/groups/instance.ts), [protocol/groups/pty.ts](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/protocol/src/groups/pty.ts), [httpapi/groups/pty.ts](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/opencode/src/server/routes/instance/httpapi/groups/pty.ts)
- Files and experimental worktrees: [httpapi/groups/file.ts](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/opencode/src/server/routes/instance/httpapi/groups/file.ts) and [httpapi/groups/experimental.ts](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/opencode/src/server/routes/instance/httpapi/groups/experimental.ts)
- Attachments: [schema/v1/session.ts](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/schema/src/v1/session.ts), [schema/prompt-input.ts](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/schema/src/prompt-input.ts), and [image/image.ts](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/opencode/src/image/image.ts)
- Server authentication and route mounting: [server/auth.ts](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/opencode/src/server/auth.ts), [httpapi/middleware/authorization.ts](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/opencode/src/server/routes/instance/httpapi/middleware/authorization.ts), [httpapi/server.ts](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/opencode/src/server/routes/instance/httpapi/server.ts)
