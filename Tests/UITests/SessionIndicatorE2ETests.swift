import XCTest

/// Live suite for the sidebar session indicator: needs a real OpenCode server
/// reachable from the test host (OPENCODE_E2E_URL). The runnable/busy pass
/// additionally needs a model configured on the server; it is gated behind
/// OPENCODE_UI_INDICATOR_LIVE and skipped otherwise, so CI (fixture server,
/// no model) runs only the idle assertions.
@MainActor
final class SessionIndicatorE2ETests: XCTestCase {
  private let url = ProcessInfo.processInfo.environment["OPENCODE_E2E_URL"] ?? ""
  private let devPassword = ProcessInfo.processInfo.environment["OPENCODE_E2E_PASSWORD"] ?? ""
  private let allowsLiveRun =
    ProcessInfo.processInfo.environment["OPENCODE_UI_INDICATOR_LIVE"] == "1"

  private func requireServer() throws {
    try XCTSkipIf(url.isEmpty, "OPENCODE_E2E_URL is not set; skipping live-server test")
  }

  override func setUp() {
    continueAfterFailure = false
  }

  private func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["OPENCODE_E2E_URL"] = url
    app.launchEnvironment["OPENCODE_E2E_PASSWORD"] = devPassword
    app.launchEnvironment["OPENCODE_E2E_NAME"] = "Indicator E2E"
    app.launch()
    return app
  }

  private func dots(_ app: XCUIApplication) -> XCUIElementQuery {
    app.descendants(matching: .any).matching(identifier: "session.status")
  }

  private func labels(_ app: XCUIApplication) -> [String] {
    var out: [String] = []
    let query = app.descendants(matching: .any).matching(identifier: "session.status")
    for index in 0..<query.count {
      out.append(query.element(boundBy: index).label)
    }
    return out
  }

  func testIdleIndicatorShownForFreshSessions() throws {
    try requireServer()
    let app = launch()
    app.buttons["chat.menu"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "session.row")
        .firstMatch.waitForExistence(timeout: 20)
    )
    let seen = labels(app)
    XCTAssertTrue(seen.contains("Session idle"), "expected an idle row, saw \(seen)")
  }

  func testRunMovesRowRunningThenIdle() throws {
    try XCTSkipIf(!allowsLiveRun, "needs a model on the server; set OPENCODE_UI_INDICATOR_LIVE=1")
    try requireServer()
    let app = launch()
    app.buttons["chat.menu"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "session.row")
        .firstMatch.waitForExistence(timeout: 20)
    )
    app.descendants(matching: .any).matching(identifier: "session.row").element(boundBy: 0).tap()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "composer.field")
        .firstMatch.waitForExistence(timeout: 20)
    )

    let slow =
      ProcessInfo.processInfo.environment["OPENCODE_UI_INDICATOR_PROMPT"]
      ?? "Räkna upp 1 till 25, ett tal per mening. Svara sedan med ordet färdig."
    app.descendants(matching: .any).matching(identifier: "composer.field").firstMatch.tap()
    app.typeText("\(slow)\n")

    app.buttons["chat.menu"].tap()
    var sawRunning = false
    var sawIdleAgain = false
    let deadline = Date().addingTimeInterval(180)
    while Date() < deadline && !(sawRunning && sawIdleAgain) {
      let seen = labels(app)
      if seen.contains("Session running") { sawRunning = true }
      if sawRunning && seen.contains("Session idle") { sawIdleAgain = true }
      usleep(1_000_000)
    }
    XCTAssertTrue(sawRunning, "row never showed running")
    XCTAssertTrue(sawIdleAgain, "row never returned to idle")
  }
}
