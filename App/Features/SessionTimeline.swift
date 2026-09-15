import OpenCodeAPI
import SwiftUI

struct SessionTimeline: View {
  let sessionID: String
  let client: Client

  @State private var model = SessionChatModel()
  @State private var draft = ""
  @State private var chosen: Set<String> = []
  @State private var custom = ""

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          ForEach(model.messages) { message in
            messageView(message).id(message.id)
          }
        }
        .padding()
      }
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
      .background(.bar)
    }
    .task(id: sessionID) {
      #if DEBUG
        // Lets UI tests exercise send/abort without the simulator keyboard.
        if let seed = ProcessInfo.processInfo.environment["OPENCODE_UI_DRAFT"], draft.isEmpty {
          draft = seed
        }
      #endif
      await model.run(client: client, sessionID: sessionID)
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
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("composer.field")

      if model.isRunning {
        Button {
          Task { await model.abort(client: client, sessionID: sessionID) }
        } label: {
          Image(systemName: "stop.circle.fill").font(.system(size: 30))
        }
        .accessibilityIdentifier("composer.stop")
      } else {
        Button {
          send()
        } label: {
          Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
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
          .foregroundStyle(.secondary)
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
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
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
                Text(description).font(.caption).foregroundStyle(.secondary)
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
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
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

  // MARK: - Messages

  @ViewBuilder
  private func messageView(_ message: ChatMessage) -> some View {
    VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
      ForEach(message.blocks) { block in
        blockView(block, role: message.role)
      }
    }
    .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
  }

  // MARK: - Blocks

  /// The user speaks in bubbles; the assistant answers as a document.
  @ViewBuilder
  private func blockView(_ block: ChatBlock, role: ChatMessage.Role) -> some View {
    switch block.kind {
    case .text(let text):
      switch role {
      case .user:
        Text(text)
          .padding(.horizontal, 12)
          .padding(.vertical, 9)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
      case .assistant:
        MarkdownText(text)
      }
    case .reasoning(let text):
      Text(text)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    case .tool(let name, let status):
      HStack(spacing: 8) {
        Text(name).font(.footnote).monospaced()
        Text(status).font(.caption2).foregroundStyle(.secondary)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .overlay(
        RoundedRectangle(cornerRadius: 10).stroke(.quaternary)
      )
    case .marker(let text):
      if !text.isEmpty {
        Text(text).font(.caption2).foregroundStyle(.secondary)
      }
    }
  }
}
