import XCTest

// Offline suite: runs everywhere (CI included); no real server needed.
// Fixture URLs are overridable via the environment; the defaults assume a
// local development setup where the host fixture is reachable at 10.0.2.2.
@MainActor
final class SessionsOfflineE2ETests: XCTestCase {
  private let emptyURL =
    ProcessInfo.processInfo.environment["OPENCODE_E2E_EMPTY_URL"] ?? "http://10.0.2.2:4097"
  private let downURL =
    ProcessInfo.processInfo.environment["OPENCODE_E2E_DOWN_URL"] ?? "http://10.0.2.2:4999"
  private let seededURL =
    ProcessInfo.processInfo.environment["OPENCODE_E2E_URL"] ?? "http://10.0.2.2:4098"

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
    let app = launch(url: emptyURL, password: "unused", name: "E2E empty")
    app.buttons["chat.menu"].tap()
    XCTAssertTrue(app.staticTexts["No sessions yet"].waitForExistence(timeout: 20))
  }

  func testUnreachableShowsFailure() {
    let app = launch(url: downURL, password: "unused", name: "E2E down")
    XCTAssertTrue(app.staticTexts["Can't reach the computer"].waitForExistence(timeout: 20))
  }

  func testGroupCollapseHidesRowsAndExpandRestoresThem() throws {
    let app = launch(url: seededURL, password: "unused", name: "E2E collapse")
    app.buttons["chat.menu"].tap()
    let rowQuery = app.descendants(matching: .any).matching(identifier: "session.row")
    XCTAssertTrue(rowQuery.firstMatch.waitForExistence(timeout: 20))
    let before = rowQuery.count
    try XCTSkipIf(before < 2, "needs at least two seeded sessions in one group")

    let header = app.descendants(matching: .any).matching(identifier: "session.group").firstMatch
    XCTAssertTrue(header.waitForExistence(timeout: 10))
    header.tap()
    var collapsed = 0
    let collapseDeadline = Date().addingTimeInterval(10)
    while Date() < collapseDeadline && collapsed == 0 {
      collapsed = rowQuery.count
      usleep(500_000)
    }
    XCTAssertEqual(collapsed, 0, "rows still visible after collapsing the group")

    header.tap()
    var expanded = 0
    let expandDeadline = Date().addingTimeInterval(10)
    while Date() < expandDeadline && expanded == 0 {
      expanded = rowQuery.count
      usleep(500_000)
    }
    XCTAssertEqual(expanded, before, "rows did not come back after expanding")
  }
}
