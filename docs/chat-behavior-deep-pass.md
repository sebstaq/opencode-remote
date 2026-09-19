# Chat behaviour foundation — deep pass (6 sources)

Status: **draft for the Phase 1 gate** (see issue #57). Companion to `chat-behavior-foundation.md`.
Deep pass over: T3 Code · Paseo · LibreChat · HuggingFace Chat UI · jcode · ChatViewportKit.
Behaviour only, plain English. No requirements, no design.

## T3 Code

- Three modes for the list: following the end · anchoring a just-sent first message · free scrolling (detached).
- Re-attaching uses a band of about 40 points above the true end, deliberately wider than an exact-end test, so a growing stream does not have to be chased.
- Detaching needs an actual navigation gesture. For touch/pointer/keys it only detaches once the view is already beyond the ~40-point band; an upward wheel detaches whenever there is scrollable content above.
- Hysteresis is asymmetric (wider to re-arm, exact to leave).
- Only the **first** user message of a conversation is anchored at the top with reserved space; follow-up sends stay at the real bottom.
- Composer growth is deliberately excluded from end-following, so it does not move already-visible messages (the newest line can end up under the composer until the reader scrolls).
- Above-viewport changes are absorbed by a maintain-visible-content behaviour; it is restricted during expand/collapse toggles so only the toggled row is held.
- Momentum is modelled as a user scroll session (drag start through momentum end); only scroll events inside a session can break following, so its own compensations never strand a follower.
- Conversation switching: the reading position is remembered per conversation (last 100), including the row, offset, whether it was at the end, and which blocks were expanded; a conversation left mid-thread restores that exact position, one left at the end opens at the bottom. In the other client variant it always opens at the bottom.
- Older history loads from an explicit "Load earlier turns" control (not by scrolling to the top), plus when navigating to a message outside the loaded window.
- Jump-to-latest appears when the reader is away from the live edge (show debounced ~150, hide immediate); it never moves the view by itself; activating it scrolls to the end, re-arms follow and releases the send anchor.
- Lessons: re-arming follow must also release the send-time reserved space, or nothing actually follows; the first-message anchor must be released when tool activity appears, or a full page of blank reserved space can show.

## Paseo

- Two layers: a shared bottom-anchor controller with modes `sticky-bottom` / `detached`, and per-client follow thresholds.
- One client: leaves following at ~64 points from the bottom, re-attaches only within ~1 point; detaches only with direct upward input evidence (upward wheel, upward touch drag, upward keys, scrollbar press); scroll deltas alone never detach.
- Other client: near-bottom is ~32 points; detaching requires the drag/momentum to end away from the bottom; a deliberate away-move of ~24 points overrides an unverified layout revision; re-attaches when a user scroll ends near the bottom.
- Hysteresis is asymmetric (roughly 64/1 in one client, 32/24 in the other).
- Above-viewport change: one client captures the oldest visible row's offset before prepending and corrects each frame until stable; the other relies on visible-content maintenance (disabled while sticky in one environment, where it fights the offset correction).
- Conversation switching: a newly opened conversation anchors to the bottom; a retained conversation preserves the reading position when the layout is unchanged; entering a different agent resets to sticky.
- Older history: triggers when within ~96 points of the history start, as a small state machine (dormant → ready → loading → settling → latched); one page per threshold crossing; re-arms only after leaving and returning, or when a loaded page still leaves the viewport at the start.
- Jump-to-latest: appears when the reader is not near the bottom **or** when the server has newer rows not yet loaded — two different "detached" meanings share one control. Activation loads the tail first when the server is ahead, then scrolls.
- Edge: no unread count is shown; the exact reading position is not shown to survive an app relaunch.

## LibreChat

- A single binary "riding" state is the authority for following the stream.
- Detach is directional, not positional: an upward move past ~24 points releases the ride even if the reader is still close to the bottom.
- Re-attach happens on arrival: moving down and landing within ~150 points of the end re-arms. Asymmetric hysteresis (attach far, detach near).
- A looser ~120-point "near bottom" is kept only for resize-follow.
- Content-area growth (not viewport change) triggers following; the bottom is written directly per growth frame.
- Tapping or pressing a key inside message content suppresses the next growth-follow, so expanding a tool result is not mistaken for streaming.
- Momentum is inferred from consecutive scroll positions (covers wheel, trackpad and dragged scrollbar).
- Programmatic movement is separated by recording the position it left at before judging direction, and by not seeding a fake first sample.
- Conversation switching: a conversation opens at its newest message **only if** the "auto-scroll to latest on open" preference is on — the default is off, so it opens at the **start** of the conversation. No position is saved or restored.
- Older history: the transcript does not paginate; the whole conversation is fetched, then rows mount progressively around the anchor as a rendering optimisation. The first mounted row is re-pinned when rows are inserted above.
- Jump-to-latest: appears when the end-of-thread marker leaves the viewport (debounced ~150), if the preference is on (default on); one smooth jump (throttled ~750) that also re-attaches the ride.
- Edge: a momentum flick that settles back at the bottom can stay detached; the ~24-point detach is sensitive.

## HuggingFace Chat UI

- Two states only: following (glued to the bottom, moves with growth) and detached (parked, never moves on its own). The state is decided by where positions land, not by which input produced them.
- Detach after ~3 points of accumulated upward movement; any upward scroll event counts.
- Re-attach when a downward move enters the last ~60 points; also re-attaches when the view is clamped to the bottom because content shrank.
- Read mode after send: sending lands the view detached with the sent message ~50 points below the top; the reply streams into reserved blank space and its growth does **not** move the view until the reader re-engages.
- While following, growth is answered with an instant one-frame snap; easing is used only for explicit moves (send, jump buttons, re-attach catch-up).
- Reduced motion and hidden/backgrounded states turn every move instant.
- Intent is attributed geometrically, with no timers or position queues: a programmatic move either lands exactly at the bottom or begins by explicitly detaching.
- Above-viewport change while detached is compensated by the environment's own anchoring and is not read as reader intent; a gestureless upward move within ~120 ms of a content change is treated as the engine's own clamp and undone, while on a quiet page it is treated as navigation and detaches.
- Conversation switching: always opens at the bottom and follows; the previous position is deliberately not remembered. Opening a conversation that is mid-stream adopts the streaming anchor and keeps following; reload behaves like open.
- Older history: none — the whole conversation loads at once.
- Jump-to-latest: appears when detached and more than ~200 points from the bottom, hides at ~60 points or below (sticky band in between); activating it glides, continuously re-reading the target so it never lands short; long jumps teleport near then glide. A companion jump-to-previous lands the nearest earlier user message ~50 points below the top and stays detached.
- Lessons: per-token auto-scroll was deliberately removed after complaints; collapsing reasoning once shifted a reader by a measured ~267 points; one environment lacks native above-viewport anchoring, so a detached reader can be shifted when content above shrinks.

## jcode (the conversation-list library)

- At-bottom is a single geometric threshold of ~80 points; a separate "bottom lock" starts armed on a fresh list and re-pins to the true bottom on every height re-measure until an explicit upward gesture releases it.
- Release: upward wheel/trackpad, **any** touch move, upward keys, or a pointer-down in the scrollbar gutter. Re-arm when a downward-leaning gesture reaches the bottom (or on touch/pointer release while within ~80).
- Streaming follow is a second, independent rule: on each content change it scrolls to the bottom only if geometrically at bottom, otherwise it leaves the view alone.
- No resize or on-screen-keyboard handling in the list: while armed, any height change re-pins; while released, nothing moves.
- No older-history pagination: the whole transcript is fetched once.
- No jump-to-latest control at all — a detached reader has no way back except scrolling down manually.
- Conversation switching always lands at the newest content; never restores a position (the view is unmounted behind a loading state, so all scroll state resets).
- Edge: any touch movement releases following (very sensitive); a fling that settles short stays detached; overlay scrollbars defeat the gutter release; the non-virtualised variant has no lock and no initial pin.

## ChatViewportKit

- Three reachable states: initial-bottom-anchored, pinned-to-bottom, free-browsing — decided by a single ~50-point threshold with no hysteresis and no directional logic.
- Underfilled content (shorter than the viewport) is forced pinned regardless of position.
- Appends auto-scroll only if the viewport was pinned when the item count changed; a row growing or streaming in place does **not** pull the viewport down.
- Three declared states are effectively dead: the "correcting after data change" mode is never entered, the anchor snapshot is never populated, and the programmatic-scroll state is only used by one variant's far-jump probing.
- Keyboard/resize: re-pins if pinned; leaves a free-browsing view untouched.
- Above-viewport height changes get no compensating adjustment except for an explicitly signalled prepend; the configuration flags for preserving position are declared but never read.
- Momentum is not distinguished from an active drag; de-pinning/re-pinning can occur mid-momentum.
- No per-conversation position memory or restore; replacing the content leaves the viewport where it was.
- Older history: the host must decide when to load and must signal before inserting; the declared trigger offset is never read. Known: a 1–2 frame window where the position is wrong before correction; prepending while pinned does not jump to the newest content.
- Jump-to-latest: the library exposes only a pin-state boolean, a callback and a distance; the host renders the control. The pin signal can momentarily report "unpinned" during programmatic movement, so a naive binding may flash.
- Lessons: far-jump accuracy is poor with variable row heights (lands 10–60 rows off most of the time, occasionally 300+); several documented configuration values have no effect.

## Refined, cross-cutting facts

- **Thresholds cluster into four bands:** very tight (~1–5), moderate (~24–40), generous (~60–100), loose (~150–300). There is no standard.
- **The refined clients detach on a gesture or a direction, not on position alone.** The simpler ones detach on position and carry documented false-detach/mis-attach failures.
- **Growth handling differs:** some snap instantly on every growth (HuggingFace), some animate while streaming (T3 Code), some only move on discrete new items and ignore in-place growth (ChatViewportKit, FluidGroup).
- **Anchoring to the reader's turn on send ("read mode") is a deliberate, growing pattern** (HuggingFace, Lobe Chat, T3 Code first send, one assistant-ui mode). The opposite also exists: LibreChat force re-attaches and glides to the newest word on send.
- **Position restore on switch is rare:** only T3 Code (per conversation, last 100) and Paseo (retained, in-session) do it; HuggingFace, jcode and ChatViewportKit never restore; LibreChat opens at the start of the conversation by default.
- **Older history is not universal:** several products load the whole conversation at once (HuggingFace, jcode, LibreChat) or require an explicit control (T3 Code); Paseo auto-loads near the top.
- **Most products have a jump-to-latest control; jcode deliberately has none.**
- **A "server has newer rows" state can exist separately from "the reader scrolled away"** (Paseo), and both can share one control.
- **Composer growth is a known source of trouble:** one product deliberately excludes it from end-following; another awaits keyboard dismissal before re-pinning.

## New product decisions surfaced by the deep pass (beyond the earlier six)

- Does the reader's own send always mean "go to the newest content", or can it anchor their message and leave the view detached?
- Should composer growth move already-visible messages, or never?
- When opening a conversation, is the default the start of the conversation or the newest message?
- Should a "server has newer rows" state be shown differently from "the reader scrolled away"?
- Should expanded/collapsed blocks (reasoning, tools) be restored together with the saved position?
- Restore a reading position per conversation, and for how long, or never?
- Older history: automatic on scrolling up, an explicit control, or load everything at once?
- Should the jump-to-latest control exist at all, and if so with an unread count?
- What is the exact reduced-motion mapping?
