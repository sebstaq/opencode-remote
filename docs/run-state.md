# Run state: one store, one reconcile

Sessions can be running (busy), retrying, or idle. That single fact drives two
surfaces — the sidebar's spinner and the composer's stop button — and it used to
be tracked twice, differently, which made them drift apart: a spinner or a stop
button could stay "active" long after the run had finished.

## The rule

`GET /session/status` is **complete for the active set**: it lists exactly the
sessions that are busy or retrying, and a session disappears from it when it goes
idle (`session/status.ts` deletes the entry). Therefore:

> A session is idle **iff** it is absent from `GET /session/status`.

The snapshot is authoritative; events are only fast deltas. Reconciling means
*replacing* the state with the snapshot, including the sessions that are no
longer there.

## The model

- **`RunStateStore`** (`App/Core/RunState.swift`) — an `@Observable` map of
  `sessionID → RunState { idle, busy, retry }`. Absent reads as `.idle`.
  `reconcile(active:)` takes the full active set and replaces the state;
  `set(_:for:)` applies one event. It is the single source of truth.
- **`SessionActivityModel`** (`App/Core/SessionActivityModel.swift`) — the only
  writer of server-derived state. It owns the status subscription and a periodic
  `reconcile` (10 s), also triggered on subscribe and on foreground. One instance
  per connection generation.
- **Consumers** read the store and never keep their own copy:
  - the sidebar (`SessionsSidebar`) renders `state(for: row.id)`;
  - the chat (`SessionChatModel.isRunning`) derives the composer's stop/send.

Because there is one writer and one value, the sidebar and the composer cannot
disagree.

## Why this replaces the old approach

The previous design merged the snapshot into each surface's own state and only
for sessions *present* in the map. An idle session is absent, so a missed
`session.idle` event could never be corrected — the 15 s "self-heal" could
confirm busy but never clear it. Two independent merges (chat and sidebar) meant
two places to get it wrong. `RunStateStore.reconcile` treats absence as idle, so
any missed event self-corrects within one interval, on both surfaces at once.

## Server side (separate follow-up)

If the provider stream hangs with no timeout, the server never leaves `busy`, so
no reconcile can help. That needs a stream timeout / error on the server; it is
out of scope for the client.

## Tests

- `Tests/UnitTests/RunStateStoreTests` — absence means idle, empty snapshot
  clears, `set`/`reconcile` transitions, status mapping.
- `Tests/UITests/SessionIndicatorE2ETests` — offline fixture shows the spinner
  for the seeded active rows; live (`OPENCODE_UI_INDICATOR_LIVE=1`) asserts a row
  goes running then back to idle.
- `Tests/UITests/ComposerLiveE2ETests` — a fresh session is idle; the stop button
  clears when a run finishes.
