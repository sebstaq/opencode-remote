import XCTest

// Live-server suite: needs a real OpenCode server over Tailscale. Credentials
// come from the environment (see .env.example); tests are skipped when they
// are not set. Run locally via `make e2e`; CI runs the offline suites only.
@MainActor
final class ComposerLiveE2ETests: XCTestCase {
  private let tailnetURL = ProcessInfo.processInfo.environment["OPENCODE_E2E_URL"] ?? ""
  private let devPassword = ProcessInfo.processInfo.environment["OPENCODE_E2E_PASSWORD"] ?? ""

  override func setUp() {
    continueAfterFailure = false
  }

  private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func launch(draft: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["OPENCODE_E2E_URL"] = tailnetURL
    app.launchEnvironment["OPENCODE_E2E_PASSWORD"] = devPassword
    app.launchEnvironment["OPENCODE_E2E_NAME"] = "E2E composer"
    app.launchEnvironment["OPENCODE_UI_DRAFT"] = draft
    app.launch()
    return app
  }

  private func openNewSession(_ app: XCUIApplication) {
    let menu = element(app, "chat.menu")
    XCTAssertTrue(menu.waitForExistence(timeout: 20))
    menu.tap()

    let newSession = element(app, "sidebar.newSession")
    XCTAssertTrue(newSession.waitForExistence(timeout: 20))
    newSession.tap()

    let create = element(app, "newSession.create")
    XCTAssertTrue(create.waitForExistence(timeout: 20))
    expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: create)
    waitForExpectations(timeout: 30)
    create.tap()
  }

  func testSendReceivesReply() throws {
    try XCTSkipIf(tailnetURL.isEmpty, "OPENCODE_E2E_URL is not set; skipping live-server test")
    let app = launch(draft: "Reply with exactly one word: pong")
    openNewSession(app)

    let send = element(app, "composer.send")
    XCTAssertTrue(send.waitForExistence(timeout: 10))
    send.tap()

    let reply = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS[c] %@", "pong")
    ).firstMatch
    XCTAssertTrue(reply.waitForExistence(timeout: 60))
  }

  /// A freshly opened session is idle: the composer offers send, never stop.
  /// This is the "absence means idle" default on the shared run-state store.
  func testFreshSessionIsIdle() throws {
    try XCTSkipIf(tailnetURL.isEmpty, "OPENCODE_E2E_URL is not set; skipping live-server test")
    let app = launch(draft: "")
    openNewSession(app)

    XCTAssertTrue(element(app, "composer.send").waitForExistence(timeout: 20))
    XCTAssertFalse(element(app, "composer.stop").exists)
  }

  /// The regression guard for the stuck stop button: when the run finishes the
  /// composer must return to send. `RunStateStore` reconciles to idle even if
  /// the `session.idle` event was missed.
  func testStopButtonClearsWhenRunFinishes() throws {
    try XCTSkipIf(tailnetURL.isEmpty, "OPENCODE_E2E_URL is not set; skipping live-server test")
    let app = launch(draft: "Reply with exactly one word: pong")
    openNewSession(app)

    let send = element(app, "composer.send")
    XCTAssertTrue(send.waitForExistence(timeout: 10))
    send.tap()

    XCTAssertTrue(element(app, "composer.stop").waitForExistence(timeout: 30))
    let reply = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS[c] %@", "pong")
    ).firstMatch
    XCTAssertTrue(reply.waitForExistence(timeout: 60))

    XCTAssertTrue(
      element(app, "composer.send").waitForExistence(timeout: 30),
      "stop button did not clear after the run finished")
    XCTAssertFalse(element(app, "composer.stop").exists)
  }

  func testAbortStopsRun() throws {
    try XCTSkipIf(tailnetURL.isEmpty, "OPENCODE_E2E_URL is not set; skipping live-server test")
    let app = launch(draft: "Count from 1 to 500 slowly, one number per line. Do not use tools.")
    openNewSession(app)

    let send = element(app, "composer.send")
    XCTAssertTrue(send.waitForExistence(timeout: 10))
    send.tap()

    let stop = element(app, "composer.stop")
    XCTAssertTrue(stop.waitForExistence(timeout: 30))
    stop.tap()
    XCTAssertTrue(element(app, "composer.send").waitForExistence(timeout: 30))
  }
}
