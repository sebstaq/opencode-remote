import SwiftUI

/// The chat timeline's scroll container.
///
/// Instead of driving the scroll with commands, it binds `scrollPosition(id:)`
/// to the **identity of the last item**. SwiftUI then keeps that item visible
/// across content-size changes, which is exactly the streaming follow: as text
/// grows or a new item is appended, the bottom stays in view with no per-frame
/// scroll commands (those caused a "multiple updates per frame" loop).
///
/// When the reader scrolls away, the binding moves to an earlier item and we
/// stop re-targeting the bottom, so new content cannot move the view. Reaching
/// the last item again resumes following.
struct ChatViewport<Content: View>: View {
  /// Identity of the last item (message or tail prompt). `nil` while empty.
  let bottomID: String?

  @State private var scrolledID: String?
  @State private var isFollowing = true

  private let content: Content

  init(bottomID: String?, @ViewBuilder content: () -> Content) {
    self.bottomID = bottomID
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
    .scrollPosition(id: $scrolledID, anchor: .bottom)
    // Bottom-align content that is shorter than the viewport (a chat opens at
    // the last message).
    .defaultScrollAnchor(.bottom, for: .alignment)
    .onAppear { followIfNeeded() }
    .onChange(of: bottomID) { _, _ in followIfNeeded() }
    .onChange(of: scrolledID) { _, id in
      // The binding changes both when we target the bottom and when the reader
      // scrolls. Reaching the last item resumes following; anything else means
      // the reader took over.
      guard let id else { return }
      isFollowing = id == bottomID
    }
    #if DEBUG
      .overlay(alignment: .topLeading) {
        if ProcessInfo.processInfo.environment["OPENCODE_UI_VIEWPORT_DEBUG"] == "1" {
          let debugText =
            "scrolled=\(scrolledID ?? "-") bottom=\(bottomID ?? "-") "
            + "follow=\(isFollowing ? 1 : 0)"
          Text(verbatim: debugText)
          .font(.system(size: 9, design: .monospaced))
          .padding(4)
          .background(.yellow)
          .foregroundStyle(.black)
          .accessibilityIdentifier("viewport.probe")
        }
      }
    #endif
  }

  private func followIfNeeded() {
    guard isFollowing, let bottomID else { return }
    scrolledID = bottomID
  }
}
