import Foundation
import Observation

/// The single place the app persists anything between launches.
///
/// One storage backend (UserDefaults), one schema, one way to read and write:
///
///     prefs[.collapsedGroups] = ["api"]
///
/// A key is either **global** (the computer list, the last chosen computer,
/// the open conversation) or **scoped to the active computer**, so two
/// machines that both have a project called "api" never share collapse state,
/// model choice or agent. The scope is the last connected computer
/// (`Key.lastComputerID`).
///
/// Writes persist immediately (UserDefaults coalesces them), and every read is
/// observable, so SwiftUI updates when a preference changes.
///
/// Ephemeral state — connection, run status, session contents — must **not** be
/// added here. It is reconciled against the server on every launch instead.
@MainActor
@Observable
final class Preferences {
  /// A named slot. `scoped` keys resolve against the active computer.
  ///
  /// The schema lives in constrained extensions below so call sites read
  /// `prefs[.collapsedGroups]`. (A generic type cannot hold static storage, so
  /// the keys are computed properties.)
  struct Key<Value: Codable> {
    let name: String
    let defaultValue: Value
    let scoped: Bool

    static func global(_ name: String, _ defaultValue: Value) -> Key {
      Key(name: name, defaultValue: defaultValue, scoped: false)
    }

    static func computer(_ name: String, _ defaultValue: Value) -> Key {
      Key(name: name, defaultValue: defaultValue, scoped: true)
    }
  }

  private static let namespace = "prefs."

  private let defaults: UserDefaults

  /// One-time setup (the E2E reset) must run once per process. `RootView.init`
  /// can run more than once, so an unguarded `init` would reset the store
  /// mid-session.
  private static var didRunOneTimeSetup = false

  /// Bumped on every write and read on every read, so Observation invalidates
  /// all preference readers. The set is small enough that per-key tracking is
  /// not worth the bookkeeping.
  private(set) var revision = 0

  /// Resolves the backing store. A UI test can pin a suite with
  /// `OPENCODE_UI_DEFAULTS_SUITE` to exercise persistence across launches;
  /// otherwise the standard store is used.
  init(defaults: UserDefaults? = nil) {
    self.defaults = defaults ?? Self.resolveDefaults()
    if defaults == nil, !Self.didRunOneTimeSetup {
      Self.didRunOneTimeSetup = true
      resetForEndToEndIfNeeded()
    }
  }

  subscript<Value: Codable>(_ key: Key<Value>) -> Value {
    get {
      _ = revision
      guard let data = defaults.data(forKey: storageName(key)),
        let value = try? JSONDecoder().decode(Value.self, from: data)
      else { return key.defaultValue }
      return value
    }
    set {
      revision &+= 1
      let name = storageName(key)
      if (newValue as? AnyOptional)?.isNil == true {
        defaults.removeObject(forKey: name)
        return
      }
      guard let data = try? JSONEncoder().encode(newValue) else {
        defaults.removeObject(forKey: name)
        return
      }
      defaults.set(data, forKey: name)
    }
  }

  /// Removes every key this store owns. Used by tests and the E2E reset.
  func reset() {
    revision &+= 1
    for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.namespace) {
      defaults.removeObject(forKey: key)
    }
  }

  private var scopeID: String? {
    guard let data = defaults.data(forKey: storageName(Key<String?>.lastComputerID)),
      let id = try? JSONDecoder().decode(String.self, from: data)
    else { return nil }
    return id
  }

  private func storageName<Value>(_ key: Key<Value>) -> String {
    guard key.scoped, let scopeID else { return Self.namespace + key.name }
    return "\(Self.namespace)computer.\(scopeID).\(key.name)"
  }

  private static func resolveDefaults() -> UserDefaults {
    let environment = ProcessInfo.processInfo.environment
    if let suite = environment["OPENCODE_UI_DEFAULTS_SUITE"], !suite.isEmpty,
      let defaults = UserDefaults(suiteName: suite)
    {
      return defaults
    }
    return .standard
  }

  /// A UI test injects a clean slate through the environment, so a prior run's
  /// preferences never leak into a test. `OPENCODE_UI_PERSIST=1` opts out for
  /// the suite that verifies restore across launches.
  private func resetForEndToEndIfNeeded() {
    let environment = ProcessInfo.processInfo.environment
    guard environment["OPENCODE_E2E_URL"]?.isEmpty == false,
      environment["OPENCODE_UI_PERSIST"]?.isEmpty != false
    else { return }
    reset()
  }

}

// MARK: - Schema

extension Preferences.Key where Value == [Computer] {
  static var computers: Self { .global("computers", []) }
}

extension Preferences.Key where Value == String? {
  static var lastComputerID: Self { .global("lastComputerID", nil) }
  static var agent: Self { .computer("agent", nil) }
}

extension Preferences.Key where Value == SessionRow? {
  static var selectedSession: Self { .global("selectedSession", nil) }
}

extension Preferences.Key where Value == Set<String> {
  static var collapsedGroups: Self { .computer("collapsedGroups", []) }
}

extension Preferences.Key where Value == ModelChoice? {
  static var model: Self { .computer("model", nil) }
}

/// Lets the store drop a key instead of writing `null` when a value is an
/// optional that became nil.
private protocol AnyOptional {
  var isNil: Bool { get }
}

extension Optional: AnyOptional {
  var isNil: Bool { self == nil }
}
