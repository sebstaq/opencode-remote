import Foundation
import HTTPTypes
import OpenAPIRuntime
#if DEBUG
  import OSLog
#endif

/// The server pages `session.messages` backwards: the response carries an
/// opaque `X-Next-Cursor` header pointing at the next, older page. The header is
/// not part of the OpenAPI schema, so it is captured here and handed to
/// `SessionChatModel`, which passes it back as the `before` query.
actor PaginationCursorStore {
  static let shared = PaginationCursorStore()

  private var cursors: [String: String] = [:]

  func store(_ cursor: String?, for sessionID: String) {
    cursors[sessionID] = cursor
  }

  func cursor(for sessionID: String) -> String? {
    cursors[sessionID]
  }
}

struct PaginationCursorMiddleware: ClientMiddleware {
  let store: PaginationCursorStore

  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String,
    next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPResponse, HTTPBody?) {
    let (response, responseBody) = try await next(request, body, baseURL)
    guard operationID == "session.messages" else {
      return (response, responseBody)
    }
    guard let name = HTTPField.Name("X-Next-Cursor"),
      let sessionID = Self.sessionID(from: request.path ?? "")
    else {
      return (response, responseBody)
    }
    let cursor = response.headerFields[name]
    await store.store(cursor, for: sessionID)
    #if DEBUG
      Logger(subsystem: "dev.sebstaq.opencode", category: "pagination").debug(
        "page session=\(sessionID, privacy: .public) has_older=\(cursor != nil, privacy: .public)")
    #endif
    return (response, responseBody)
  }

  /// Extracts the session id from `/session/{sessionID}/message…` (the generated
  /// request may append the query string to the path).
  private static func sessionID(from path: String) -> String? {
    let parts = path.split(separator: "/", omittingEmptySubsequences: true)
    guard parts.count >= 3, parts[0] == "session", parts[2].hasPrefix("message") else {
      return nil
    }
    return String(parts[1])
  }
}
