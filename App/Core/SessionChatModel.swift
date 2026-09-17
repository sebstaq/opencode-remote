import Foundation
import Observation
import OpenCodeAPI
import os

struct ChatBlock: Identifiable, Sendable, Equatable {
  enum Kind: Sendable, Equatable {
    case text(String)
    case reasoning(String)
    case tool(name: String, status: String, callID: String?)
    case marker(String)
  }

  let id: String
  var kind: Kind
}

extension ChatBlock {
  var toolCallID: String? {
    if case .tool(_, _, let callID) = kind { return callID }
    return nil
  }
}

struct ChatMessage: Identifiable, Sendable, Equatable {
  enum Role: Sendable, Equatable {
    case user
    case assistant
  }

  let id: String
  var role: Role
  var blocks: [ChatBlock]
}

enum PermissionDecision: String, Sendable, Equatable {
  case once
  case always
  case reject
}

/// A permission kept for the life of the open session: pending while the run
/// waits, then retained as history once answered. `resolved` covers a reply
/// made from another client, where we know it left the pending set but not the
/// decision.
struct PermissionPrompt: Identifiable, Sendable, Equatable {
  var request: PermissionRequest
  var decision: PermissionDecision? = nil
  var resolved = false

  var id: String { request.id }
}

/// A question, pending until answered or skipped, then kept as a short record.
struct QuestionPrompt: Identifiable, Sendable, Equatable {
  var request: QuestionRequest
  var answered = false
  var skipped = false

  var id: String { request.id }
}

/// A prompt placed at its tool call. `callID` is how the timeline finds the
/// block to render the card next to.
enum InlinePrompt: Identifiable, Sendable, Equatable {
  case permission(PermissionPrompt)
  case question(QuestionPrompt)

  var id: String {
    switch self {
    case .permission(let prompt): return "permission-\(prompt.id)"
    case .question(let prompt): return "question-\(prompt.id)"
    }
  }

  var callID: String? {
    switch self {
    case .permission(let prompt): return prompt.request.tool?.callID
    case .question(let prompt): return prompt.request.tool?.callID
    }
  }
}

@MainActor
@Observable
final class SessionChatModel {
  private(set) var messages: [ChatMessage] = []
  private(set) var error: String?
  private(set) var didLoad = false
  private(set) var isRunning = false
  /// Requests for this session. Pending while the run waits, retained after the
  /// answer so the timeline keeps the record. Recovered from snapshots, since a
  /// request asked while the stream was down has no event to replay.
  private(set) var permissions: [PermissionPrompt] = []
  private(set) var questions: [QuestionPrompt] = []
  /// The block currently receiving deltas; the timeline renders it live.
  private(set) var streamingBlockID: String?
  private var streamSources: [String: StreamedBlockText] = [:]
  private var pendingDeltas: [PendingDelta] = []
  private var flushTask: Task<Void, Never>?
  private var isSending = false

  /// Loads history, then follows the session live until the surrounding task is cancelled.
  func run(
    client: Client,
    sessionID: String,
    service: ConnectionService,
    isCurrent: @escaping @Sendable () async -> Bool
  ) async {
    service.setStreamHealth(.idle)
    defer { service.setStreamHealth(.idle) }
    reset()
    await load(client: client, sessionID: sessionID)
    let stream = SessionStream(
      client: client,
      isCurrent: isCurrent,
      onSubscribed: { [weak self] in
        await self?.resync(client: client, sessionID: sessionID)
      },
      onHealth: { [weak service] live in
        guard let service else { return }
        Task { @MainActor in
          if live {
            service.markStreamActivity()
          } else {
            service.setStreamHealth(.broken)
          }
        }
      }
    )
    for await event in stream.events() {
      if Task.isCancelled {
        return
      }
      apply(event, sessionID: sessionID)
      // Simple robustness net: if events slip through (abort, network blip)
      // the snapshot heals the whole view within seconds, without extra logic.
      var needResync = false
      if case .failure = event {
        needResync = true
      }
      if Date().timeIntervalSince(lastResync) >= 15 {
        needResync = true
      }
      if needResync {
        lastResync = Date()
        await resync(client: client, sessionID: sessionID)
      }
    }
  }

  private var lastResync = Date.distantPast

  func send(client: Client, sessionID: String, text: String) async {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return
    }
    error = nil
    isRunning = true
    isSending = true
    defer { isSending = false }
    let part = Components.Schemas.TextPartInput(_type: .text, text: trimmed)
    do {
      _ = try await client.session_period_prompt_async(
        path: .init(sessionID: sessionID),
        body: .json(.init(parts: [.init(value1: part)]))
      )
      echoMessage(trimmed)
    } catch {
      isRunning = false
      self.error = "Couldn't send the message."
    }
  }

  /// Fetches server state and reconciles. `/event` has no replay, so anything
  /// emitted while the stream was down must come from the snapshot instead.
  func resync(client: Client, sessionID: String) async {
    await load(client: client, sessionID: sessionID)
    // The snapshot supersedes everything buffered before (and during) the
    // fetch; flushing those deltas on top of it would re-apply their tail.
    discardPendingDeltas()
    await loadStatus(client: client, sessionID: sessionID)
    await loadPending(client: client, sessionID: sessionID)
  }

  /// Drops buffered deltas. The stream continues from the current block text,
  /// and any shortfall self-heals through the next full part snapshot.
  private func discardPendingDeltas() {
    pendingDeltas.removeAll()
    flushTask?.cancel()
    flushTask = nil
  }

  private func echoMessage(_ text: String) {
    let id = "local-\(UUID().uuidString)"
    messages.append(
      ChatMessage(id: id, role: .user, blocks: [ChatBlock(id: id, kind: .text(text))])
    )
  }

  private func clearEchoes() {
    messages.removeAll { $0.id.hasPrefix("local-") }
  }

  private func loadStatus(client: Client, sessionID: String) async {
    guard !isSending else {
      return
    }
    guard let output = try? await client.session_period_status() else {
      return
    }
    guard case .ok(let ok) = output, let payload = try? ok.body.json else {
      return
    }
    guard let status = payload.additionalProperties[sessionID] else {
      return
    }
    isRunning = status.value3 != nil || status.value2 != nil
  }

  /// Replaces the pending set from the server snapshots. Both endpoints are
  /// global across sessions, so scope to the open session. A failed fetch
  /// leaves the current set untouched — a network blip must not hide a prompt.
  private func loadPending(client: Client, sessionID: String) async {
    if let output = try? await client.permission_period_list(),
      case .ok(let ok) = output,
      let payload = try? ok.body.json
    {
      let incoming = payload.filter { $0.sessionID == sessionID }.map { PermissionRequest($0) }
      permissions = Self.mergePermissions(incoming, into: permissions, anchor: lastToolAnchor)
    }
    if let output = try? await client.question_period_list(),
      case .ok(let ok) = output,
      let payload = try? ok.body.json
    {
      let incoming = payload.filter { $0.sessionID == sessionID }.compactMap { QuestionRequest($0) }
      questions = Self.mergeQuestions(incoming, into: questions, anchor: lastToolAnchor)
    }
  }

  /// Most `ctx.ask` calls (e.g. `external_directory`) carry no tool reference, so
  /// anchor such a prompt at the newest tool block — the call that raised it.
  var lastToolAnchor: ToolRef? {
    for message in messages.reversed() {
      for block in message.blocks.reversed() {
        if let callID = block.toolCallID {
          return ToolRef(messageID: message.id, callID: callID)
        }
      }
    }
    return nil
  }

  /// The snapshots list only *pending* requests. Keep entries we already
  /// resolved (history, and never clobbered by a still-in-flight reply),
  /// refresh the ones still pending, mark any that vanished as resolved
  /// elsewhere, and append new ones.
  private static func mergePermissions(
    _ incoming: [PermissionRequest], into current: [PermissionPrompt], anchor: ToolRef?
  ) -> [PermissionPrompt] {
    let byID = Dictionary(incoming.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var result: [PermissionPrompt] = []
    var seen = Set<String>()
    for prompt in current {
      seen.insert(prompt.id)
      if prompt.decision != nil || prompt.resolved {
        result.append(prompt)
      } else if var refreshed = byID[prompt.id] {
        if refreshed.tool == nil { refreshed.tool = prompt.request.tool ?? anchor }
        result.append(PermissionPrompt(request: refreshed))
      } else {
        var kept = prompt
        kept.resolved = true
        result.append(kept)
      }
    }
    for var request in incoming where !seen.contains(request.id) {
      if request.tool == nil { request.tool = anchor }
      result.append(PermissionPrompt(request: request))
    }
    return result
  }

  private static func mergeQuestions(
    _ incoming: [QuestionRequest], into current: [QuestionPrompt], anchor: ToolRef?
  ) -> [QuestionPrompt] {
    let byID = Dictionary(incoming.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var result: [QuestionPrompt] = []
    var seen = Set<String>()
    for prompt in current {
      seen.insert(prompt.id)
      if prompt.answered || prompt.skipped {
        result.append(prompt)
      } else if var refreshed = byID[prompt.id] {
        if refreshed.tool == nil { refreshed.tool = prompt.request.tool ?? anchor }
        result.append(QuestionPrompt(request: refreshed))
      } else {
        var kept = prompt
        kept.answered = true
        result.append(kept)
      }
    }
    for var request in incoming where !seen.contains(request.id) {
      if request.tool == nil { request.tool = anchor }
      result.append(QuestionPrompt(request: request))
    }
    return result
  }

  /// Prompts whose tool call lives in `messageID`; the timeline renders each
  /// next to the matching tool block.
  func inlinePrompts(for messageID: String) -> [InlinePrompt] {
    let perms = permissions.filter { $0.request.tool?.messageID == messageID }
    let asks = questions.filter { $0.request.tool?.messageID == messageID }
    return perms.map(InlinePrompt.permission) + asks.map(InlinePrompt.question)
  }

  /// Prompts with no tool, or whose message is not loaded: kept in the thread
  /// tail so they are never hidden.
  var tailPrompts: [InlinePrompt] {
    let messageIDs = Set(messages.map(\.id))
    func orphan(_ tool: ToolRef?) -> Bool {
      guard let tool else { return true }
      return !messageIDs.contains(tool.messageID)
    }
    let perms = permissions.filter { orphan($0.request.tool) }
    let asks = questions.filter { orphan($0.request.tool) }
    return perms.map(InlinePrompt.permission) + asks.map(InlinePrompt.question)
  }

  #if DEBUG
    /// Test seam: seed state without a server, so the anchoring rules can be
    /// exercised deterministically.
    func seedForTesting(
      messages: [ChatMessage],
      permissions: [PermissionPrompt] = [],
      questions: [QuestionPrompt] = []
    ) {
      self.messages = messages
      self.permissions = permissions
      self.questions = questions
    }
  #endif

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
    // Optimistic, and kept as history. A failed reply is re-offered by the
    // next snapshot reconcile (the server still lists it as pending).
    if let index = permissions.firstIndex(where: { $0.id == request.id }) {
      permissions[index].decision = decision
    }
  }

  func answer(question request: QuestionRequest, answers: [[String]], client: Client) async {
    _ = try? await client.question_period_reply(
      path: .init(requestID: request.id),
      body: .json(.init(answers: answers))
    )
    if let index = questions.firstIndex(where: { $0.id == request.id }) {
      questions[index].answered = true
    }
  }

  func reject(question request: QuestionRequest, client: Client) async {
    _ = try? await client.question_period_reject(path: .init(requestID: request.id))
    if let index = questions.firstIndex(where: { $0.id == request.id }) {
      questions[index].skipped = true
    }
  }

  // MARK: - Loading

  private func reset() {
    finishStreaming()
    discardPendingDeltas()
    messages = []
    error = nil
    didLoad = false
    isRunning = false
    permissions = []
    questions = []
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
      if error != nil { error = nil }
      reconcileSnapshot(messageID: messageID, partID: partID, kind: kind)
      setBlock(messageID: messageID, partID: partID, kind: kind)

    case .partDelta(let sid, let messageID, let partID, let field, let delta):
      guard sid == sessionID, !delta.isEmpty else { return }
      if error != nil { error = nil }
      // Coalesce: buffer the delta and flush on a fixed cadence so the UI
      // invalidates once per tick instead of once per token.
      pendingDeltas.append(PendingDelta(messageID: messageID, partID: partID, field: field, delta: delta))
      if streamingBlockID != partID {
        finishStreamingBlocks(except: partID)
        streamingBlockID = partID
        streamSources[partID] = streamSources[partID] ?? StreamedBlockText()
      }
      scheduleFlush()

    case .messageUpdated(let sid, let info):
      guard sid == sessionID else { return }
      if error != nil { error = nil }
      if info.value1 != nil {
        clearEchoes()
      }
      setMessage(id: Self.messageID(info), role: info.value1 != nil ? .user : .assistant)

    case .status(let sid, let status):
      guard sid == sessionID else { return }
      isRunning = status != .idle
      if status == .idle {
        finishStreaming()
      }

    case .idle(let sid):
      guard sid == sessionID else { return }
      isRunning = false
      finishStreaming()

    case .failure(let sid, let message):
      guard sid == sessionID else { return }
      isRunning = false
      error = message
      finishStreaming()

    case .permissionAsked(let request):
      guard request.sessionID == sessionID else { return }
      if let index = permissions.firstIndex(where: { $0.id == request.id }) {
        var updated = request
        if updated.tool == nil { updated.tool = permissions[index].request.tool ?? lastToolAnchor }
        permissions[index].request = updated
      } else {
        var created = request
        if created.tool == nil { created.tool = lastToolAnchor }
        permissions.append(PermissionPrompt(request: created))
      }

    case .permissionResolved(let id):
      if let index = permissions.firstIndex(where: { $0.id == id }) {
        permissions[index].resolved = true
      }

    case .questionAsked(let request):
      guard request.sessionID == sessionID else { return }
      if let index = questions.firstIndex(where: { $0.id == request.id }) {
        var updated = request
        if updated.tool == nil { updated.tool = questions[index].request.tool ?? lastToolAnchor }
        questions[index].request = updated
      } else {
        var created = request
        if created.tool == nil { created.tool = lastToolAnchor }
        questions.append(QuestionPrompt(request: created))
      }

    case .questionResolved(let id):
      if let index = questions.firstIndex(where: { $0.id == id }) {
        questions[index].answered = true
      }

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

  private struct PendingDelta {
    let messageID: String
    let partID: String
    let field: String
    let delta: String
  }

  /// Applies buffered deltas at most once per flush tick. The timeline only
  /// sees a single mutation per tick, no matter how bursty the token stream is.
  private func scheduleFlush() {
    guard flushTask == nil else { return }
    flushTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(100))
      guard let self, !Task.isCancelled else { return }
      self.flushTask = nil
      self.flushPendingDeltas()
    }
  }

  private func flushPendingDeltas() {
    guard !pendingDeltas.isEmpty else { return }
    let signpostState = Self.flushSignposter.beginInterval("coalescedFlush")
    defer { Self.flushSignposter.endInterval("coalescedFlush", signpostState) }
    var batched: [PendingDelta] = []
    for pending in pendingDeltas {
      if let last = batched.last,
        last.messageID == pending.messageID,
        last.partID == pending.partID,
        last.field == pending.field
      {
        batched[batched.count - 1] = PendingDelta(
          messageID: last.messageID,
          partID: last.partID,
          field: last.field,
          delta: last.delta + pending.delta)
      } else {
        batched.append(pending)
      }
    }
    pendingDeltas.removeAll()
    for pending in batched {
      appendDelta(
        messageID: pending.messageID,
        partID: pending.partID,
        field: pending.field,
        delta: pending.delta)
      let text = currentBlockText(messageID: pending.messageID, partID: pending.partID)
      streamSources[pending.partID]?.update(text)
    }
  }

  private func currentBlockText(messageID: String, partID: String) -> String {
    guard
      let index = messages.firstIndex(where: { $0.id == messageID }),
      let blockIndex = messages[index].blocks.firstIndex(where: { $0.id == partID })
    else { return "" }
    switch messages[index].blocks[blockIndex].kind {
    case .text(let text): return text
    case .reasoning(let text): return text
    case .tool, .marker: return ""
    }
  }

  func streamSource(for blockID: String) -> StreamedBlockText? {
    streamSources[blockID]
  }

  /// Closes every live source (and all but the given block, when provided) so
  /// the timeline can switch those blocks back to static rendering.
  private func finishStreamingBlocks(except blockID: String?) {
    for (id, source) in streamSources where id != blockID {
      source.finish()
    }
    streamSources = streamSources.filter { $0.key == blockID }
    if blockID == nil {
      streamingBlockID = nil
    }
  }

  private func finishStreaming() {
    finishStreamingBlocks(except: nil)
  }

  /// A full part snapshot is server truth. When it is at least as long as what
  /// the block accumulated (plus what is still buffered), any buffered deltas
  /// for that part are already included — dropping them prevents re-applying
  /// their tail on top of the snapshot. A shorter snapshot is stale and loses
  /// to the existing text (same longest-wins rule as `merge`).
  private func reconcileSnapshot(messageID: String, partID: String, kind: ChatBlock.Kind) {
    let snapshotText: String?
    switch kind {
    case .text(let text): snapshotText = text
    case .reasoning(let text): snapshotText = text
    case .tool, .marker: snapshotText = nil
    }
    guard let snapshotText else { return }
    let currentText = currentBlockText(messageID: messageID, partID: partID)
    let buffered =
      pendingDeltas
      .filter { $0.partID == partID }
      .map(\.delta)
      .joined()
    guard snapshotText.count >= currentText.count + buffered.count else { return }
    pendingDeltas.removeAll { $0.partID == partID }
    streamSources[partID]?.update(snapshotText)
  }

  private static let flushSignposter = OSSignposter(
    subsystem: "dev.sebstaq.opencode", category: "streamFlush")

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
      return .tool(name: tool.tool, status: status(tool.state), callID: tool.callID)
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
