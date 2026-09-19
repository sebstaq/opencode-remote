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
