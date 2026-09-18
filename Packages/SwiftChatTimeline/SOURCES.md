# Vendored: SwiftChat timeline

Source: <https://github.com/sachaservan/SwiftChat>
Pinned commit: `d6f54ccf9e84d2fec672b7b89d5a67dd6ee0f957` (main, 2026-03-30)
License: MIT, stated in the upstream README (the repository ships no LICENSE
file; see `SOURCES-LICENSE`).

The three files below are **byte-identical** to the upstream blobs at the
pinned commit. Verify with `scripts/vendor-swiftchat.sh`; it asserts both the
upstream fetch and the local file hash `git hash-object` equal the blob SHA.

| File (in `Sources/SwiftChatTimeline/`) | Upstream path | Blob SHA-1 |
| --- | --- | --- |
| `MessageTableView.swift` | `SwiftChat/Views/MessageTableView.swift` | `20463db8e594737160e3de030e4c54ed09ef103f` |
| `ChatListView.swift` | `SwiftChat/Views/ChatListView.swift` | `cf4f5993eb32b556ea192d279c6467051642ef2f` |
| `Constants.swift` | `SwiftChat/Config/Constants.swift` | `551dbb33380bd9092359df8c26696c19e9fca7e5` |

## Why a package

The donor mutates MainActor state from `@Sendable` closures (the keyboard
observers in `ChatListView`) and uses `DispatchQueue.main.async` inside
`ObservableMessageWrapper`. That does not compile under the app target's Swift 6
strict concurrency, and a language mode cannot be set per file. The timeline is
therefore its own module, compiled in Swift 5 mode (`.swiftLanguageMode(.v5)`),
so the donor source stays untouched while the app stays Swift 6 / complete.

## What we add around it (not part of the donor)

`TimelineSupport.swift` and `TimelineViews.swift` provide the interfaces the
donor file expects (`Message`, `ChatViewModel`, `SettingsManager`,
`Color.chatBackground`, `View.if`, `MessageView`, `WelcomeView`,
`MessageInputView`). `ChatTimeline.swift` is a thin public facade over the
donor's `ChatListView`, which is module-internal. None of these edit the donor
files; they are the extension points the library is designed around.
