import SwiftUI

/// The donor timeline's message cell. It renders the row the app built into
/// `Message.row`; the timeline calls this through its intended extension point.
struct MessageView: View {
  let message: Message
  let isDarkMode: Bool
  let isLastMessage: Bool
  let isLoading: Bool
  let messageIndex: Int

  var body: some View {
    message.row
  }
}

/// The donor timeline's empty state; the app overlays its own placeholder.
struct WelcomeView: View {
  let isDarkMode: Bool

  var body: some View {
    EmptyView()
  }
}

/// The donor `ChatListView` composer slot, rendering the app's composer.
struct MessageInputView: View {
  @Binding var messageText: String
  @ObservedObject var viewModel: ChatViewModel
  let isKeyboardVisible: Bool

  var body: some View {
    viewModel.makeComposer()
  }
}
