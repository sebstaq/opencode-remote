# Client persistence

Everything the app keeps between launches goes through one store:
`App/Core/Preferences.swift`. One backend (UserDefaults), one schema, one way to
read and write:

```swift
prefs[.collapsedGroups] = ["api"]
```

Writes persist immediately (UserDefaults coalesces them). Reads are observable
through the `@Observable` store, so SwiftUI updates when a preference changes.

## Keys

| Key | Scope | Type | Default |
| --- | --- | --- | --- |
| `computers` | global | `[Computer]` | `[]` |
| `lastComputerID` | global | `String?` | `nil` |
| `selectedSession` | global | `SessionRow?` | `nil` |
| `collapsedGroups` | per computer | `Set<String>` | `[]` |
| `model` | per computer | `ModelChoice?` | `nil` |
| `agent` | per computer | `String?` | `nil` |

A **per computer** key is prefixed with the active computer’s id
(`prefs.computer.<id>.<name>`), so two machines that both have a project called
`api` never share collapse state, model choice or agent. The scope is the last
connected computer (`lastComputerID`).

## What does not belong here

Connection state, run status, session contents and an open sheet are
**ephemeral**. They are re-derived from the server on every launch, and a
reconnect is not a state to restore. Only *user choices* are persisted.

`selectedSession` is the exception that proves the rule: it is a user choice
(which conversation to have open), and the server validates it on load —
`ChatShell` clears it if the session is gone.

## Secrets

Passwords never touch this store. They stay in the Keychain, keyed by computer
id (`App/Core/Keychain.swift`). The computer list is in the store; the
credentials are not.

## Test isolation

- A UI test can pin a suite with `OPENCODE_UI_DEFAULTS_SUITE` and opt out of the
  reset with `OPENCODE_UI_PERSIST=1`; the restore suite uses both to observe
  persistence across a relaunch.
- Every other UI launch that sets `OPENCODE_E2E_URL` starts from a clean slate,
  so a prior run’s preferences can never leak into a test.

## Why not SQLite

The persistent UI state is a handful of key–value choices. UserDefaults is the
right tool; a database would add schema and migration cost with no benefit, and
would blur the line against the server-owned conversation history. A durable
local cache (message projection, outbox, last applied sequence) would be a
separate concern for offline support, not part of preferences.
