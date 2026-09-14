import XCTest

// Live-server suite: needs a real OpenCode server over Tailscale. Credentials
// come from the environment (see .env.example); tests are skipped when they
// are not set. Run locally via `make e2e`; CI runs the offline suites only.
@MainActor
final class SessionsLiveE2ETests: XCTestCase {
  private let tailnetURL = ProcessInfo.processInfo.environment["OPENCODE_E2E_URL"] ?? ""
  private let devPassword = ProcessInfo.processInfo.environment["OPENCODE_E2E_PASSWORD"] ?? ""

  private func requireServer() throws {
    try XCTSkipIf(tailnetURL.isEmpty, "OPENCODE_E2E_URL is not set; skipping live-server test")
  }

  override func setUp() {
    continueAfterFailure = false
  }

  private func launch(url: String, password: String, name: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["OPENCODE_E2E_URL"] = url
    app.launchEnvironment["OPENCODE_E2E_PASSWORD"] = password
    app.launchEnvironment["OPENCODE_E2E_NAME"] = name
    app.launch()
    return app
  }

  func testListShowsSession() throws {
    try requireServer()
    let app = launch(url: tailnetURL, password: devPassword, name: "E2E list")
    app.buttons["chat.menu"].tap()
    let rows = app.descendants(matching: .any).matching(identifier: "session.row")
    XCTAssertTrue(rows.element(boundBy: 0).waitForExistence(timeout: 20))
  }

  func testWrongPasswordShowsFailure() throws {
    try requireServer()
    let app = launch(url: tailnetURL, password: "wrong", name: "E2E wrong")
    XCTAssertTrue(app.staticTexts["Wrong password"].waitForExistence(timeout: 20))
  }

  func testOpenSessionFromSidebar() throws {
    try requireServer()
    let app = launch(url: tailnetURL, password: devPassword, name: "E2E chat")
    app.buttons["chat.menu"].tap()
    let rows = app.descendants(matching: .any).matching(identifier: "session.row")
    XCTAssertTrue(rows.element(boundBy: 0).waitForExistence(timeout: 20))
    rows.element(boundBy: 0).tap()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "composer.field").firstMatch
        .waitForExistence(timeout: 20)
    )
  }

  func testSidebarToSettingsToAddComputer() throws {
    try requireServer()
    let app = launch(url: tailnetURL, password: devPassword, name: "E2E shell")
    app.buttons["chat.menu"].tap()
    XCTAssertTrue(app.buttons["sidebar.newSession"].waitForExistence(timeout: 10))
    app.buttons["sidebar.settings"].tap()
    XCTAssertTrue(app.buttons["settings.addComputer"].waitForExistence(timeout: 10))
    app.buttons["settings.addComputer"].tap()
    XCTAssertTrue(app.buttons["addComputer.connect"].waitForExistence(timeout: 10))
  }
}
