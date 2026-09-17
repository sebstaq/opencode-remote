import XCTest

@testable import OpenCodeRemote

/// The rule that fixes the stuck spinner / stop button: `GET /session/status`
/// lists only active sessions, so the snapshot reconcile is authoritative and
/// *absence means idle*. The old code merged present entries only, so a missed
/// `session.idle` could never be corrected.
@MainActor
final class RunStateStoreTests: XCTestCase {
  func testUnknownSessionIsIdle() {
    let store = RunStateStore()
    XCTAssertEqual(store.state(for: "ses_x"), .idle)
  }

  func testSetThenIdleClears() {
    let store = RunStateStore()
    store.set(.busy, for: "ses_a")
    XCTAssertEqual(store.state(for: "ses_a"), .busy)
    store.set(.retry, for: "ses_a")
    XCTAssertEqual(store.state(for: "ses_a"), .retry)
    store.set(.idle, for: "ses_a")
    XCTAssertEqual(store.state(for: "ses_a"), .idle)
  }

  func testReconcileClearsASessionMissingFromTheSnapshot() {
    let store = RunStateStore()
    store.set(.busy, for: "ses_a")
    store.set(.busy, for: "ses_b")

    // `ses_a` went idle while the `session.idle` event was missed; the snapshot
    // only lists the still-active `ses_b`.
    store.reconcile(active: ["ses_b": .busy])

    XCTAssertEqual(store.state(for: "ses_a"), .idle, "absent from the snapshot means idle")
    XCTAssertEqual(store.state(for: "ses_b"), .busy)
  }

  func testReconcileEmptySnapshotClearsEverything() {
    let store = RunStateStore()
    store.set(.busy, for: "ses_a")
    store.reconcile(active: [:])
    XCTAssertEqual(store.state(for: "ses_a"), .idle)
  }

  func testReconcileTracksSessionsItHasNotSeen() {
    let store = RunStateStore()
    store.reconcile(active: ["ses_new": .retry])
    XCTAssertEqual(store.state(for: "ses_new"), .retry)
  }

  func testInitIgnoresIdleEntries() {
    let store = RunStateStore(states: ["ses_a": .busy, "ses_b": .idle])
    XCTAssertEqual(store.state(for: "ses_a"), .busy)
    XCTAssertEqual(store.state(for: "ses_b"), .idle)
  }

  func testRunStateMapsServerStatus() {
    XCTAssertEqual(RunState(ServerStatus(raw: "busy")), .busy)
    XCTAssertEqual(RunState(ServerStatus(raw: "retry")), .retry)
    XCTAssertEqual(RunState(ServerStatus(raw: "idle")), .idle)
    XCTAssertEqual(RunState(ServerStatus(raw: "unexpected")), .idle)
  }
}
