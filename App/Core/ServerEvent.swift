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

extension SessionRow.Status {
  init(from status: ServerStatus) {
    switch status {
    case .busy: self = .busy
    case .retry: self = .retry
    case .idle: self = .idle
    }
  }
}

struct PermissionRequest: Identifiable, Sendable, Equatable {
  let id: String
  let sessionID: String
  let permission: String
  let patterns: [String]
  let always: [String]
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
          always: props["always"] as? [String] ?? []
        )
      )

    case "permission.replied":
      guard let id = props["id"] as? String else { return nil }
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
          custom: first["custom"] as? Bool ?? false
        )
      )

    case "question.replied", "question.rejected":
      guard let id = props["id"] as? String else { return nil }
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
