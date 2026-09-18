# The chat viewport (scroll behaviour)

How the timeline scrolls. The problem is deceptively hard: an AI answer whose
height grows unevenly while it streams must keep the bottom in view **only**
while the reader is at the bottom, must not yank a reader who scrolled up, and
must open a restored thread at the end in one step.

We build it ourselves, natively, ported from the production-proven
[`use-stick-to-bottom`](https://github.com/stackblitz-labs/use-stick-to-bottom)
(MIT, powers bolt.new, ~600k downloads/week). That hook is the de-facto
solution for exactly this, and its core is small enough to translate. The
React/ResizeObserver mechanics map 1:1 onto iOS 18's scroll APIs.

## Decision: iOS 18 minimum

`onScrollGeometryChange`, `onScrollPhaseChange` and `ScrollPosition` — the
offset, phase and command primitives the viewport needs — are all iOS 18.
There is no clean iOS 17 path that keeps `LazyVStack`; a `UIScrollView` bridge
would cost laziness and add hosting complexity. We raised the minimum to iOS 18
(see `DECISIONS.md`).

## Shape

```
SessionTimeline (content: messages, prompts, composer)
└── ChatViewport                 # owns the scroll mechanics only
    ├── ViewportState            # pure reducer: pinned / released
    ├── ScrollView + LazyVStack  # unchanged content, MessageRow.equatable()
    └── position: ScrollPosition # edge .bottom while pinned, point while released
```

`ViewportState` is free of SwiftUI so the edge cases are unit tested. The view
only performs the effect the reducer returns (`pinToBottom` or `release`).
Streaming stays in `SessionChatModel`; the viewport is orthogonal to it.

## The rules (ported)

- **Start pinned.** Content growth/container shrink keeps the bottom in view.
- **Follow is driven by height, not by message/block count.** Text growing
  inside one block must still keep the bottom; `blocks.count` does not change
  there, which is why the previous `onChange` missed it.
- **A user scroll away from the bottom releases.** New content must not move
  the view. Released means the position is a point, which SwiftUI does not keep
  stable across content-size changes.
- **Returning near the bottom (≤ 70 pt) re-pins.** The threshold is the same
  as the reference hook's `STICK_TO_BOTTOM_OFFSET_PX`.
- **Keyboard is a container resize.** Pinned stays pinned; released stays put.

## Phases

**Fas 0 — decisions.** iOS 18, native, this document. *(done)*

**Fas 1 — the landing (this change).** `ChatViewport` + `ViewportState`; open at
the bottom in one step; follow on height change; releasing so a reader is never
yanked. Old code removed: `.defaultScrollAnchor(.bottom)` and the three
`onChange … scrollToTail` hooks (`SessionTimeline.swift`).

**Fas 2 — streaming safety.** Explicit user/programmatic distinction via
`ScrollPhase`, the "jump to latest" affordance, keyboard re-pin, and a
streaming E2E (the offline suite cannot stream yet).

**Fas 3 — robustness.** `resync`/`load` replacing `messages` (hold bottom when
pinned, preserve the visible message when released), tail prompts as growth,
short/empty threads, Reduce Motion.

**Fas 4 — polish (later).** Velocity spring instead of instant follow, an
"N new messages" pill, `turnAnchor="top"` exploration, VoiceOver, re-verifying
on new iOS releases.

## Not doing (deliberately)

- Prepending older messages: the server returns the full history, no paging
  endpoint is used. The "prepend without jump" problem is therefore moot.
- A third-party chat/message UI: they solve human-to-human messaging, not
  uneven streaming growth, and would take over our row model and theme.
- A local message database. The server is the source of truth.

## Verifying

- Unit: `ViewportState` transitions (pin, release, re-pin, threshold, resize).
- Manual/simulator: record a restore against a long thread and confirm the
  first content frame already sits at the tail (no animated second scroll).
- Performance: `scripts/vm/measure-stream.sh` frame-drop numbers must not
  regress.
