import Combine
import OpenCodeAPI
import PhotosUI
import SwiftChatTimeline
import SwiftStreamingMarkdown
import SwiftUI
import UIKit

struct SessionTimeline: View {
  let sessionID: String
  let client: Client
  let service: ConnectionService
  let runState: RunStateStore
  let generation: Int
  let isCurrent: @Sendable () async -> Bool

  @State private var model = SessionChatModel()
  @StateObject private var chatViewModel = ChatViewModel()
  @State private var composerText = ""
  @State private var expandedReasoning: Set<String> = []
  @State private var pendingUserScroll = false
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.colorScheme) private var colorScheme

  private var isStreaming: Bool {
    model.isRunning || model.streamingBlockID != nil
  }

  var body: some View {
    configure()
    return ChatTimeline(
      isDarkMode: colorScheme == .dark,
      isLoading: isStreaming,
      viewModel: chatViewModel,
      messageText: $composerText
    )
    .overlay { placeholder }
    // No `.id(sessionID)`: the timeline must persist across sessions so the
    // donor's own chat-switch detection (`currentChat?.createdAt`) and the
    // wrapper reset (`currentChat?.id`) actually run.
    #if DEBUG
      .overlay(alignment: .topLeading) {
        if ProcessInfo.processInfo.environment["OPENCODE_UI_VIEWPORT_DEBUG"] == "1" {
          Text(
            verbatim:
              "atBottom=\(chatViewModel.isAtBottom ? 1 : 0) "
              + "interacting=\(chatViewModel.isScrollInteractionActive ? 1 : 0)"
          )
          .font(.system(size: 9, design: .monospaced))
          .padding(4)
          .background(.yellow)
          .foregroundStyle(.black)
          .accessibilityIdentifier("viewport.probe")
        }
      }
    #endif
    .task(id: "\(sessionID)#\(generation)") {
      // Assume an already-used chat on switch (so the donor fades in and lands
      // at the bottom); `rebuildMessages` corrects this to the real blank state
      // when a genuinely empty session finishes loading, taking the other arm.
      chatViewModel.currentChat = TimelineChat(
        id: sessionID, createdAt: Date(), isBlankChat: false)
      chatViewModel.scrollToBottomTrigger = UUID()
      await model.run(
        client: client, sessionID: sessionID, service: service, runState: runState,
        isCurrent: isCurrent)
      rebuildMessages()
    }
    .onChange(of: model.messages) { _, _ in
      rebuildMessages()
      // The send path asks for the user's own message to be brought to the top
      // once its row actually exists (the donor input a regenerate action would
      // otherwise drive).
      if pendingUserScroll, model.messages.last?.role == .user {
        pendingUserScroll = false
        chatViewModel.scrollToUserMessageTrigger = UUID()
      }
    }
    .onChange(of: expandedReasoning) { _, _ in rebuildMessages() }
    .onChange(of: isStreaming) { _, value in
      chatViewModel.isLoading = value
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      Task { await model.resync(client: client, sessionID: sessionID) }
    }
  }

  /// Wires the composer the vendored timeline calls back into, capturing only
  /// values/references (never `self`).
  private func configure() {
    let model = self.model
    let client = self.client
    let sessionID = self.sessionID
    let pendingScroll = $pendingUserScroll

    chatViewModel.makeComposer = {
      AnyView(
        VStack(spacing: 0) {
          tailPrompts(model: model, client: client)
          // The donor timeline's own count handler does the initial scroll; this
          // send hook only marks that the user's next message should be brought
          // to the top once its row exists.
          TimelineComposer(model: model, client: client, sessionID: sessionID) {
            pendingScroll.wrappedValue = true
          }
          .background(Theme.Color.surface)
          .overlay(alignment: .top) {
            Rectangle().fill(Theme.Color.line).frame(height: 0.5)
          }
        }
      )
    }
  }

  /// Projects our messages into the timeline's `Message`, each carrying its
  /// prebuilt row.
  private func rebuildMessages() {
    let model = self.model
    let client = self.client
    let expanded = expandedReasoning
    let expandedBinding = $expandedReasoning
    let streamingBlockID = model.streamingBlockID
    let lastAssistantID = model.messages.last(where: { $0.role == .assistant })?.id
    let streamError = model.error

    // Keep the donor's chat descriptor in step with reality: a session switch
    // (new id) and the first content arriving (blank flips) each change
    // `createdAt`, which is what drives `ChatListView`'s blank/fade branch.
    let blank = model.messages.isEmpty
    if chatViewModel.currentChat?.id != sessionID
      || (chatViewModel.currentChat?.isBlankChat ?? true) != blank
    {
      chatViewModel.currentChat = TimelineChat(
        id: sessionID, createdAt: Date(), isBlankChat: blank)
    }

    chatViewModel.messages = model.messages.map { message in
      var text: [String] = []
      var thoughts: [String] = []
      var thinkingIDs: [String] = []
      for block in message.blocks {
        switch block.kind {
        case .text(let value):
          text.append(value)
        case .reasoning(let value):
          thoughts.append(value)
          thinkingIDs.append(block.id)
        default:
          break
        }
      }
      return Message(
        id: message.id,
        role: message.role == .user ? .user : .assistant,
        content: text.joined(separator: "\n"),
        thoughts: thoughts.isEmpty ? nil : thoughts.joined(separator: "\n"),
        contentChunks: message.blocks.map(\.id),
        thinkingChunks: thinkingIDs,
        isThinking: streamingBlockID.map { id in
          message.blocks.contains { $0.id == id }
        } ?? false,
        isCollapsed: !expanded.contains(message.id),
        // This app has no per-message generation timing, so the donor's field
        // stays at its default; the error is projected onto the last assistant.
        generationTimeSeconds: nil,
        streamError: message.id == lastAssistantID ? streamError : nil,
        row: AnyView(
          MessageRow(
            message: message,
            model: model,
            prompts: model.inlinePrompts(for: message.id),
            streamingBlockID: model.streamingBlockID,
            expanded: expanded.contains(message.id),
            onToggleReasoning: {
              if expandedBinding.wrappedValue.contains(message.id) {
                expandedBinding.wrappedValue.remove(message.id)
              } else {
                expandedBinding.wrappedValue.insert(message.id)
              }
            },
            onPermission: { request, decision in
              Task { await model.reply(permission: request, decision: decision, client: client) }
            },
            onAnswer: { request, names in
              Task { await model.answer(question: request, answers: [names], client: client) }
            },
            onReject: { request in
              Task { await model.reject(question: request, client: client) }
            }
          )
          .equatable()
        )
      )
    }
  }

  @ViewBuilder
  private var placeholder: some View {
    if model.messages.isEmpty && model.permissions.isEmpty && model.questions.isEmpty {
      if let error = model.error {
        ContentUnavailableView(
          "Couldn't load messages",
          systemImage: "exclamationmark.triangle",
          description: Text(error)
        )
      } else if model.didLoad {
        ContentUnavailableView(
          "No messages yet",
          systemImage: "bubble.left.and.bubble.right",
          description: Text("Write an instruction to start.")
        )
      } else {
        ProgressView()
      }
    }
  }

}

/// The thread-tail prompts, shown just above the composer. A file-scope
/// function (not a view method) so the composer closure does not capture the
/// view and retain the chat view model.
@MainActor
@ViewBuilder
private func tailPrompts(model: SessionChatModel, client: Client) -> some View {
  ForEach(model.tailPrompts) { prompt in
    PromptView(
      prompt: prompt,
      onPermission: { request, decision in
        Task { await model.reply(permission: request, decision: decision, client: client) }
      },
      onAnswer: { request, names in
        Task { await model.answer(question: request, answers: [names], client: client) }
      },
      onReject: { request in
        Task { await model.reject(question: request, client: client) }
      }
    )
    .padding(.horizontal, 12)
    .padding(.bottom, 8)
  }
}

// MARK: - Message row

/// One message. `Equatable` so SwiftUI skips re-rendering a row whose content
/// did not change — only the row receiving the current stream re-renders per
/// flush.
private struct MessageRow: View, Equatable {
  let message: ChatMessage
  let model: SessionChatModel
  let prompts: [InlinePrompt]
  let streamingBlockID: String?
  let expanded: Bool
  let onToggleReasoning: () -> Void
  let onPermission: (PermissionRequest, PermissionDecision) -> Void
  let onAnswer: (QuestionRequest, [String]) -> Void
  let onReject: (QuestionRequest) -> Void

  nonisolated static func == (lhs: MessageRow, rhs: MessageRow) -> Bool {
    lhs.message == rhs.message
      && lhs.prompts == rhs.prompts
      && lhs.expanded == rhs.expanded
      && lhs.streamingBlockID == rhs.streamingBlockID
  }

  var body: some View {
    VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
      ForEach(message.blocks) { block in
        blockView(block)
        promptViews(after: block)
      }
      ForEach(unmatchedPrompts) { prompt in
        promptView(prompt)
      }
    }
    .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
  }

  /// The card belongs to its tool call: render it directly under the matching
  /// block, in message order, not at the end of the thread.
  private func promptViews(after block: ChatBlock) -> some View {
    let callID = block.toolCallID
    return ForEach(prompts.filter { callID != nil && $0.callID == callID }) { prompt in
      promptView(prompt)
    }
  }

  /// Defensive fallback: a prompt whose call no longer has a block (e.g. the
  /// message was reloaded without it) still shows, right after the message.
  private var unmatchedPrompts: [InlinePrompt] {
    let blockCallIDs = Set(message.blocks.compactMap(\.toolCallID))
    return prompts.filter { prompt in
      guard let callID = prompt.callID else { return true }
      return !blockCallIDs.contains(callID)
    }
  }

  @ViewBuilder
  private func promptView(_ prompt: InlinePrompt) -> some View {
    PromptView(
      prompt: prompt,
      onPermission: onPermission,
      onAnswer: onAnswer,
      onReject: onReject
    )
  }

  @ViewBuilder
  private func blockView(_ block: ChatBlock) -> some View {
    switch block.kind {
    case .text(let text):
      switch message.role {
      case .user:
        Text(text)
          .padding(.horizontal, 12)
          .padding(.vertical, 9)
          .background(Theme.Color.fillUser, in: RoundedRectangle(cornerRadius: 18))
      case .assistant:
        if model.streamingBlockID == block.id, let source = model.streamSource(for: block.id) {
          StreamedMarkdownView(source: source, config: Self.documentConfig)
        } else {
          MarkdownView(text: text, config: Self.documentConfig)
        }
      }
    case .reasoning(let text):
      ReasoningBlockView(
        text: text,
        isStreaming: model.streamingBlockID == block.id,
        expanded: expanded,
        model: model,
        blockID: block.id,
        onToggle: onToggleReasoning
      )
    case .tool(let presentation, _):
      ToolCallRow(presentation: presentation)
    case .image(_, let dataURL, _):
      AttachmentImageView(dataURL: dataURL)
        .frame(maxWidth: 280)
    case .file(let name, _):
      HStack(spacing: 6) {
        Image(systemName: "doc")
        Text(name).lineLimit(1)
      }
      .font(.footnote)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .overlay(
        RoundedRectangle(cornerRadius: 10).stroke(Theme.Color.line)
      )
    case .marker(let text):
      if !text.isEmpty {
        Text(text).font(.caption2).foregroundStyle(Theme.Color.inkSecondary)
      }
    }
  }

  private static let documentConfig = MarkdownRenderConfig(
    blockQuoteStyle: .init(textFonts: DocFonts.body, textColor: Theme.Color.ink),
    headingStyle: .init(
      h1Font: DocFonts.heading.h1, h2Font: DocFonts.heading.h2, h3Font: DocFonts.heading.h3,
      h4Font: DocFonts.heading.h3, h5Font: DocFonts.heading.h3, h6Font: DocFonts.heading.h3,
      textColor: Theme.Color.ink),
    orderedListStyle: .init(textFonts: DocFonts.body, textColor: Theme.Color.ink),
    paragraphStyle: .init(textFonts: DocFonts.body, textColor: Theme.Color.ink),
    inlineStyle: .init(
      boldTextColor: Theme.Color.ink,
      linkTextFont: DocFonts.body.normal,
      linkTextColor: Theme.Color.ink,
      codeTextFont: DocFonts.mono.normal,
      codeTextColor: Theme.Color.ink,
      codeBackgroundColor: Theme.Color.fillComposer,
      codeUnderlineColor: Theme.Color.line
    ),
    codeBlockConfig: CodeBlockConfig(
      theme: .grayscale,
      backgroundColor: Theme.Color.fillComposer,
      foregroundColor: Theme.Color.ink
    ),
    blockSpacing: 10
  )
}

// MARK: - Attachment

/// Decodes the `data:` URL of an image part once and renders it. Decoding is
/// deferred to `.task` so a large payload does not run during layout.
private struct AttachmentImageView: View {
  let dataURL: String
  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .clipShape(RoundedRectangle(cornerRadius: 14))
      } else {
        RoundedRectangle(cornerRadius: 14)
          .fill(Theme.Color.fillComposer)
          .frame(height: 120)
          .overlay(ProgressView())
      }
    }
    .task(id: dataURL) {
      image = AttachmentImageDecoder.decode(dataURL)
    }
    .accessibilityIdentifier("timeline.image")
  }
}

// MARK: - Reasoning

/// Collapsed by default (a UX default, not a performance mechanism). Expanded,
/// the still-streaming block renders inside a capped-height live region so the
/// page layout does not shift on every flush; once the block closes it renders
/// as a settled markdown document.
private struct ReasoningBlockView: View {
  let text: String
  let isStreaming: Bool
  let expanded: Bool
  let model: SessionChatModel
  let blockID: String
  let onToggle: () -> Void

  @State private var follow = true

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button(action: onToggle) {
        HStack(spacing: 6) {
          Image(systemName: expanded ? "chevron.up" : "chevron.down")
            .font(.caption2.bold())
          Text(isStreaming ? "Thinking…" : "Thought process")
            .font(.footnote.bold())
          if isStreaming {
            ProgressView()
              .controlSize(.small)
          }
        }
        .foregroundStyle(Theme.Color.inkSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.Color.fillComposer, in: RoundedRectangle(cornerRadius: 10))
      }
      .accessibilityIdentifier("reasoning.toggle")

      if expanded {
        liveRegion
      }
    }
  }

  @ViewBuilder
  private var liveRegion: some View {
    if isStreaming, let source = model.streamSource(for: blockID) {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            StreamedMarkdownView(source: source, config: Self.reasoningConfig)
              .id("reasoning-tail")
            Color.clear.frame(height: 1).id("reasoning-bottom")
          }
        }
        .frame(height: 340)
        .overlay(alignment: .topTrailing) {
          if !follow {
            Button {
              follow = true
              withAnimation {
                proxy.scrollTo("reasoning-bottom", anchor: .bottom)
              }
            } label: {
              Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.Color.fillInverted)
            }
            .padding(8)
            .accessibilityIdentifier("reasoning.jump")
          }
        }
        .simultaneousGesture(
          DragGesture().onChanged { _ in follow = false }
        )
        .onChange(of: text.count) {
          guard follow else { return }
          proxy.scrollTo("reasoning-bottom", anchor: .bottom)
        }
        .onAppear {
          proxy.scrollTo("reasoning-bottom", anchor: .bottom)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .overlay(
        RoundedRectangle(cornerRadius: 10).stroke(Theme.Color.line)
      )
    } else if !isStreaming {
      MarkdownView(text: text, config: Self.reasoningConfig)
    } else {
      // Expanded before any flush landed; keep the region reserved.
      Color.clear.frame(height: 1)
    }
  }

  private static let reasoningConfig = MarkdownRenderConfig(
    blockQuoteStyle: .init(textFonts: DocFonts.small, textColor: Theme.Color.inkSecondary),
    headingStyle: .init(
      h1Font: DocFonts.heading.h3, h2Font: DocFonts.heading.h3, h3Font: DocFonts.heading.h3,
      h4Font: DocFonts.heading.h3, h5Font: DocFonts.heading.h3, h6Font: DocFonts.heading.h3,
      textColor: Theme.Color.inkSecondary),
    orderedListStyle: .init(textFonts: DocFonts.small, textColor: Theme.Color.inkSecondary),
    paragraphStyle: .init(textFonts: DocFonts.small, textColor: Theme.Color.inkSecondary),
    inlineStyle: .init(
      boldTextColor: Theme.Color.inkSecondary,
      linkTextFont: DocFonts.small.normal,
      linkTextColor: Theme.Color.inkSecondary,
      codeTextFont: DocFonts.mono.normal,
      codeTextColor: Theme.Color.inkSecondary,
      codeBackgroundColor: Theme.Color.fillComposer,
      codeUnderlineColor: Theme.Color.line
    ),
    codeBlockConfig: CodeBlockConfig(
      theme: .grayscale,
      backgroundColor: Theme.Color.fillComposer,
      foregroundColor: Theme.Color.inkSecondary
    ),
    blockSpacing: 10
  )
}

/// A prompt rendered at its tool call (or in the thread tail when it has none).
private struct PromptView: View {
  let prompt: InlinePrompt
  let onPermission: (PermissionRequest, PermissionDecision) -> Void
  let onAnswer: (QuestionRequest, [String]) -> Void
  let onReject: (QuestionRequest) -> Void

  var body: some View {
    switch prompt {
    case .permission(let value):
      PermissionCardView(prompt: value) { decision in
        onPermission(value.request, decision)
      }
    case .question(let value):
      QuestionCard(
        prompt: value,
        onAnswer: { onAnswer(value.request, $0) },
        onReject: { onReject(value.request) }
      )
    }
  }
}

/// A permission rendered inline at its tool call. Pending shows the choices;
/// once answered it stays as a short record instead of disappearing.
private struct PermissionCardView: View {
  let prompt: PermissionPrompt
  let onDecide: (PermissionDecision) -> Void

  private var isPending: Bool { prompt.decision == nil && !prompt.resolved }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(prompt.request.permission).font(.footnote.bold())
      if !prompt.request.patterns.isEmpty {
        Text(prompt.request.patterns.joined(separator: ", "))
          .font(.caption)
          .foregroundStyle(Theme.Color.inkSecondary)
          .lineLimit(2)
      }
      if isPending {
        HStack(spacing: 8) {
          Button("Deny", role: .destructive) { onDecide(.reject) }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("permission.deny")
          Button("Always") { onDecide(.always) }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("permission.always")
          Button("Allow once") { onDecide(.once) }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("permission.allow")
        }
      } else {
        HStack(spacing: 6) {
          Image(systemName: prompt.decision == .reject ? "xmark.circle" : "checkmark.circle")
            .font(.caption)
          Text(resolution).font(.caption)
        }
        .foregroundStyle(Theme.Color.inkSecondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Theme.Color.fillSelected, in: RoundedRectangle(cornerRadius: 14))
  }

  private var resolution: String {
    guard let decision = prompt.decision else { return "Resolved" }
    switch decision {
    case .once: return "Allowed once"
    case .always: return "Always allowed"
    case .reject: return "Denied"
    }
  }
}

/// A pending question as a timeline item. Owns its selection state so several
/// can be outstanding at once without sharing a draft.
private struct QuestionCard: View {
  let prompt: QuestionPrompt
  let onAnswer: ([String]) -> Void
  let onReject: () -> Void

  @State private var chosen: Set<String> = []
  @State private var custom = ""

  private var answered: Bool { prompt.answered || prompt.skipped }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(prompt.request.header).font(.footnote.bold())
      Text(prompt.request.question).font(.footnote)
      if answered {
        HStack(spacing: 6) {
          Image(systemName: prompt.skipped ? "arrow.uturn.backward.circle" : "checkmark.circle")
            .font(.caption)
          Text(prompt.skipped ? "Skipped" : "Answered").font(.caption)
        }
        .foregroundStyle(Theme.Color.inkSecondary)
      } else {
        ForEach(prompt.request.options, id: \.label) { option in
          Button {
            select(option.label)
          } label: {
            HStack {
              Image(systemName: chosen.contains(option.label) ? "checkmark.circle.fill" : "circle")
              VStack(alignment: .leading) {
                Text(option.label)
                if let description = option.description {
                  Text(description).font(.caption).foregroundStyle(Theme.Color.inkSecondary)
                }
              }
              Spacer()
            }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("question.option")
        }
        if prompt.request.custom {
          TextField("Your answer", text: $custom)
            .textFieldStyle(.roundedBorder)
        }
        HStack {
          Button("Skip") { reject() }
            .buttonStyle(.bordered)
          if prompt.request.multiple {
            Button("Send") { answer() }
              .buttonStyle(.borderedProminent)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Theme.Color.fillSelected, in: RoundedRectangle(cornerRadius: 14))
  }

  private func select(_ label: String) {
    if prompt.request.multiple {
      if chosen.contains(label) { chosen.remove(label) } else { chosen.insert(label) }
    } else {
      chosen = [label]
      answer()
    }
  }

  private func answer() {
    var names = Array(chosen)
    let extra = custom.trimmingCharacters(in: .whitespacesAndNewlines)
    if !extra.isEmpty { names.append(extra) }
    chosen = []
    custom = ""
    onAnswer(names)
  }

  private func reject() {
    chosen = []
    custom = ""
    onReject()
  }
}
