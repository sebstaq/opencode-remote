# Next steps

## Next: ChatGPT-like sidebar (reveal via window)

Goal: the sidebar opens by the chat sliding to the right and the sidebar being laid bare underneath it — not as an overlay on top of the chat. Reference: ChatGPT on iPhone (iOS 26), see `docs/sidebar-reveal.md`.

In short: ChatGPT runs the chat column in a **separate window** that is offset to the right and made the key window; the sidebar stays in the main window. The keyboard follows the key window, ends up inside the chat window and therefore does not cover the sidebar. See `docs/sidebar-reveal.md` for mechanism, evidence and plan.

1. Spike: minimal second window (UIWindow) for a text field + sidebar in the main window; verify on the iPhone simulator (iOS 26.2) that the keyboard ends up in the chat window.
2. If the spike holds: rebuild `ChatShell` into two windows — the sidebar in the main window (static), the chat in a child window whose frame = screen minus the sidebar width; key window and focus handled; dragging animates the chat window's frame.
3. Motion according to the transitions skill: panel open 400 ms / close 350 ms, `cubic-bezier(0.22, 1, 0.36, 1)`, reduce-motion guard. No resize, only translation.
4. Fallback if the spike fails: reveal in one window (chat offset, sidebar static) — the keyboard then becomes full-width and the sidebar's bottom row must sit above the keyboard.

## History

The MVP scope is locked (`DECISIONS.md`), the connection is specced (`connection.md`), the project is scaffolded (`structure.md`) and the app is built: connection layer, Add computer, session list, read-only chat **and composer with live streaming, abort, and approval/question overlays**. Remote distribution: signed IPA via Diawi (`scripts/diawi.sh`).
