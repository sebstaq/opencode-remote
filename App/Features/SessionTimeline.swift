import OpenCodeAPI
import SwiftStreamingMarkdown
import SwiftUI

struct SessionTimeline: View {
  let sessionID: String
  let client: Client
  let service: ConnectionService
  let generation: Int
  let isCurrent: @Sendable () async -> Bool

  @State private var model = SessionChatModel()
  @State private var draft = ""
  @State private var chosen: Set<String> = []
  @State private var custom = ""
  @State private var expandedReasoning: Set<String> = []
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          ForEach(model.messages) { message in
            MessageRow(
              message: message,
              model: model,
              streamingBlockID: model.streamingBlockID,
              expanded: expandedReasoning.contains(message.id),
              onToggleReasoning: { toggleReasoning(message.id) }
            )
            .equatable()
            .id(message.id)
          }
        }
        .padding()
      }
      // Open the thread at the newest message: content is anchored at the
      // bottom, so a long conversation starts at the end — no animated
      // traversal from the top (and LazyVStack only materialises the last
      // screenful).
      .defaultScrollAnchor(.bottom)
      .overlay { placeholder }
      .onChange(of: model.messages.last?.blocks.count ?? 0) {
        if let last = model.messages.last {
          withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(last.id, anchor: .bottom)
          }
        }
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 0) {
        if let request = model.permission {
          permissionBanner(request)
        }
        if let request = model.question {
          questionBanner(request)
        }
        composer
      }
      .background(Theme.Color.surface)
      .overlay(alignment: .top) {
        Rectangle()
          .fill(Theme.Color.line)
          .frame(height: 0.5)
      }
    }
    .task(id: "\(sessionID)#\(generation)") {
      #if DEBUG
        // Lets UI tests exercise send/abort without the simulator keyboard.
        if let seed = ProcessInfo.processInfo.environment["OPENCODE_UI_DRAFT"], draft.isEmpty {
          draft = seed
        }
      #endif
      await model.run(client: client, sessionID: sessionID, service: service, isCurrent: isCurrent)
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      Task { await model.resync(client: client, sessionID: sessionID) }
    }
  }

  private func toggleReasoning(_ messageID: String) {
    if expandedReasoning.contains(messageID) {
      expandedReasoning.remove(messageID)
    } else {
      expandedReasoning.insert(messageID)
    }
  }

  @ViewBuilder
  private var placeholder: some View {
    if model.messages.isEmpty {
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

  // MARK: - Composer

  private var composer: some View {
    HStack(spacing: 10) {
      TextField("Write an instruction…", text: $draft, axis: .vertical)
        .lineLimit(1...5)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Theme.Color.fillComposer, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("composer.field")

      if model.isRunning {
        Button {
          Task { await model.abort(client: client, sessionID: sessionID) }
        } label: {
          Image(systemName: "stop.circle.fill")
            .font(.system(size: 30))
            .foregroundStyle(Theme.Color.fillInverted)
        }
        .accessibilityIdentifier("composer.stop")
      } else {
        Button {
          send()
        } label: {
          Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: 30))
            .foregroundStyle(Theme.Color.fillInverted)
        }
        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("composer.send")
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  private func send() {
    let text = draft
    draft = ""
    Task { await model.send(client: client, sessionID: sessionID, text: text) }
  }

  // MARK: - Permission and questions

  private func permissionBanner(_ request: PermissionRequest) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(request.permission)
        .font(.footnote.bold())
      if !request.patterns.isEmpty {
        Text(request.patterns.joined(separator: ", "))
          .font(.caption)
          .foregroundStyle(Theme.Color.inkSecondary)
          .lineLimit(2)
      }
      HStack(spacing: 8) {
        Button("Deny", role: .destructive) { decide(request, .reject) }
          .buttonStyle(.bordered)
          .accessibilityIdentifier("permission.deny")
        Button("Always") { decide(request, .always) }
          .buttonStyle(.bordered)
          .accessibilityIdentifier("permission.always")
        Button("Allow once") { decide(request, .once) }
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("permission.allow")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Theme.Color.fillSelected, in: RoundedRectangle(cornerRadius: 14))
    .padding(.horizontal, 12)
    .padding(.top, 8)
  }

  private func decide(_ request: PermissionRequest, _ decision: PermissionDecision) {
    Task {
      await model.reply(permission: request, decision: decision, client: client)
    }
  }

  private func questionBanner(_ request: QuestionRequest) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(request.header).font(.footnote.bold())
      Text(request.question).font(.footnote)
      ForEach(request.options, id: \.label) { option in
        Button {
          select(request, option.label)
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
      if request.custom {
        TextField("Your answer", text: $custom)
          .textFieldStyle(.roundedBorder)
      }
      HStack {
        Button("Skip") { rejectQuestion(request) }
          .buttonStyle(.bordered)
        if request.multiple {
          Button("Send") { answerQuestion(request) }
            .buttonStyle(.borderedProminent)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Theme.Color.fillSelected, in: RoundedRectangle(cornerRadius: 14))
    .padding(.horizontal, 12)
    .padding(.top, 8)
  }

  private func select(_ request: QuestionRequest, _ label: String) {
    if request.multiple {
      if chosen.contains(label) { chosen.remove(label) } else { chosen.insert(label) }
    } else {
      chosen = [label]
      answerQuestion(request)
    }
  }

  private func answerQuestion(_ request: QuestionRequest) {
    var names = Array(chosen)
    let extra = custom.trimmingCharacters(in: .whitespacesAndNewlines)
    if !extra.isEmpty { names.append(extra) }
    chosen = []
    custom = ""
    Task { await model.answer(question: request, answers: [names], client: client) }
  }

  private func rejectQuestion(_ request: QuestionRequest) {
    chosen = []
    custom = ""
    Task { await model.reject(question: request, client: client) }
  }
}

// MARK: - Message row

/// One message. `Equatable` so SwiftUI skips re-rendering a row whose content
/// did not change — only the row receiving the current stream re-renders per
/// flush.
private struct MessageRow: View, Equatable {
  let message: ChatMessage
  let model: SessionChatModel
  let streamingBlockID: String?
  let expanded: Bool
  let onToggleReasoning: () -> Void

  nonisolated static func == (lhs: MessageRow, rhs: MessageRow) -> Bool {
    lhs.message == rhs.message
      && lhs.expanded == rhs.expanded
      && lhs.streamingBlockID == rhs.streamingBlockID
  }

  var body: some View {
    VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
      ForEach(message.blocks) { block in
        blockView(block)
      }
    }
    .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
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
    case .tool(let name, let status):
      HStack(spacing: 8) {
        Text(name).font(.footnote).monospaced()
        Text(status).font(.caption2).foregroundStyle(Theme.Color.inkSecondary)
      }
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
