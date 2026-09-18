# The chat viewport (scroll behaviour)

How the timeline scrolls. An AI answer whose height grows unevenly while it
streams must keep the bottom in view **only** while the reader is at the bottom,
must not yank a reader who scrolled up, and must open a restored thread at the
end in one step.

We build it ourselves, natively, from the ideas in
[`use-stick-to-bottom`](https://github.com/stackblitz-labs/use-stick-to-bottom)
(MIT, powers bolt.new). The hook is the de-facto solution for exactly this; its
core is small enough to adopt conceptually.

## Decision: iOS 18 minimum

`scrollPosition(id:)`, `onScrollGeometryChange` and `onScrollPhaseChange` are
the primitives used here and are all iOS 18. See `DECISIONS.md`.

## Shape

`ChatViewport` binds `scrollPosition(id:)` to the **identity of the last item**
(message or tail prompt). SwiftUI keeps that item visible across content-size
changes — that *is* the streaming follow. There are no per-frame scroll commands.

```
SessionTimeline (content: messages, prompts, composer)
└── ChatViewport(bottomID: tail?.id ?? lastMessage?.id)
    └── ScrollView + LazyVStack + scrollTargetLayout
        .scrollPosition(id: $scrolledID, anchor: .bottom)
```

The rules:

- **Start following.** On appear and whenever `bottomID` changes, target it.
- **Follow is free.** While the binding is the last item, growth keeps the
  bottom in view; a new message re-targets the new last item.
- **A user scroll away releases.** The binding moves to an earlier item, so we
  stop re-targeting; new content cannot move the view.
- **Reaching the last item resumes following** (`scrolledID == bottomID`).
- **Short content is bottom-aligned** with `defaultScrollAnchor(.bottom, for:
  .alignment)`.

## Why not a command-driven reducer

The first implementation used a `ViewportState` reducer plus
`ScrollPosition.scrollTo(edge:)` / `scrollTo(y:)` commands on every geometry
update. That was a regression, and it is worth recording why:

- Issuing a scroll command from inside `onScrollGeometryChange` produced
  *"tried to update multiple times per frame"* and could stall the main thread.
- Computing the distance as `contentSize - containerSize` ignored the
  composer's safe-area inset, and `ScrollGeometry.contentInsets` turned out to
  be unstable while streaming (it ranged 677 → 573 → 116).
- The edge/point commands fought content growth: after a release the view
  re-pinned itself, and `pinned` and the actual offset diverged.

Binding to the last item's identity avoids all three: no commands, inset-safe
bottom via the anchor, and the user's scroll is the source of truth for whether
we are following.

## Phases

**Fas 0 — decisions.** iOS 18, native, this document. *(done)*

**Fas 1 — the landing and the follow (this change).** `ChatViewport` bound to
the last item; release on scroll-away; re-pin on return. Removes
`.defaultScrollAnchor(.bottom)` and the `onChange … scrollToTail` hooks from
`SessionTimeline`.

**Fas 2 — streaming tests.** A deterministic streaming fixture and a VM test
suite that asserts: open at the bottom in one step, follow while pinned, no
movement while released, re-pin on return. The current verification is manual
(`scripts`/`/tmp` scripts on the VM) and must become a checked-in repeatable
suite. Verifying this on the macOS VM — not in CI — is the point: CI stays
offline.

**Fas 3 — robustness.** Investigate the content-height collapse seen during
streaming (`SessionChatModel.resync` replacing `messages` with a snapshot while
deltas are unpersisted). `ChatViewport` tolerates it, but the collapse is a
data-layer issue. Also: keyboard re-pin, permissions/tail prompts as growth,
very long threads.

**Fas 4 — polish (later).** Spring-follow, an "N new messages" pill, VoiceOver,
re-verifying on new iOS releases.

## Not doing (deliberately)

- Prepending older messages: the server returns the full history, no paging
  endpoint is used.
- A third-party chat/message UI: they solve human-to-human messaging, not
  uneven streaming growth.
- A local message database: the server is the source of truth.

## How to verify in the simulator

- Open a long thread: it must land at the end with the last line fully visible.
- Start a long streamed answer; scroll up while it streams: the view must not
  move. Scroll back to the bottom: it must follow again.
- On a debug build, `OPENCODE_UI_VIEWPORT_DEBUG=1` shows
  `scrolled=… bottom=… follow=…` so the state is observable from
  `axe describe-ui`.
