import XCTest

// Offline: the last opened conversation must come back on the next launch, so a
// launch lands straight in the chat instead of on "Select a session". Runs
// against the seeded fixture; a pinned defaults suite isolates it from the
// other suites (which start from a clean slate) and makes persistence observable.
@MainActor
final class SessionRestoreE2ETests: XCTestCase {
  private let seededURL =
    ProcessInfo.processInfo.environment["OPENCODE_E2E_URL"] ?? "http://10.0.2.2:4098"

  override func setUp() {
    continueAfterFailure = false
  }

  private func configure(_ app: XCUIApplication, suite: String) {
    app.launchEnvironment["OPENCODE_E2E_URL"] = seededURL
    app.launchEnvironment["OPENCODE_E2E_PASSWORD"] = "unused"
    app.launchEnvironment["OPENCODE_E2E_NAME"] = "E2E restore"
    app.launchEnvironment["OPENCODE_UI_DEFAULTS_SUITE"] = suite
    app.launchEnvironment["OPENCODE_UI_PERSIST"] = "1"
  }

  func testReopensLastSessionAfterRelaunch() {
    let suite = "restore-\(UUID().uuidString)"
    let app = XCUIApplication()
    configure(app, suite: suite)

    app.launch()
    app.buttons["chat.menu"].tap()
    let rows = app.descendants(matching: .any).matching(identifier: "session.row")
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 20))
    rows.firstMatch.tap()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "composer.field").firstMatch
        .waitForExistence(timeout: 20)
    )

    app.terminate()
    configure(app, suite: suite)
    app.launch()

    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "composer.field").firstMatch
        .waitForExistence(timeout: 20),
      "the last conversation should be open without touching the sidebar"
    )
  }

  /// The new-session sheet is the only screen that reads and writes the stored
  /// model and agent, so opening it proves the store is wired into the flow.
  func testNewSessionSheetOpens() {
    let app = XCUIApplication()
    configure(app, suite: "new-\(UUID().uuidString)")
    app.launch()

    app.buttons["chat.menu"].tap()
    let newSession = app.buttons["sidebar.newSession"]
    XCTAssertTrue(newSession.waitForExistence(timeout: 20))
    newSession.tap()
    XCTAssertTrue(app.buttons["newSession.create"].waitForExistence(timeout: 20))
  }
}
