import Foundation
import OpenCodeAPI

/// Owns the connection's run-state feed: the status subscription plus the
/// periodic reconcile that keep `RunStateStore` truthful. One instance is
/// created per connection generation by `ChatShell`.
///
/// Deliberately the *only* writer of server-derived run state. Views read the
/// store; the open chat only reacts to transitions (to finish a stream), so the
/// sidebar and the composer are always consistent.
@MainActor
final class SessionActivityModel {
  let store: RunStateStore
  private let interval: Duration

  init(store: RunStateStore, interval: Duration = .seconds(10)) {
    self.store = store
    self.interval = interval
  }

  /// Follows the connection until `isCurrent` turns false (generation change).
  func run(client: Client, isCurrent: @escaping @Sendable () async -> Bool) async {
    await reconcile(client: client)
    let polling = Task { [weak self] in
      await self?.poll(client: client, isCurrent: isCurrent)
    }
    await stream(client: client, isCurrent: isCurrent)
    polling.cancel()
    await polling.value
  }

  /// One authoritative snapshot folded into the store. Also called on
  /// foreground, so returning to the app corrects any drift immediately.
  func reconcile(client: Client) async {
    guard let active = try? await Self.activeSessions(client) else { return }
    store.reconcile(active: active)
  }

  /// The complete active set from `GET /session/status`; only non-idle sessions
  /// are present by construction of the API.
  static func activeSessions(_ client: Client) async throws -> [String: RunState] {
    let output = try await client.session_period_status()
    guard case .ok(let ok) = output, let payload = try? ok.body.json else { return [:] }
    var active: [String: RunState] = [:]
    for (id, status) in payload.additionalProperties {
      let state = RunState(status)
      if state != .idle {
        active[id] = state
      }
    }
    return active
  }

  private func stream(client: Client, isCurrent: @escaping @Sendable () async -> Bool) async {
    let stream = SessionStream(
      client: client,
      isCurrent: isCurrent,
      onSubscribed: { [weak self] in
        await self?.reconcile(client: client)
      },
      onHealth: { _ in }
    )
    for await event in stream.events() {
      switch event {
      case .status(let sessionID, let status):
        store.set(RunState(status), for: sessionID)
      case .idle(let sessionID):
        store.set(.idle, for: sessionID)
      default:
        continue
      }
    }
  }

  /// Bounds the cost of a missed event: an idle that never arrived is corrected
  /// within one interval, because the reconcile is authoritative.
  private func poll(client: Client, isCurrent: @escaping @Sendable () async -> Bool) async {
    while !Task.isCancelled, await isCurrent() {
      try? await Task.sleep(for: interval)
      if Task.isCancelled { break }
      await reconcile(client: client)
    }
  }
}
