import XCTest

// Offline suite: runs everywhere (CI included); no real server needed.
@MainActor
final class SessionsOfflineE2ETests: XCTestCase {
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

  func testEmptyState() {
    let app = launch(url: "http://10.0.2.2:4097", password: "unused", name: "E2E empty")
    app.buttons["chat.menu"].tap()
    XCTAssertTrue(app.staticTexts["No sessions yet"].waitForExistence(timeout: 20))
  }

  func testUnreachableShowsFailure() {
    let app = launch(url: "http://10.0.2.2:4999", password: "unused", name: "E2E down")
    XCTAssertTrue(app.staticTexts["Can't reach the computer"].waitForExistence(timeout: 20))
  }
}
