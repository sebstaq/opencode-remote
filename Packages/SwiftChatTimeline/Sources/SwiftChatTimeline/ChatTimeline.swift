import SwiftUI

/// Public entry point over the vendored `ChatListView` (SwiftChat, MIT). The
/// donor file is used as-is; this only exposes it across the module boundary.
public struct ChatTimeline: View {
  let isDarkMode: Bool
  let isLoading: Bool
  @ObservedObject var viewModel: ChatViewModel
  @Binding var messageText: String

  public init(
    isDarkMode: Bool,
    isLoading: Bool,
    viewModel: ChatViewModel,
    messageText: Binding<String>
  ) {
    self.isDarkMode = isDarkMode
    self.isLoading = isLoading
    self.viewModel = viewModel
    self._messageText = messageText
  }

  public var body: some View {
    ChatListView(
      isDarkMode: isDarkMode,
      isLoading: isLoading,
      viewModel: viewModel,
      messageText: $messageText
    )
  }
}
