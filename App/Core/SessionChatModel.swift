import Foundation
import Observation
import OpenCodeAPI

struct ChatBlock: Identifiable, Sendable {
  enum Kind: Sendable {
    case text(String)
    case reasoning(String)
    case tool(name: String, status: String)
    case marker(String)
  }

  let id: String
  var kind: Kind
}

struct ChatMessage: Identifiable, Sendable {
  enum Role: Sendable {
    case user
    case assistant
  }

  let id: String
  var role: Role
  var blocks: [ChatBlock]
}

enum PermissionDecision: String, Sendable {
  case once
  case always
  case reject
}

@MainActor
@Observable
final class SessionChatModel {
  private(set) var messages: [ChatMessage] = []
  private(set) var error: String?
  private(set) var didLoad = false
  private(set) var isRunning = false
  private(set) var permission: PermissionRequest?
  private(set) var question: QuestionRequest?

  /// Loads history, then follows the session live until the surrounding task is cancelled.
  func run(client: Client, sessionID: String) async {
    reset()
    await load(client: client, sessionID: sessionID)
    let stream = SessionStream(client: client)
    for await event in stream.events() {
      if Task.isCancelled {
        return
      }
      apply(event, sessionID: sessionID)
    }
  }

  func send(client: Client, sessionID: String, text: String) async {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return
    }
    error = nil
    isRunning = true
    let part = Components.Schemas.TextPartInput(_type: .text, text: trimmed)
    do {
      _ = try await client.session_period_prompt_async(
        path: .init(sessionID: sessionID),
        body: .json(.init(parts: [.init(value1: part)]))
      )
    } catch {
      isRunning = false
      self.error = "Couldn't send the message."
    }
  }

  func abort(client: Client, sessionID: String) async {
    _ = try? await client.session_period_abort(path: .init(sessionID: sessionID))
  }

  func reply(
    permission request: PermissionRequest, decision: PermissionDecision, client: Client
  ) async {
    let reply: Operations.permission_period_reply.Input.Body.jsonPayload.replyPayload
    switch decision {
    case .once: reply = .once
    case .always: reply = .always
    case .reject: reply = .reject
    }
    _ = try? await client.permission_period_reply(
      path: .init(requestID: request.id),
      body: .json(.init(reply: reply))
    )
    permission = nil
  }

  func answer(question request: QuestionRequest, answers: [[String]], client: Client) async {
    _ = try? await client.question_period_reply(
      path: .init(requestID: request.id),
      body: .json(.init(answers: answers))
    )
    question = nil
  }

  func reject(question request: QuestionRequest, client: Client) async {
    _ = try? await client.question_period_reject(path: .init(requestID: request.id))
    question = nil
  }

  // MARK: - Loading

  private func reset() {
    messages = []
    error = nil
    didLoad = false
    isRunning = false
    permission = nil
    question = nil
  }

  private func load(client: Client, sessionID: String) async {
    do {
      let output = try await client.session_period_messages(path: .init(sessionID: sessionID))
      switch output {
      case .ok(let ok):
        let payload = try ok.body.json
        messages = payload.map { item in
          ChatMessage(
            id: Self.messageID(item.info),
            role: item.info.value1 != nil ? .user : .assistant,
            blocks: item.parts.map(Self.block(from:))
          )
        }
        error = nil
        didLoad = true
      case .badRequest:
        setError("The server rejected the request")
      case .undocumented(let statusCode, _):
        setError("The server returned \(statusCode)")
      default:
        setError("Unexpected response")
      }
    } catch {
      if isCancellation(error) {
        return
      }
      setError("Couldn't load messages.")
    }
  }

  private func setError(_ message: String) {
    if messages.isEmpty {
      error = message
    }
  }

  // MARK: - Live events

  private func apply(_ event: ServerEvent, sessionID: String) {
    switch event {
    case .partUpdated(let sid, let messageID, let partID, let part):
      guard sid == sessionID, let kind = Self.kind(from: part) else { return }
      setBlock(messageID: messageID, partID: partID, kind: kind)

    case .partDelta(let sid, let messageID, let partID, let field, let delta):
      guard sid == sessionID else { return }
      appendDelta(messageID: messageID, partID: partID, field: field, delta: delta)

    case .messageUpdated(let sid, let info):
      guard sid == sessionID else { return }
      setMessage(id: Self.messageID(info), role: info.value1 != nil ? .user : .assistant)

    case .status(let sid, let status):
      guard sid == sessionID else { return }
      isRunning = status != .idle

    case .idle(let sid):
      guard sid == sessionID else { return }
      isRunning = false

    case .failure(let sid, let message):
      guard sid == sessionID else { return }
      isRunning = false
      error = message

    case .permissionAsked(let request):
      guard request.sessionID == sessionID else { return }
      permission = request

    case .permissionResolved(let id):
      if permission?.id == id { permission = nil }

    case .questionAsked(let request):
      guard request.sessionID == sessionID else { return }
      question = request

    case .questionResolved(let id):
      if question?.id == id { question = nil }

    case .todoUpdated:
      break
    }
  }

  private func setMessage(id: String, role: ChatMessage.Role) {
    guard !id.isEmpty else { return }
    if let index = messages.firstIndex(where: { $0.id == id }) {
      messages[index].role = role
    } else {
      messages.append(ChatMessage(id: id, role: role, blocks: []))
    }
  }

  private func setBlock(messageID: String, partID: String, kind: ChatBlock.Kind) {
    guard !messageID.isEmpty, !partID.isEmpty else { return }
    setMessage(id: messageID, role: .assistant)
    guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
    if let blockIndex = messages[index].blocks.firstIndex(where: { $0.id == partID }) {
      messages[index].blocks[blockIndex].kind = Self.merge(
        messages[index].blocks[blockIndex].kind, kind)
    } else {
      messages[index].blocks.append(ChatBlock(id: partID, kind: kind))
    }
  }

  /// `part.updated` is authoritative, but the server can emit a shorter snapshot
  /// (e.g. an empty text part when a run is aborted) which must not wipe the
  /// text we already streamed from deltas.
  private static func merge(_ existing: ChatBlock.Kind, _ incoming: ChatBlock.Kind) -> ChatBlock.Kind {
    switch (existing, incoming) {
    case (.text(let current), .text(let next)):
      return .text(next.count >= current.count ? next : current)
    case (.reasoning(let current), .reasoning(let next)):
      return .reasoning(next.count >= current.count ? next : current)
    default:
      return incoming
    }
  }

  private func appendDelta(messageID: String, partID: String, field: String, delta: String) {
    guard !messageID.isEmpty, !partID.isEmpty else { return }
    setMessage(id: messageID, role: .assistant)
    guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
    if let blockIndex = messages[index].blocks.firstIndex(where: { $0.id == partID }) {
      messages[index].blocks[blockIndex].kind = Self.appending(
        messages[index].blocks[blockIndex].kind, delta)
    } else {
      let kind: ChatBlock.Kind = field == "reasoning" ? .reasoning(delta) : .text(delta)
      messages[index].blocks.append(ChatBlock(id: partID, kind: kind))
    }
  }

  private static func appending(_ kind: ChatBlock.Kind, _ delta: String) -> ChatBlock.Kind {
    switch kind {
    case .text(let text): return .text(text + delta)
    case .reasoning(let text): return .reasoning(text + delta)
    default: return kind
    }
  }

  // MARK: - Part mapping

  private static func messageID(_ message: Components.Schemas.Message) -> String {
    message.value1?.id ?? message.value2?.id ?? UUID().uuidString
  }

  static func block(from part: Components.Schemas.Part) -> ChatBlock {
    ChatBlock(id: partID(part), kind: kind(from: part) ?? .marker(""))
  }

  private static func partID(_ part: Components.Schemas.Part) -> String {
    if let value = part.value1 { return value.id }
    if let value = part.value2 { return value.id }
    if let value = part.value3 { return value.id }
    if let value = part.value4 { return value.id }
    if let value = part.value5 { return value.id }
    if let value = part.value6 { return value.id }
    if let value = part.value7 { return value.id }
    if let value = part.value8 { return value.id }
    if let value = part.value9 { return value.id }
    if let value = part.value10 { return value.id }
    if let value = part.value11 { return value.id }
    if let value = part.value12 { return value.id }
    return UUID().uuidString
  }

  private static func kind(from part: Components.Schemas.Part) -> ChatBlock.Kind? {
    if let text = part.value1 {
      return .text(text.text)
    }
    if let reasoning = part.value3 {
      return .reasoning(reasoning.text)
    }
    if let tool = part.value5 {
      return .tool(name: tool.tool, status: status(tool.state))
    }
    if let compaction = part.value12 {
      return .marker(compaction.auto ? "Context compacted" : "Compacted")
    }
    if part.value11 != nil {
      return .marker("Retrying")
    }
    return nil
  }

  private static func status(_ state: Components.Schemas.ToolState) -> String {
    if state.value3 != nil {
      return "done"
    }
    if state.value4 != nil {
      return "error"
    }
    if state.value2 != nil {
      return "running"
    }
    return "pending"
  }

  private func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError {
      return true
    }
    var current: Error? = error
    for _ in 0..<8 {
      guard let candidate = current else {
        return false
      }
      if let urlError = candidate as? URLError, urlError.code == .cancelled {
        return true
      }
      if (candidate as NSError).code == NSURLErrorCancelled {
        return true
      }
      let nsError = candidate as NSError
      current = (nsError.userInfo[NSUnderlyingErrorKey] as? Error) ?? nsError.underlyingErrors.first
    }
    return false
  }
}
