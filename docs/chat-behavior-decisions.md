# Chat behaviour decisions

Status: living record. Decided items become the product spec (Phase 2). The un-answered list is in `chat-behavior-open-questions.md`; the evidence base is in `chat-behavior-foundation.md` and `chat-behavior-deep-pass.md`.

## Batch 1 — The bottom and the follow state (A1–A12)

**D1. "At the bottom" is defined by a distance band from the end of the content.** Not a marker element. Rationale: simplest and testable, and what established clients use; a marker-based rule is fragile when heights change.

**D2. The re-arm band is about 40 points, with a separate tight "exact bottom" used for landing.** Rationale: a tight band causes false detach during growth; a generous one feels loose.

**D3. Detaching is governed by intent (a gesture); re-attaching is governed by the band.** Asymmetric hysteresis. Rationale: an intentional scroll-up is respected immediately; returning close enough re-attaches.

**D4. When the content is shorter than the viewport, it counts as at the bottom, and the content is pinned to the bottom.** Rationale: nothing is below to read.

**D5. Short content sits at the bottom (the newest content is at the bottom).** Rationale: chat-like, and the first message does not jump when it arrives.

**D6. The band scales with accessibility text size, and loosely with viewport height.** Rationale: a fixed band is too small at large text sizes.

**D7. Following is an explicit, small state set — following, anchored, detached — not a boolean.** Rationale: most scroll defects come from an implicit boolean; explicit states are testable.

**D8. Our follow state expresses intent; the measured scroll position is input, never cached as the truth.**

**D9. System-initiated movements are not treated as reader intent; they are compensated for while detached.**

**D10. A detached view is never moved without an explicit action (send, open a conversation, jump-to-latest).** Following while already pinned is not "forcing".

**D11. Follow intent survives keyboard show/hide, rotation and app backgrounding; geometry is recomputed on resize.**

**D12. On a viewport resize mid-stream: stay following if it was following; otherwise stay put.**

## Batch 2 — Sending a message (B13–B25)

**D13. On send, the reader's own message is anchored near the top and the reply grows below ("read mode"); the view does not chase the newest text.**

**D14. The anchored reader message sits a fixed offset below the top (about 50 points).**

**D15. If the reader's own message is taller than the viewport, its top is shown and the reserved space is clamped so the reply's start stays reachable.**

**D16. Sending always moves the view to the sent message, even if the reader was reading history far above.** Sending is an explicit action (see D10).

**D17. The view moves immediately on send (optimistic), before the server confirms.**

**D18. If the send fails, the view stays at the sent message, which is marked failed with a retry; the view does not move.**

**D19. A failed message stays inline as a failed turn and does not change following.**

**D20. The reader's message is shown immediately (optimistic), with no pending state.**

**D21. Sending dismisses the keyboard.** The resulting resize must not move a detached view (D9/D12).

**D22. The composer does not keep focus after sending.**

**D23. Deferred — pending queue and "steer" semantics against the API.** What happens on two rapid sends cannot be decided until the API's queue/steer handling is known. Tracked as an open item.

**D24. While waiting for the reply, show an ellipsis-style indicator (e.g. "…") at the end of the thread — not a text label; the view stays on the sent message.**

**D25. If the reader sends while detached, the view moves to their new message.** Consistent with D16.

### Deferred / open items from Batch 2

- **D23** — two rapid sends: blocked on how the API handles queue and steer.
