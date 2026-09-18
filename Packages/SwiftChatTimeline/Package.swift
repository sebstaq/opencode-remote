// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SwiftChatTimeline",
  platforms: [.iOS(.v17)],
  products: [
    .library(name: "SwiftChatTimeline", targets: ["SwiftChatTimeline"])
  ],
  targets: [
    .target(
      name: "SwiftChatTimeline",
      swiftSettings: [
        // The donor sources (SwiftChat's MessageTableView/ChatListView, MIT) are
        // vendored byte-identical and predate Swift 6 strict concurrency. The
        // module alone is compiled in Swift 5 mode so the donor code stays
        // untouched; the app target remains Swift 6 / complete.
        .swiftLanguageMode(.v5)
      ]
    )
  ]
)
