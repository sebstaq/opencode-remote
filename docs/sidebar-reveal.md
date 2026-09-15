# Sidebar reveal (ChatGPT-like)

Status: **behaviour decided 2026-09-15 (see the spec below). The previous
drawer/edge-swipe/child-window implementation is rejected and will be reworked.**
Reference: ChatGPT on iPhone (iOS 26), screenshot `IMG_2354.png`.

## Behaviour spec (decided)

This is the source of truth for how the sidebar behaves. The code must follow this
spec; any deviation is a bug unless it is a native iOS convention (home indicator,
safe areas, status bar).

### Surfaces

- **Chat solo** (sidebar closed): full screen, timeline scrolls freely, composer
  pinned at the bottom, standard iOS keyboard. No surprises.
- **Sidebar open**: the sidebar takes ~**85 %** of the screen width and lies
  *underneath* the chat. The chat slides right and appears as a clipped, rounded
  card with a soft shadow (the visual "sidebar underneath, chat on top" signal).
  Only a narrow strip of the chat column stays visible.

### Opening and closing

- **Open**: sidebar (hamburger) button, **and** edge-swipe from the left edge.
- **Close**: tapping anywhere on the (shifted, clipped) chat card, dragging the
  chat back, or the sidebar button again.
- The chat card is **non-interactive** while the sidebar is open: taps close the
  sidebar, nothing else. Timeline gestures must never swallow scrolling in the
  closed state — this is the regression to guard against.

### Keyboard rules

- Opening the sidebar while the keyboard is up **dismisses the keyboard first**,
  then the chat slides. One motion, no colliding animations.
- Sidebar + keyboard open simultaneously **cannot occur**: the sidebar has no text
  field. New session and settings open as sheets above everything; the keyboard
  inside those sheets is standard iOS behaviour.
- Returning to the chat: the chat becomes the key surface again; the keyboard
  returns when the composer is tapped.

### Motion

- Panel open 400 ms / close 350 ms, `cubic-bezier(0.22, 1, 0.36, 1)`
  (`--ease-smooth-out`), reduce-motion = instant.
- **Pure translation only** — no resize, no reflow. Scroll position and composer
  width are preserved exactly.
- The full-width keyboard during reveal is accepted; keyboard-follows-chat parity
  (custom input keyboard) is **deferred** — see history below.

### Streaming

- Streaming continues undisturbed while the sidebar opens/closes. No special cases.

### Scope

- Portrait, iPhone only. No iPad, no responsive variants.

## Reference material

- `docs/reference/chatgpt-sidebar-flow.mp4` — screen recording of the ChatGPT flow
  (kept locally, not committed).
- `docs/reference/frames/sidebar-open-keyboard.png` + `-zoom.png` — the decisive
  state: sidebar open, chat as a narrow clipped column on the right.

## History (do not build on this)

The original approach (child `UIWindow` per chat column, keyboard-follow via
key-window) was spiked 2026-09-14 and **does not work on iPhone/iOS 26**: the
system keyboard follows the scene, not the key window, and cannot be moved by the
app. See the git history of the original repository for the spike details
(`docs/reference/frames`, `App/Debug/SidebarWindowSpike.swift` remain as evidence).
The decided spec above intentionally accepts the full-width keyboard fallback
instead of pursuing custom-keyboard parity.
