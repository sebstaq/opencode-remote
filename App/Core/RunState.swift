import Observation
import OpenCodeAPI

/// A session's run state. `idle` is the default and is what the server means by
/// *absence* from `GET /session/status`: that endpoint lists only active
/// sessions (busy/retry) and deletes a session from its map when it goes idle.
enum RunState: String, Sendable, Equatable {
  case idle
  case busy
  case retry
}

extension RunState {
  init(_ status: ServerStatus) {
    switch status {
    case .idle: self = .idle
    case .busy: self = .busy
    case .retry: self = .retry
    }
  }

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

/// The single source of truth for "is this session running", shared by the
/// sidebar and the open chat so they can never disagree.
///
/// Two writers keep it truthful:
///
/// - `session.status` / `session.idle` events, as fast deltas (`set`).
/// - A periodic `GET /session/status` reconcile (`reconcile`), which is
///   *authoritative and complete*: the snapshot is the whole active set, so
///   everything absent is idle. That is what heals a missed event — the
///   previous design only merged present entries and could therefore never
///   clear a stale "running".
@MainActor
@Observable
final class RunStateStore {
  private var states: [String: RunState]

  init(states: [String: RunState] = [:]) {
    self.states = Self.activeOnly(states)
  }

  func state(for sessionID: String) -> RunState {
    states[sessionID] ?? .idle
  }

  /// A delta from a single event.
  func set(_ state: RunState, for sessionID: String) {
    if state == .idle {
      states.removeValue(forKey: sessionID)
    } else {
      states[sessionID] = state
    }
  }

  /// Replaces the state with the complete active set from `GET /session/status`
  /// (`active` holds only non-idle sessions). Absent sessions become idle.
  func reconcile(active: [String: RunState]) {
    states = Self.activeOnly(active)
  }

  private static func activeOnly(_ states: [String: RunState]) -> [String: RunState] {
    states.filter { $0.value != .idle }
  }
}
