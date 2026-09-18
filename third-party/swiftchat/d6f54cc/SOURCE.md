# Vendored: SwiftChat timeline

Source: <https://github.com/sachaservan/SwiftChat>
Pinned commit: `d6f54ccf9e84d2fec672b7b89d5a67dd6ee0f957` (main, 2026-03-30)
License: MIT, stated in the upstream README (the repository ships no LICENSE
file; see `LICENSE` here).

The files below are **byte-identical** to the upstream blobs at the pinned
commit. Verify with `scripts/vendor-swiftchat.sh`; `git hash-object <file>` must
equal the blob SHA.

| File | Upstream path | Blob SHA-1 |
| --- | --- | --- |
| `MessageTableView.swift` | `SwiftChat/Views/MessageTableView.swift` | `20463db8e594737160e3de030e4c54ed09ef103f` |
| `ChatListView.swift` | `SwiftChat/Views/ChatListView.swift` | `cf4f5993eb32b556ea192d279c6467051642ef2f` |
| `Constants.swift` | `SwiftChat/Config/Constants.swift` | `551dbb33380bd9092359df8c26696c19e9fca7e5` |

## Derived code

`App/Features/ChatTable.swift` is adapted from `MessageTableView.swift`: it is a
`UITableView`-backed timeline with the donor's bottom math
(`contentSize.height - bounds.height + contentInset.bottom`), `willDisplay`
landing, drag cancellation and keyboard handling, but rendering our own
`MessageRow` and using `ChatMessage`. The donor's streaming buffer, archive
separator, dark mode and "user message to top" mode are dropped. Every
difference is recorded in `PATCH.diff` (regenerate with
`scripts/vendor-swiftchat.sh`).

This directory is not compiled (it is outside `App/`); it is the provenance
record.
