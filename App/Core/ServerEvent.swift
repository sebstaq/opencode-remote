import Foundation
import OpenCodeAPI

enum ServerStatus: Sendable {
  case idle
  case busy
  case retry

  init(raw: String) {
    switch raw {
    case "busy": self = .busy
    case "retry": self = .retry
    default: self = .idle
    }
  }
}

/// The tool call a permission/question belongs to. Lets the timeline place the
/// card at the exact tool block instead of at the end of the thread.
struct ToolRef: Sendable, Equatable {
  let messageID: String
  let callID: String
}

struct PermissionRequest: Identifiable, Sendable, Equatable {
  let id: String
  let sessionID: String
  let permission: String
  let patterns: [String]
  let always: [String]
  var tool: ToolRef? = nil
}

struct QuestionOption: Sendable, Equatable {
  let label: String
  let description: String?
}

struct QuestionRequest: Identifiable, Sendable, Equatable {
  let id: String
  let sessionID: String
  let header: String
  let question: String
  let options: [QuestionOption]
  let multiple: Bool
  let custom: Bool
  var tool: ToolRef? = nil
}

/// The subset of `GET /event` we act on. Everything else is dropped by the decoder.
enum ServerEvent: Sendable {
  case partUpdated(sessionID: String, messageID: String, partID: String, part: Components.Schemas.Part)
  case partDelta(
    sessionID: String, messageID: String, partID: String, field: String, delta: String)
  case messageUpdated(sessionID: String, info: Components.Schemas.Message)
  case status(sessionID: String, status: ServerStatus)
  case idle(sessionID: String)
  case failure(sessionID: String, message: String)
  case permissionAsked(PermissionRequest)
  case permissionResolved(id: String)
  case questionAsked(QuestionRequest)
  case questionResolved(id: String)
  case todoUpdated(sessionID: String)
}

enum ServerEventDecoder {
  private static let decoder = JSONDecoder()

  static func decode(_ data: Data) -> ServerEvent? {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let type = root["type"] as? String,
      let props = root["properties"] as? [String: Any]
    else {
      return nil
    }

    func decodeValue<T: Decodable>(_ key: String, as _: T.Type) -> T? {
      guard let value = props[key], JSONSerialization.isValidJSONObject(value),
        let encoded = try? JSONSerialization.data(withJSONObject: value)
      else {
        return nil
      }
      return try? decoder.decode(T.self, from: encoded)
    }

    switch type {
    case "message.part.updated":
      guard let sessionID = props["sessionID"] as? String,
        let partObject = props["part"] as? [String: Any],
        let partID = partObject["id"] as? String,
        let part = decodeValue("part", as: Components.Schemas.Part.self)
      else { return nil }
      return .partUpdated(
        sessionID: sessionID,
        messageID: partObject["messageID"] as? String ?? "",
        partID: partID,
        part: part
      )

    case "message.part.delta":
      guard let sessionID = props["sessionID"] as? String,
        let messageID = props["messageID"] as? String,
        let partID = props["partID"] as? String,
        let field = props["field"] as? String,
        let delta = props["delta"] as? String
      else { return nil }
      return .partDelta(
        sessionID: sessionID, messageID: messageID, partID: partID, field: field, delta: delta)

    case "message.updated":
      guard let sessionID = props["sessionID"] as? String,
        let info = decodeValue("info", as: Components.Schemas.Message.self)
      else { return nil }
      return .messageUpdated(sessionID: sessionID, info: info)

    case "session.status":
      guard let sessionID = props["sessionID"] as? String,
        let status = decodeValue("status", as: RawStatus.self)
      else { return nil }
      return .status(sessionID: sessionID, status: ServerStatus(raw: status.type))

    case "session.idle":
      guard let sessionID = props["sessionID"] as? String else { return nil }
      return .idle(sessionID: sessionID)

    case "session.error":
      guard let sessionID = props["sessionID"] as? String else { return nil }
      return .failure(sessionID: sessionID, message: errorText(props["error"]))

    case "permission.asked":
      guard let id = props["id"] as? String, let sessionID = props["sessionID"] as? String
      else { return nil }
      return .permissionAsked(
        PermissionRequest(
          id: id,
          sessionID: sessionID,
          permission: props["permission"] as? String ?? "permission",
          patterns: props["patterns"] as? [String] ?? [],
          always: props["always"] as? [String] ?? [],
          tool: toolRef(props["tool"])
        )
      )

    case "permission.replied":
      guard let id = requestID(props) else { return nil }
      return .permissionResolved(id: id)

    case "question.asked":
      guard let id = props["id"] as? String, let sessionID = props["sessionID"] as? String,
        let questions = props["questions"] as? [[String: Any]], let first = questions.first
      else { return nil }
      let options = (first["options"] as? [[String: Any]] ?? []).compactMap { option -> QuestionOption? in
        guard let label = option["label"] as? String else { return nil }
        return QuestionOption(label: label, description: option["description"] as? String)
      }
      return .questionAsked(
        QuestionRequest(
          id: id,
          sessionID: sessionID,
          header: first["header"] as? String ?? "Question",
          question: first["question"] as? String ?? "",
          options: options,
          multiple: first["multiple"] as? Bool ?? false,
          custom: first["custom"] as? Bool ?? false,
          tool: toolRef(props["tool"])
        )
      )

    case "question.replied", "question.rejected":
      guard let id = requestID(props) else { return nil }
      return .questionResolved(id: id)

    case "todo.updated":
      guard let sessionID = props["sessionID"] as? String else { return nil }
      return .todoUpdated(sessionID: sessionID)

    default:
      return nil
    }
  }

  private struct RawStatus: Decodable {
    let type: String
  }

  /// Resolution events carry the request under `requestID`; older payloads used
  /// `id`. Accept both so the card clears regardless of the server build.
  private static func requestID(_ props: [String: Any]) -> String? {
    (props["requestID"] as? String) ?? (props["id"] as? String)
  }

  private static func toolRef(_ value: Any?) -> ToolRef? {
    guard let object = value as? [String: Any],
      let messageID = object["messageID"] as? String,
      let callID = object["callID"] as? String
    else { return nil }
    return ToolRef(messageID: messageID, callID: callID)
  }

  private static func errorText(_ value: Any?) -> String {
    guard let object = value as? [String: Any] else {
      return "The session stopped with an error."
    }
    if let name = object["name"] as? String, name.lowercased().contains("abort") {
      return "This turn was stopped; the next message starts a new turn."
    }
    if let data = object["data"] as? [String: Any] {
      for key in ["message", "reason", "error"] {
        if let text = data[key] as? String, !text.isEmpty {
          return text
        }
      }
    }
    if let name = object["name"] as? String, !name.isEmpty {
      return name
    }
    return "The session stopped with an error."
  }
}

// MARK: - Snapshot mapping
//
// `GET /event` has no replay, so pending requests are recovered from the
// `GET /permission` and `GET /question` snapshots. Map the generated payloads
// into the same shapes the live events produce.

extension PermissionRequest {
  init(_ request: Components.Schemas.PermissionRequest) {
    self.init(
      id: request.id,
      sessionID: request.sessionID,
      permission: request.permission,
      patterns: request.patterns,
      always: request.always,
      tool: request.tool.map { ToolRef(messageID: $0.messageID, callID: $0.callID) }
    )
  }
}

extension QuestionRequest {
  init?(_ request: Components.Schemas.QuestionRequest) {
    guard let first = request.questions.first else { return nil }
    self.init(
      id: request.id,
      sessionID: request.sessionID,
      header: first.header,
      question: first.question,
      options: first.options.map { QuestionOption(label: $0.label, description: $0.description) },
      multiple: first.multiple ?? false,
      custom: first.custom ?? false,
      tool: request.tool.map { ToolRef(messageID: $0.messageID, callID: $0.callID) }
    )
  }
}
