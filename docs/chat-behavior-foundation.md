# Chat behaviour foundation — the message list (Phase 1, broad pass)

Status: **draft for the Phase 1 gate** (see issue #57). Not requirements, not a design.
Date: 2026-09-19. Scope: how established AI chat clients behave around the message list.

## Purpose and limits

This records **observed behaviour** in named products, with a source for each claim. It contains no requirements, no product decisions and no design. Some behaviour is verified from a project's current source, docs, tests or issues; some is inferred; some could not be verified. Anything unverified is marked.

Confidence vocabulary:

- **Verified** — seen in current source, docs, tests, or an issue/PR.
- **Likely** — strongly indicated but not confirmed end to end.
- **Unverified** — reported or absent, not confirmed.

## Sources studied (broad pass)

T3 Code · Paseo · LibreChat · Vercel AI Chatbot · assistant-ui · HuggingFace Chat UI · Lobe Chat · Open WebUI · ChatViewportKit · FluidGroup messaging list · jcode · platform and accessibility guidance.

Note: "jcode" turned out to be **two unrelated projects** — `cnjack/jcode` (ships a reusable conversation-list library) and `1jehuang/jcode` (a terminal agent). Both were examined; the library is the relevant one for the message list.

## 1. Following the newest content while a reply is written

- **"At the bottom" is a product-specific band, not one value.** Observed thresholds span roughly 1 to 300 points: ~1 (assistant-ui), ~5 (Open WebUI), ~40 (T3 Code re-arm), ~50 (ChatViewportKit pin), ~60 (HuggingFace re-attach), ~70 (Vercel's sticky component), ~80 (jcode), ~100 (Vercel custom hook, FluidGroup), ~150 (LibreChat re-attach), ~300 (Lobe Chat). **Verified.**
- **Following happens only while the reader is at or near the bottom** in every product observed. **Verified.**
- **What counts as "new content" differs.** Some move on *any* content change while pinned (T3 Code, assistant-ui, Vercel, Lobe Chat); some move only on *discrete events* such as a whole message or the typing indicator appearing, not on in-place height growth of an existing row (FluidGroup). **Verified** (FluidGroup: verified for append/indicator; "no follow on in-place growth" **likely**).
- **Following may be continuous through a stream or event-based.** T3 Code follows paragraph-by-paragraph; assistant-ui/Lobe/Vercel react to each content change; Paseo re-anchors to the bottom on a content-size change while sticky. **Verified.**
- **Two send-time philosophies exist** (see §5): chase the newest text, or anchor the reader's own turn and let the reply fill below.

## 2. Detaching when the reader scrolls up

- **The more refined clients detach on a user *gesture*, not merely on geometry.** LibreChat detaches on an upward wheel immediately; T3 Code reacts to wheel, touch, pointer and keys; HuggingFace attributes a small upward drift (≥3 points) to a gesture and ignores browser-initiated movement; assistant-ui treats a decreasing scroll position (while content height is unchanged) as a user scroll-up; jcode releases its "bottom lock" on wheel-up, touch, keys and scrollbar drag. **Verified.**
- **Simpler clients detach on position alone, with documented failure.** Open WebUI cannot stop on small scrolls (issue #1195); Vercel's custom hook has no direction check, only a short "user is scrolling" window. **Verified.**
- **A deliberate scroll-up and a programmatic/layout movement must be separated.** HuggingFace moves its internal baselines synchronously when it scrolls programmatically, so its own movement reads as zero; LibreChat writes a baseline before every programmatic move; assistant-ui clears pending scroll intent on pointer-down. **Verified.**
- **Documented lessons and pitfalls:** a zero-height marker flickers and causes false attach/detach (LibreChat); observing a full-height wrapper instead of the growing content broke auto-scroll entirely (HuggingFace); a distance-based latch cannot tell a deliberate scroll from a layout reflow, so it can disable following for the rest of a stream (Open WebUI); re-snapping after the reader has scrolled away has been a recurring regression (assistant-ui issues). **Verified** (as reports).

## 3. Being off-bottom while content grows

- **The strong invariant: while detached, content growing below must not move what the reader is looking at.** All the refined clients enforce this; content is added off-screen and the viewport stays put. **Verified.**
- **Mechanisms:** bottom-anchoring that runs only while "sticky", with the offset left untouched while detached (Paseo); a "bottom lock" released on the reader's upward gesture so row growth cannot pull the view down (jcode); maintain-visible-content-position (T3 Code); freezing the visible anchor before a change (ChatViewportKit). **Verified.**
- **Reserved space / spacers** are used so a growing reply does not shove content: Lobe Chat uses a shrinkable spacer below the pinned user turn; HuggingFace reserves space so the reply can grow below the fold; assistant-ui uses a reserve element; T3 Code uses an anchored end space on the first send. **Verified.**

## 4. Jump-to-latest and re-attaching

- **Most products show a control when detached**, and hide it at the bottom: T3 Code "Scroll to end" (shown when away, reveal debounced ~150 ms); assistant-ui's control appears when scrolled up (its docs disagree on hidden vs disabled); Vercel's button is hidden at the bottom and shown otherwise; Lobe Chat has a jump control; ChatViewportKit leaves the button to the host but exposes a pin-state signal; FluidGroup documents an app-provided control when more than ~100 points away. **Verified.**
- **Activating it returns to the bottom and resumes following.** T3 Code sets the mode to "following-end" and re-enables live follow; Paseo switches to sticky and verifies the landing over several frames, retrying; ChatViewportKit scrolls to the true bottom and re-pins; HuggingFace, Vercel and LibreChat scroll and re-pin. **Verified.**
- **Following also resumes automatically** when the reader returns within the band (value varies, see §1), or on events such as a new run starting, sending, or switching conversation (varies by product). **Verified.**
- **Optional "unseen" context** on the control exists in some APIs (assistant-ui exposes a count); actual UI use **unverified**.

## 5. Where the view lands when a reply starts

- **Two clear philosophies:**
  - *Chase the newest text*: Paseo (default), Vercel, assistant-ui (default). **Verified.**
  - *Anchor the reader's own turn and let the reply grow below (a "read" mode)*: HuggingFace carries the view to the turn anchor and leaves it detached; Lobe Chat pins the just-sent user message to the top with a spacer below; T3 Code uses an anchored end space on the first send; assistant-ui offers this through a top turn-anchor mode. **Verified.**
- **Consequence:** in the anchoring products the view does not chase every streamed token; the reader sees their own message and reads the answer as it grows. **Verified.**

## 6. Switching conversations

- **No consensus.** HuggingFace always jumps to the bottom on switch and clears the reserved anchor; Vercel resets follow state on chat-id change; assistant-ui scrolls to the bottom on switch by default (can be disabled). Lobe Chat is the exception: it saves and restores a per-conversation position (only if saved within the last 5 minutes and not at the bottom), otherwise opens at the bottom. Paseo preserves a retained in-session reading position (~24 points) but resets to following when entering a different agent. **Verified** (Lobe, HuggingFace, Paseo); **likely** (Vercel, assistant-ui).
- **This is a product decision, not an established standard.**

## 7. Loading older history without jumps

- **Reader-driven:** older content loads when the reader scrolls near the top (Paseo, FluidGroup, jcode). **Verified.**
- **No-jump mechanisms:** a fixed virtual space so prepending extends content upward without changing the offset (FluidGroup); capturing the distance from the bottom and reconciling after layout (jcode); platform maintain-visible-content (Paseo); a mandatory "prepare to prepend" step that freezes the visible anchor before inserting (ChatViewportKit). **Verified.**
- **Fragility:** FluidGroup documents a regression where prepending/appending visibly shifted the view — the no-jump property is version-sensitive. ChatViewportKit documents 1–2 frames of the wrong position before snapping, and requires the prepare step or the view may jump. **Verified.**

## 8. Accessibly announcing new content

- **The message region is treated as an append-only log** whose new entries are announced politely (queued), without moving focus. **Verified** (guidance).
- **Rapid updates are an anti-pattern:** avoid announcing every streamed token; a queued/polite announcement fits streaming, while interrupting announcements are reserved for time-critical messages such as errors. **Verified** (principle); the exact "announce once on completion" rule is **not stated by the platform sources** — it is inferred.
- **Mechanisms:** an announcement notification; a layout-changed notification when visible layout changes; a trait marking elements that update too frequently to notify; a "busy" state during batch updates. **Verified** (documentation).
- **Gap:** no primary source quantifies a debounce cadence or a maximum announcement rate.

## Where the products disagree (the decisions we must make ourselves)

1. **What "at the bottom" means** — thresholds span roughly 1 to 300 points.
2. **Chase vs anchor on send** — chase the newest text, or hold the reader's turn.
3. **Follow in-place growth vs only discrete events** — react to any change, or only to new messages/indicators.
4. **Restore position on switch vs always open at the bottom.**
5. **Geometry vs gesture** for detecting a deliberate scroll-up.
6. **How much settling / how many frames** before trusting a landing.

## Gaps and unverified items

- **"jcode" is two projects** — `cnjack/jcode` (conversation-list library) and `1jehuang/jcode` (terminal agent). Both examined; the library is relevant.
- **Paseo licence** appears to have changed between older and current releases; unconfirmed.
- **T3 Code threshold history:** an ~80-point value cited earlier comes from a file removed in a later change; current behaviour uses a ~40-point re-arm band plus a mode model. Historical, not current.
- **ChatViewportKit:** its "correcting after data change" mode and anchor snapshot appear declared but unused; no conversation-switch behaviour found; very low adoption; no community discussion.
- **Restore-on-switch** for Vercel and assistant-ui is inferred, not explicit.
- **Several behaviours were read from active development branches** and may change; no version pins.
- **Platform HIG pages** were not directly fetchable; one guidance item came from a mirror (marked likely).
- **No runtime observation** — everything above comes from source, docs, tests and issues; the broad pass did not run any of these products.
