import SwiftUI

/// The chat timeline's scroll container.
///
/// Owns the scroll position and turns `ViewportState`'s rules into commands.
/// The content stays a plain `LazyVStack`; streaming is unaffected. While
/// pinned the position is the bottom edge, which SwiftUI keeps stable across
/// content-size changes; when the reader scrolls away it becomes a fixed
/// point, which SwiftUI deliberately does not keep stable.
struct ChatViewport<Content: View>: View {
  @State private var position = ScrollPosition(idType: String.self)
  @State private var state = ViewportState()
  @State private var isUserDriven = false

  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 14) {
        content
      }
      .scrollTargetLayout()
      .padding()
    }
    .scrollPosition($position)
    // Bottom-align content that is shorter than the viewport (a chat opens at
    // the last message). Only the `alignment` role is set: size changes are
    // owned by `ViewportState`, not by the framework.
    .defaultScrollAnchor(.bottom, for: .alignment)
    .onScrollPhaseChange { _, phase in
      isUserDriven = phase == .interacting || phase == .decelerating
    }
    .onScrollGeometryChange(for: Geometry.self) { geometry in
      Geometry(
        offsetY: geometry.contentOffset.y,
        contentHeight: geometry.contentSize.height,
        containerHeight: geometry.containerSize.height
      )
    } action: { _, geometry in
      apply(
        state.reduce(
          offsetY: geometry.offsetY,
          contentHeight: geometry.contentHeight,
          containerHeight: geometry.containerHeight,
          isUserDriven: isUserDriven
        )
      )
    }
  }

  private func apply(_ effect: ViewportState.SideEffect) {
    switch effect {
    case .none:
      break
    case .pinToBottom:
      position.scrollTo(edge: .bottom)
    case .release(let offsetY):
      position.scrollTo(y: offsetY)
    }
  }

  private struct Geometry: Equatable {
    var offsetY: CGFloat
    var contentHeight: CGFloat
    var containerHeight: CGFloat
  }
}
