import SwiftUI

/// Semantic theme tokens, backed by asset-catalog color sets with explicit
/// Any/Dark variants (App/Assets.xcassets). The values mirror the reference
/// design: pure white/paper and true black ink in light, inverted near-black
/// surfaces in dark.
///
/// Never use raw `Color(...)`, system materials or `.quaternary`/`.bar`
/// outside this namespace — surfaces, fills and ink always come from here so
/// the two appearances stay a single design.
enum Theme {
  enum Color {
    static let surface = SwiftUI.Color("surface")
    static let ink = SwiftUI.Color("ink")
    static let inkSecondary = SwiftUI.Color("inkSecondary")
    static let fillUser = SwiftUI.Color("fillUser")
    static let fillSelected = SwiftUI.Color("fillSelected")
    static let fillComposer = SwiftUI.Color("fillComposer")
    static let fillInverted = SwiftUI.Color("fillInverted")
    static let line = SwiftUI.Color("line")
  }
}
