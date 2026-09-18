import Foundation

/// The stick-to-bottom state machine for the chat timeline.
///
/// Ported from `stackblitz-labs/use-stick-to-bottom` (MIT), which exists for
/// exactly this problem: AI output whose height grows unevenly while it
/// streams. The rules are:
///
/// - Start pinned to the bottom.
/// - While pinned, a content growth or a container shrink keeps the bottom in
///   view. The follow is driven by height — not by message or block counts,
///   because text growing inside one block must still keep the bottom.
/// - A user scroll away from the bottom releases the viewport; new content
///   must then not move it.
/// - Returning within `bottomThreshold` re-pins.
///
/// The reducer is free of SwiftUI so the edge cases are unit tested; the view
/// only performs the effect it returns.
struct ViewportState: Equatable {
  /// Distance from the bottom within which the viewport counts as pinned.
  /// Mirrors `STICK_TO_BOTTOM_OFFSET_PX` in the reference hook.
  static let bottomThreshold: CGFloat = 70

  private(set) var isPinnedToBottom = true
  private(set) var distanceFromBottom: CGFloat = 0
  private var contentHeight: CGFloat = 0
  private var containerHeight: CGFloat = 0

  var isNearBottom: Bool { distanceFromBottom <= Self.bottomThreshold }

  enum SideEffect: Equatable {
    case none
    /// Keep the bottom in view (the viewport commands an edge scroll to bottom).
    case pinToBottom
    /// Freeze the viewport at this offset so content growth cannot move it.
    case release(atOffsetY: CGFloat)
  }

  /// Feeds a scroll geometry update.
  ///
  /// - Parameter isUserDriven: whether the user is driving the scroll
  ///   (`ScrollPhase.interacting` / `.decelerating`), as opposed to a
  ///   programmatic scroll or an idle scroll view.
  mutating func reduce(
    offsetY: CGFloat,
    contentHeight: CGFloat,
    containerHeight: CGFloat,
    isUserDriven: Bool
  ) -> SideEffect {
    let didResize =
      contentHeight != self.contentHeight || containerHeight != self.containerHeight
    self.contentHeight = contentHeight
    self.containerHeight = containerHeight
    distanceFromBottom = max(0, contentHeight - containerHeight - offsetY)

    if isNearBottom {
      guard !isPinnedToBottom else { return .none }
      isPinnedToBottom = true
      return .pinToBottom
    }

    if isUserDriven {
      guard isPinnedToBottom else { return .none }
      isPinnedToBottom = false
      return .release(atOffsetY: offsetY)
    }

    // Programmatic or idle and away from the bottom: keep following a live
    // resize (the initial load, streaming growth, or the keyboard closing).
    return isPinnedToBottom && didResize ? .pinToBottom : .none
  }

  mutating func reset() {
    self = ViewportState()
  }
}
