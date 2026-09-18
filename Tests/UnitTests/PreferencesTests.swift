import XCTest

@testable import OpenCodeRemote

/// The store is the one thing every UI preference goes through, so its scoping
/// and defaults are worth pinning: a mistake here would silently leak one
/// computer's choices into another, or lose the last conversation on launch.
@MainActor
final class PreferencesTests: XCTestCase {
  /// A throwaway suite, removed afterwards. `setUp` is nonisolated and cannot
  /// touch main-actor state, so each test builds and tears down its own store.
  private func withPreferences(_ body: (Preferences, UserDefaults) throws -> Void) rethrows {
    let suite = "PreferencesTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(Preferences(defaults: defaults), defaults)
  }

  func testEmptyStoreReturnsDefaults() {
    withPreferences { prefs, _ in
      XCTAssertNil(prefs[.lastComputerID])
      XCTAssertNil(prefs[.selectedSession])
      XCTAssertEqual(prefs[.collapsedGroups], [])
      XCTAssertEqual(prefs[.computers], [])
    }
  }

  func testValuesSurviveAReload() {
    withPreferences { prefs, defaults in
      prefs[.lastComputerID] = "computer-1"
      prefs[.collapsedGroups] = ["api", "web"]

      let reloaded = Preferences(defaults: defaults)
      XCTAssertEqual(reloaded[.lastComputerID], "computer-1")
      XCTAssertEqual(reloaded[.collapsedGroups], ["api", "web"])
    }
  }

  func testScopedKeysDoNotCollideBetweenComputers() {
    withPreferences { prefs, _ in
      prefs[.lastComputerID] = "computer-1"
      prefs[.collapsedGroups] = ["api"]
      prefs[.agent] = "build"
      prefs[.model] = ModelChoice(providerID: "opencode", modelID: "m1")

      prefs[.lastComputerID] = "computer-2"
      XCTAssertEqual(prefs[.collapsedGroups], [])
      XCTAssertNil(prefs[.agent])
      XCTAssertNil(prefs[.model])
      prefs[.collapsedGroups] = ["web"]

      prefs[.lastComputerID] = "computer-1"
      XCTAssertEqual(prefs[.collapsedGroups], ["api"])
      XCTAssertEqual(prefs[.agent], "build")
      XCTAssertEqual(prefs[.model], ModelChoice(providerID: "opencode", modelID: "m1"))

      prefs[.lastComputerID] = "computer-2"
      XCTAssertEqual(prefs[.collapsedGroups], ["web"])
    }
  }

  func testScopedWriteDoesNotTouchGlobalKeys() {
    withPreferences { prefs, _ in
      prefs[.lastComputerID] = "computer-1"
      prefs[.collapsedGroups] = ["api"]
      XCTAssertEqual(prefs[.lastComputerID], "computer-1")
    }
  }

  func testSettingAnOptionalToNilRemovesTheKey() {
    withPreferences { prefs, defaults in
      prefs[.lastComputerID] = "computer-1"
      prefs[.lastComputerID] = nil

      XCTAssertNil(Preferences(defaults: defaults)[.lastComputerID])
    }
  }

  func testSelectedSessionRoundTrips() {
    withPreferences { prefs, defaults in
      let row = SessionRow(
        id: "ses_1",
        title: "Rate limiting on /login",
        updated: Date(timeIntervalSince1970: 1_700_000_000),
        group: "beta-api",
        isChild: true
      )
      prefs[.selectedSession] = row

      XCTAssertEqual(Preferences(defaults: defaults)[.selectedSession], row)
    }
  }

  func testResetRemovesOnlyOwnKeys() {
    withPreferences { prefs, defaults in
      prefs[.lastComputerID] = "computer-1"
      prefs[.collapsedGroups] = ["api"]
      defaults.set("unrelated", forKey: "someoneElse")

      prefs.reset()

      XCTAssertNil(prefs[.lastComputerID])
      XCTAssertEqual(prefs[.collapsedGroups], [])
      XCTAssertEqual(defaults.string(forKey: "someoneElse"), "unrelated")
    }
  }

  func testComputerStoreRemembersTheLastUsedComputer() {
    withPreferences { prefs, defaults in
      let store = ComputerStore(prefs: prefs)
      let first = Computer(name: "First", url: URL(string: "https://first.ts.net")!)
      let second = Computer(name: "Second", url: URL(string: "https://second.ts.net")!)
      store.add(first)
      store.add(second)

      XCTAssertEqual(store.lastUsed?.id, second.id, "with no recorded choice, the last added wins")

      store.markUsed(first)
      XCTAssertEqual(ComputerStore(prefs: Preferences(defaults: defaults)).lastUsed?.id, first.id)
    }
  }
}
