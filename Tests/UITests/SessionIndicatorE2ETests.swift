import XCTest

/// Live suite for the sidebar session indicator: needs a real OpenCode server
/// reachable from the test host (OPENCODE_E2E_URL). The runnable/busy pass
/// additionally needs a model configured on the server; it is gated behind
/// OPENCODE_UI_INDICATOR_LIVE and skipped otherwise, so CI (fixture server,
/// no model) runs only the idle assertions.
///
/// Active sessions (running/retrying) show the spinner (`session.spinner`);
/// idle sessions keep the static dot (`session.status`). The offline fixture
/// pass renders both from the wireframe sample and runs everywhere.
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

  private func labels(_ app: XCUIApplication, identifier: String) -> [String] {
    var out: [String] = []
    let query = app.descendants(matching: .any).matching(identifier: identifier)
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
    let seen = labels(app, identifier: "session.status")
    XCTAssertTrue(seen.contains("Session idle"), "expected an idle row, saw \(seen)")
  }

  /// Offline: the wireframe fixture seeds one running and one retrying row plus
  /// idle ones, so the spinner is verifiable without a live server/model.
  func testFixtureShowsSpinnerForActiveRows() {
    let app = XCUIApplication()
    app.launchEnvironment["OPENCODE_UI_FIXTURE"] = "wireframe"
    app.launch()

    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "session.spinner")
        .firstMatch.waitForExistence(timeout: 20)
    )
    let active = labels(app, identifier: "session.spinner")
    XCTAssertTrue(active.contains("Session running"), "expected a running spinner, saw \(active)")
    XCTAssertTrue(active.contains("Session retrying"), "expected a retrying spinner, saw \(active)")
    let idle = labels(app, identifier: "session.status")
    XCTAssertTrue(idle.contains("Session idle"), "idle rows keep the dot, saw \(idle)")
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
      if labels(app, identifier: "session.spinner").contains("Session running") { sawRunning = true }
      if sawRunning && labels(app, identifier: "session.status").contains("Session idle") {
        sawIdleAgain = true
      }
      usleep(1_000_000)
    }
    XCTAssertTrue(sawRunning, "row never showed the running spinner")
    XCTAssertTrue(sawIdleAgain, "row never returned to idle")
  }
}
