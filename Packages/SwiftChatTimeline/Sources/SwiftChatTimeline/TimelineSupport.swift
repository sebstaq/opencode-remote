import Foundation
import SwiftUI

/// The model interface the vendored SwiftChat timeline consumes. `content`,
/// `thoughts` and the chunk arrays are the donor's change-detection keys; `row`
/// is the app's prebuilt row view for this message.
public struct Message: Identifiable {
  public enum Role {
    case user
    case assistant
  }

  public let id: String
  public var role: Role
  public var content: String
  public var thoughts: String?
  public var contentChunks: [String]
  public var thinkingChunks: [String]
  public var isThinking: Bool
  public var isCollapsed: Bool
  public var generationTimeSeconds: Double?
  public var streamError: String?
  public let row: AnyView

  public init(
    id: String,
    role: Role,
    content: String,
    thoughts: String?,
    contentChunks: [String],
    thinkingChunks: [String],
    isThinking: Bool,
    isCollapsed: Bool,
    generationTimeSeconds: Double?,
    streamError: String?,
    row: AnyView
  ) {
    self.id = id
    self.role = role
    self.content = content
    self.thoughts = thoughts
    self.contentChunks = contentChunks
    self.thinkingChunks = thinkingChunks
    self.isThinking = isThinking
    self.isCollapsed = isCollapsed
    self.generationTimeSeconds = generationTimeSeconds
    self.streamError = streamError
    self.row = row
  }
}

/// The donor's `currentChat` interface.
public struct TimelineChat: Equatable {
  public let id: String
  public let createdAt: Date
  public let isBlankChat: Bool

  public init(id: String, createdAt: Date, isBlankChat: Bool) {
    self.id = id
    self.createdAt = createdAt
    self.isBlankChat = isBlankChat
  }
}

/// The donor's `ChatViewModel` interface, backed by the app.
@MainActor
public final class TimelineChatViewModel: ObservableObject {
  @Published public var messages: [Message] = []
  @Published public var currentChat: TimelineChat?
  @Published public var isLoading = false
  @Published public var isBottom = false
  @Published public var isAtBottom = false
  @Published public var isScrollInteractionActive = false
  @Published public var scrollToBottomTrigger = UUID()
  @Published public var scrollToUserMessageTrigger = UUID()

  /// The app's composer, rendered by the donor's `MessageInputView` slot.
  public var makeComposer: @MainActor () -> AnyView = { @MainActor in AnyView(EmptyView()) }

  public init() {}
}

/// The app refers to the adapter as `ChatViewModel`; the donor uses the same
/// name, and `SwiftChat.ChatViewModel` in its source.
public typealias ChatViewModel = TimelineChatViewModel

public enum SwiftChat {
  public typealias ChatViewModel = TimelineChatViewModel
}

/// The donor's `SettingsManager` interface (only `maxMessages` is read).
@MainActor
public final class SettingsManager: ObservableObject {
  public static let shared = SettingsManager()
  @Published public var maxMessages = 75
  private init() {}
}

public extension Color {
  /// The donor resolves this from the passed flag; the app themes its own rows,
  /// but the timeline background still honors dark mode here.
  static func chatBackground(isDarkMode: Bool) -> Color {
    isDarkMode ? Color(white: 0.11) : Color(white: 0.98)
  }
}

public extension View {
  @ViewBuilder
  func `if`<Transformed: View>(
    _ condition: Bool,
    transform: (Self) -> Transformed
  ) -> some View {
    if condition {
      transform(self)
    } else {
      self
    }
  }
}
