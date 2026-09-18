import OpenCodeAPI
import PhotosUI
import SwiftStreamingMarkdown
import SwiftUI

struct SessionTimeline: View {
  let sessionID: String
  let client: Client
  let service: ConnectionService
  let runState: RunStateStore
  let generation: Int
  let isCurrent: @Sendable () async -> Bool

  @State private var model = SessionChatModel()
  @State private var draft = ""
  @State private var attachments: [Attachment] = []
  @State private var photoItems: [PhotosPickerItem] = []
  @State private var showPhotoPicker = false
  @State private var showCamera = false
  @State private var expandedReasoning: Set<String> = []
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    ChatViewport(bottomID: model.tailPrompts.last?.id ?? model.messages.last?.id) {
      ForEach(model.messages) { message in
        MessageRow(
          message: message,
          model: model,
          prompts: model.inlinePrompts(for: message.id),
          streamingBlockID: model.streamingBlockID,
          expanded: expandedReasoning.contains(message.id),
          onToggleReasoning: { toggleReasoning(message.id) },
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
        .id(message.id)
      }
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
        .id(prompt.id)
      }
    }
    .id(sessionID)
    .overlay { placeholder }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      composer
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
        seedAttachmentIfRequested()
      #endif
      await model.run(
        client: client, sessionID: sessionID, service: service, runState: runState,
        isCurrent: isCurrent)
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

  #if DEBUG
    /// Test seam: a solid-red attachment so the live attachment E2E can send an
    /// image without driving the system photo picker.
    private func seedAttachmentIfRequested() {
      guard attachments.isEmpty,
        (ProcessInfo.processInfo.environment["OPENCODE_UI_ATTACHMENT"] ?? "").isEmpty == false
      else { return }
      let side: CGFloat = 400
      let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
      let image = renderer.image { context in
        context.cgContext.setFillColor(UIColor.red.cgColor)
        context.cgContext.fill(CGRect(x: 0, y: 0, width: side, height: side))
      }
      if let attachment = AttachmentEncoder.make(image: image, filename: "seed.jpg") {
        attachments.append(attachment)
      }
    }
  #endif

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

  // MARK: - Composer

  private var composer: some View {
    VStack(spacing: 8) {
      if !attachments.isEmpty {
        attachmentStrip
      }
      HStack(spacing: 10) {
        Menu {
          Button {
            showPhotoPicker = true
          } label: {
            Label("Photo Library", systemImage: "photo.on.rectangle")
          }
          if CameraPicker.isAvailable {
            Button {
              showCamera = true
            } label: {
              Label("Camera", systemImage: "camera")
            }
          }
        } label: {
          Image(systemName: "plus.circle")
            .font(.system(size: 28))
            .foregroundStyle(Theme.Color.inkSecondary)
        }
        .accessibilityIdentifier("composer.attach")

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
          .disabled(!canSend)
          .accessibilityIdentifier("composer.send")
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .photosPicker(
      isPresented: $showPhotoPicker, selection: $photoItems, maxSelectionCount: 4
    )
    .onChange(of: photoItems) { _, items in
      guard !items.isEmpty else { return }
      Task { await loadAttachments(items) }
    }
    .fullScreenCover(isPresented: $showCamera) {
      CameraPicker { image in
        let stamp = Int(Date().timeIntervalSince1970)
        if let attachment = AttachmentEncoder.make(
          image: image, filename: "camera-\(stamp).jpg")
        {
          attachments.append(attachment)
        }
      }
      .ignoresSafeArea()
    }
  }

  private var attachmentStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(attachments) { attachment in
          ZStack(alignment: .topTrailing) {
            Group {
              if let preview = attachment.preview, let image = UIImage(data: preview) {
                Image(uiImage: image)
                  .resizable()
                  .scaledToFill()
              } else {
                Image(systemName: "doc.fill")
                  .font(.title3)
                  .foregroundStyle(Theme.Color.inkSecondary)
              }
            }
            .frame(width: 56, height: 56)
            .background(Theme.Color.fillComposer)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
              attachments.removeAll { $0.id == attachment.id }
            } label: {
              Image(systemName: "xmark.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(Theme.Color.fillInverted)
                .background(Circle().fill(Theme.Color.surface))
            }
            .offset(x: 5, y: -5)
            .accessibilityIdentifier("composer.removeAttachment")
          }
        }
      }
      .padding(.top, 6)
      .padding(.horizontal, 2)
    }
  }

  private var canSend: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
  }

  private func loadAttachments(_ items: [PhotosPickerItem]) async {
    for item in items {
      if let attachment = await AttachmentEncoder.make(from: item) {
        attachments.append(attachment)
      }
    }
    photoItems = []
  }

  private func send() {
    let text = draft
    let picked = attachments
    draft = ""
    attachments = []
    Task { await model.send(client: client, sessionID: sessionID, text: text, attachments: picked) }
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
