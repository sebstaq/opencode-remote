import Foundation
import Observation
import OpenCodeAPI

struct SessionRow: Identifiable, Sendable {
  enum Status: Sendable {
    case idle
    case busy
    case retry
  }

  let id: String
  let title: String
  let updated: Date
  var status: Status
  let group: String
  /// Sub-sessions (agent children) are indented, matching the wireframe.
  var isChild = false
}

@MainActor
@Observable
final class SessionsModel {
  enum Phase {
    case loading
    case loaded([SessionRow])
    case failed(String)
  }

  private(set) var phase: Phase
  private var isLoading = false

  init(phase: Phase = .loading) {
    self.phase = phase
  }

  /// Applies the API's own run-state change (`session.status` / `session.idle`)
  /// to a row. Sessions unknown to the list are ignored; the next list fetch
  /// picks them up.
  func setStatus(_ status: SessionRow.Status, for sessionID: String) {
    guard case .loaded(var rows) = phase,
      let index = rows.firstIndex(where: { $0.id == sessionID })
    else {
      return
    }
    guard rows[index].status != status else {
      return
    }
    rows[index].status = status
    phase = .loaded(rows)
  }

  func refreshStatuses(client: Client) async {
    guard case .loaded = phase else {
      return
    }
    guard let output = try? await client.session_period_status() else {
      return
    }
    guard case .ok(let ok) = output, let payload = try? ok.body.json else {
      return
    }
    var statusMap: [String: SessionRow.Status] = [:]
    for (id, status) in payload.additionalProperties {
      statusMap[id] = SessionRow.Status(status)
    }
    guard case .loaded(var rows) = phase else {
      return
    }
    for index in rows.indices {
      if let status = statusMap[rows[index].id] {
        rows[index].status = status
      }
    }
    phase = .loaded(rows)
  }

  func load(client: Client) async {
    if isLoading {
      return
    }
    isLoading = true
    defer { isLoading = false }

    if case .loaded = phase {
    } else {
      phase = .loading
    }

    do {
      async let listRequest = client.session_period_list()
      async let statusRequest = client.session_period_status()
      let list = try await listRequest
      let statuses = try await statusRequest

      var statusMap: [String: SessionRow.Status] = [:]
      if case .ok(let ok) = statuses, let payload = try? ok.body.json {
        for (id, status) in payload.additionalProperties {
          statusMap[id] = SessionRow.Status(status)
        }
      }

      switch list {
      case .ok(let ok):
        let sessions = try ok.body.json
        let rows =
          sessions
          .filter { entry in (entry.time.archived ?? 0) <= 0 }
          .map { session in
            SessionRow(
              id: session.id,
              title: session.title,
              updated: Self.date(from: Double(session.time.updated)),
              status: statusMap[session.id] ?? .idle,
              group: Self.group(from: session.directory),
              isChild: session.parentID != nil
            )
          }
          .sorted { $0.updated > $1.updated }
        phase = .loaded(rows)
      case .badRequest:
        fail("The server rejected the request")
      case .undocumented(let statusCode, _):
        fail("The server returned \(statusCode)")
      }
    } catch {
      if isCancellation(error) {
        return
      }
      fail(shortMessage(error))
    }
  }

  /// Archives a session (`PATCH /session {time.archived}`) and removes it from
  /// the list. The row re-appears if the update fails. The server's list
  /// endpoint does not hide archived sessions, so filtering happens here.
  func archive(_ id: String, client: Client) async {
    guard case .loaded(var rows) = phase,
      let index = rows.firstIndex(where: { $0.id == id })
    else {
      return
    }
    let row = rows.remove(at: index)
    phase = .loaded(rows)
    do {
      let output = try await client.session_period_update(
        path: .init(sessionID: id),
        body: .json(.init(time: .init(archived: Date().timeIntervalSince1970 * 1000)))
      )
      if case .ok = output {
        return
      }
      rows.insert(row, at: min(index, rows.count))
      phase = .loaded(rows)
    } catch {
      if isCancellation(error) {
        return
      }
      rows.insert(row, at: min(index, rows.count))
      phase = .loaded(rows)
    }
  }

  private func fail(_ message: String) {
    if case .loaded = phase {
      return
    }
    phase = .failed(message)
  }

  private func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError {
      return true
    }
    return underlyingURLError(error)?.code == .cancelled
      || (error as NSError).code == NSURLErrorCancelled
  }

  private func shortMessage(_ error: Error) -> String {
    guard let urlError = underlyingURLError(error) else {
      return "Something went wrong."
    }
    switch urlError.code {
    case .cannotConnectToHost, .cannotFindHost, .notConnectedToInternet, .networkConnectionLost:
      return "Can't reach the computer."
    case .timedOut:
      return "The server did not respond in time."
    default:
      return "The request failed."
    }
  }

  private func underlyingURLError(_ error: Error) -> URLError? {
    var current: Error? = error
    for _ in 0..<8 {
      guard let candidate = current else {
        return nil
      }
      if let urlError = candidate as? URLError {
        return urlError
      }
      let nsError = candidate as NSError
      current = (nsError.userInfo[NSUnderlyingErrorKey] as? Error) ?? nsError.underlyingErrors.first
    }
    return nil
  }

  private static func group(from directory: String) -> String {
    let name = URL(fileURLWithPath: directory).lastPathComponent
    return name.isEmpty ? directory : name
  }

  private static func date(from value: Double) -> Date {
    let seconds = value > 1e11 ? value / 1000 : value
    return Date(timeIntervalSince1970: seconds)
  }
}

extension SessionRow.Status {
  init(_ status: Components.Schemas.SessionStatus) {
    if status.value3 != nil {
      self = .busy
    } else if status.value2 != nil {
      self = .retry
    } else {
      self = .idle
    }
  }
}
