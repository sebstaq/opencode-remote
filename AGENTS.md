# Project working rules

## Direction

We are building a native iPhone client in Swift/SwiftUI for an existing OpenCode installation. Full agent usage and a good mobile interface is the goal. Tailscale is accepted initially, and a custom backend is only added when a concrete requirement justifies it.

## Documentation

- Read `README.md`, `docs/DECISIONS.md` and `docs/NEXT_STEPS.md` before new product or architecture decisions.
- `docs/DECISIONS.md` separates settled decisions from proposals and open questions.
- `docs/research/` is the dated research base with primary sources. Source-code findings are not proof of a run integration.
- Document new decisions and test results where they belong. Do not move a proposal to decided without support in the user's instructions.

## Implementation and verification

The repo starts as documentation; no app, Xcode configuration or iPhone verification exists yet. Set up a normal Swift/Xcode project structure with relevant build and test commands before implementing features. Do not introduce an agent engine, a custom conversation database or a generic middle layer without a verified need.

Verify which OpenCode runtime/API is actually supported. Do not mix legacy API routes with the experimental V2 contract. Keep the server as the source of truth for conversations and run status; distinguish disconnection from aborted execution.

## Motion and transitions

- When transitions or animations are in play (view switches, modals, dropdowns, status changes, list openings): use the checked-in skill in `.agents/skills/transitions-dev` (source: https://transitions.dev/skill), and keep durations and movement according to its scale. `.agents/skills/transitions-polish` is used to align motion we already have.
- The skill is web-oriented (CSS/React). In SwiftUI we translate the principles and the token scale, not the code verbatim.

## UI parity and diff

- When the user asks to compare or fix the interface against the design: run `scripts/ui-diff.sh` and report the SSIM number plus the overlay. The tool builds the app, takes a simulator screenshot and renders the wireframe in a WKWebView on the VM, so fonts and metrics become 1:1 comparable.
- The reference is always `docs/wireframes/index.html`, rendered by the tool (`scripts/ui/render-wireframe.swift`). Never use other screenshots or previously pasted images as the reference.
- The diff measures only the design: the sidebar is fed the wireframe's sample content via the DEBUG fixture `OPENCODE_UI_FIXTURE=wireframe` (`SidebarFixtureView`). Do not touch the fixture's content when adjusting the design.
- Accept only deviations that are native iOS convention or environment (e.g. home indicator, rounded corners, status bar contents), and keep them few. Adjust SwiftUI measurements against the wireframe's CSS measurements, but trust what WebKit actually renders (e.g. line height) rather than DOM numbers.
- The software keyboard shows in the simulator only in the GUI user's Simulator (`w1`) and requires `ConnectHardwareKeyboard=0` in `~/Library/Preferences/com.apple.iphonesimulator.plist` (`plutil -replace ConnectHardwareKeyboard -bool NO …`, per device `DevicePreferences.<UDID>.ConnectHardwareKeyboard`). Headless `simctl` as another user shows no keyboard. See `docs/sidebar-reveal.md`.

## Workflow

- Prefix shell commands with `rtk`.
- Work on a separate branch and publish finished changes via a review-ready pull request.
- Do not change the user's OpenCode, network or Tailscale configuration as a consequence of a documentation task.
- Never put credentials, private conversations, real session identifiers or APNs keys in the repo, logs or test fixtures.
- Keep reporting brief and clearly separate completed verification from planned checks.
