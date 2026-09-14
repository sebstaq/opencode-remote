# Sidebar reveal (ChatGPT-like)

Status: **spike run 2026-09-14 — a child window is not enough.** Reference: ChatGPT on
iPhone (iOS 26), screenshot `IMG_2354.png`.

## Reference material

- `docs/reference/chatgpt-sidebar-flow.mp4` — screen recording of the whole flow
  (19.7 s, 1180×2556, 60 fps).
- `docs/reference/frames/flow-0*.png` — contact prints, 4 fps.
- `docs/reference/frames/sidebar-open-keyboard.png` + `-zoom.png` — the decisive
  state: sidebar open, the chat as a narrow column on the right, keyboard visible.

What the recording shows: the whole chat panel — composer **and keyboard** — is
offset to the right and clipped by the screen edge; we only see its left ~25 %. The
sidebar stands still and its bottom row (chat pill + gear) is untouched. The chat has
a rounded bottom-left corner. This is ChatGPT's native app on iPhone (iOS 26).

## The keyboard: measured and exhausted (2026-09-14)

Several attempts, all with a screenshot as evidence:

1. Chat in a child `UIWindow` with `frame.x = 330` → the keyboard reports
   `screen x=0 w=393`, i.e. full width. It follows the scene, not the key window.
2. The scene cannot be made non-fullscreen on iPhone: windowed apps are iPadOS
   26-only, and `UIRequiresFullScreen` is ignored for iOS apps.
3. The keyboard's window cannot be reached: the app's scene only exposes
   `UIWindow` (x0), `UIWindow` (x330) and `UITextEffectsWindow` (L1.0) — no
   `UIRemoteKeyboardWindow`. A transform on `UITextEffectsWindow` took (x330 in
   diagnostics) but did not move the keyboard: it is rendered outside the app's
   process.

Conclusion: the system keyboard cannot be moved by the app on iPhone/iOS 26. The only
path to the reference's behaviour is a **custom input keyboard** (`inputView`) drawn
inside the chat panel — then we own the position completely. That is a large build and
loses system features (dictation, layouts). The alternative is to accept full width
and place the sidebar's bottom row above the keyboard.

## Spike results (2026-09-14)

Ran `OPENCODE_UI_SPIKE=window` (`App/Debug/SidebarWindowSpike.swift`): sidebar in the
main window, chat in a child `UIWindow` with `frame.x = 330`, on the iPhone simulator
iOS 26.2 (w1).

- **The chat window landed correctly**: the column sits correctly offset to the right
  of the sidebar, with rounded left corners.
- **The keyboard did not follow**: it is still full-width and covers the lower part of
  the sidebar. It follows the **scene**, not the key window we created.

Conclusion: a child window with an inserted frame is not the mechanism on iPhone. The
next hypothesis is that the **scene itself** must be non-fullscreen (windowed app /
requested scene geometry), which ChatGPT would then be using. If iOS 26 does not
allow that on iPhone, the reference is built with a custom input keyboard, and then
the practical fallback is single-window reveal with the sidebar's bottom row above
the keyboard.

## The goal

The sidebar should not be placed over the chat. When you pull it in, the **chat
slides to the right** and the sidebar is laid bare underneath it — the sidebar stands
still (as if it lay underneath the chat), the chat is a clipped, rounded card with a
shadow, and the **keyboard follows the chat** so it does not cover the sidebar.

## Why it works (the mechanism)

The keyboard is positioned relative to **the key window that has focus**, not the
screen:

- Apple's documentation: the keyboard's frame lies in the screen's coordinate system
  and differs when the app is not fullscreen (Split View, Slide Over, Stage Manager);
  the keyboard layout guide is "sized for what part of the keyboard is over your
  app's window" when the app is not alone on the screen.
- Apple Developer Forums, *"Chaotic keyboard frame notification in windowed app in
  iOS 26"* (Sep 2025): the keyboard's frame reports a negative `origin.x` (e.g.
  −247) and sometimes a **positive** `origin.x` — "as if the keyboard starts from
  the middle of the screen". That is exactly the reference's behaviour.

Conclusion: ChatGPT runs the chat column in its own window that is offset to the
right and made the key window. The sidebar stays in the main window. Therefore the
keyboard ends up inside the chat window and does not cover the sidebar.

## Plan

1. **Spike**: minimal second window (UIWindow) with a text field, sidebar in the
   main window, on the iPhone simulator (iOS 26.2). Verify that the keyboard ends up
   in the chat window and that the sidebar is untouched.
2. If the spike holds: rebuild `ChatShell`: the sidebar in the main window (static),
   the chat in a child window whose frame = screen minus the sidebar width. Handle
   key window and focus. Dragging animates the chat window's frame/transform.
3. Motion according to `transitions-dev`/`transitions-polish`: panel open 400 ms,
   close 350 ms, `cubic-bezier(0.22, 1, 0.36, 1)` (`--ease-smooth-out`),
   reduce-motion guard. No resize — only translation, so scroll position and composer
   width are preserved.
4. Fallback if the spike fails: reveal in one window (chat `offset(x:)`, sidebar
   static). The keyboard then becomes full-width and the sidebar's bottom row must
   sit above the keyboard instead.

## Risks

- iOS 26's keyboard frame in windowed mode is reported as flaky (negative x,
  sometimes height 0). Must not become a precondition for our layout.
- UIKit window layering under SwiftUI: key window and focus, plus UI tests across two
  windows.
- Current UI tests assume one window and that the sidebar only exists when open.

## Prerequisite: the software keyboard in the simulator

Verified 2026-09-14. The keyboard shows only in the **GUI user's** Simulator (here
`w1`), because `com.apple.iphonesimulator` is that user's plist. Recipe:

```bash
ssh w1@localhost \
  'plutil -replace ConnectHardwareKeyboard -bool NO \
     ~/Library/Preferences/com.apple.iphonesimulator.plist'
```

Per device: `DevicePreferences.<UDID>.ConnectHardwareKeyboard`. Then verify with
`defaults read com.apple.iphonesimulator ConnectHardwareKeyboard` (should be `0`),
boot the device in w1's Simulator, focus a text field — the software keyboard
appears.
