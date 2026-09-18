import XCTest

/// Tool-call rows should name *what* the call does, not just that it ran: the
/// file a read touches (with its line range), the command a shell runs (with a
/// non-zero exit). The offline pass renders them from the debug fixture; the
/// live pass drives a real model on a real server and is skipped otherwise.
@MainActor
final class ToolTimelineE2ETests: XCTestCase {
  private let url = ProcessInfo.processInfo.environment["OPENCODE_E2E_URL"] ?? ""
  private let devPassword = ProcessInfo.processInfo.environment["OPENCODE_E2E_PASSWORD"] ?? ""
  private let allowsLiveRun = ProcessInfo.processInfo.environment["OPENCODE_UI_TOOL_LIVE"] == "1"

  override func setUp() {
    continueAfterFailure = false
  }

  private func labels(_ app: XCUIApplication, identifier: String) -> [String] {
    var out: [String] = []
    let query = app.descendants(matching: .any).matching(identifier: identifier)
    for index in 0..<query.count {
      out.append(query.element(boundBy: index).label)
    }
    return out
  }

  func testFixtureRendersRichReadAndBashRows() {
    let app = XCUIApplication()
    app.launchEnvironment["OPENCODE_UI_FIXTURE"] = "chat-tools"
    app.launch()

    let rows = app.descendants(matching: .any).matching(identifier: "timeline.tool")
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 20))
    let seen = labels(app, identifier: "timeline.tool")
    XCTAssertEqual(seen.count, 4, "expected four fixture rows, saw \(seen)")

    XCTAssertTrue(
      seen.contains("Read, src/session.ts · lines 12–40 of 300"),
      "read row did not carry its path and line range, saw \(seen)"
    )
    XCTAssertTrue(
      seen.contains("Bash, npm test · exit 1"),
      "bash row did not carry its command and exit code, saw \(seen)"
    )
    XCTAssertTrue(seen.contains("Bash, git status"), "pending bash row lost its command, saw \(seen)")
    XCTAssertTrue(seen.contains("Grep, toolCallID"), "grep row lost its pattern, saw \(seen)")
  }

  func testLiveReadAndBashRenderContext() throws {
    try XCTSkipIf(url.isEmpty, "OPENCODE_E2E_URL is not set; skipping live-server test")
    try XCTSkipIf(!allowsLiveRun, "needs a model on the server; set OPENCODE_UI_TOOL_LIVE=1")

    let app = XCUIApplication()
    app.launchEnvironment["OPENCODE_E2E_URL"] = url
    app.launchEnvironment["OPENCODE_E2E_PASSWORD"] = devPassword
    app.launchEnvironment["OPENCODE_E2E_NAME"] = "Tool E2E"
    app.launchEnvironment["OPENCODE_UI_MODEL"] = "opencode/big-pickle"
    app.launch()

    let menu = app.descendants(matching: .any).matching(identifier: "chat.menu").firstMatch
    XCTAssertTrue(menu.waitForExistence(timeout: 20))
    menu.tap()
    let newSession = app.descendants(matching: .any).matching(identifier: "sidebar.newSession").firstMatch
    XCTAssertTrue(newSession.waitForExistence(timeout: 20))
    newSession.tap()
    let create = app.descendants(matching: .any).matching(identifier: "newSession.create").firstMatch
    XCTAssertTrue(create.waitForExistence(timeout: 20))
    expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: create)
    waitForExpectations(timeout: 30)
    create.tap()

    let field = app.descendants(matching: .any).matching(identifier: "composer.field").firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 20))
    field.tap()
    app.typeText(
      "Run the shell command `echo TOOLMARKER` and read the file README.md. Then reply DONE.\n")

    let deadline = Date().addingTimeInterval(180)
    var seen: [String] = []
    while Date() < deadline {
      seen = labels(app, identifier: "timeline.tool")
      if seen.contains(where: { $0.contains("echo TOOLMARKER") }),
        seen.contains(where: { $0.contains("README.md") })
      {
        break
      }
      usleep(1_000_000)
    }
    XCTAssertTrue(
      seen.contains(where: { $0.contains("echo TOOLMARKER") }),
      "shell row did not show the command, saw \(seen)"
    )
    XCTAssertTrue(
      seen.contains(where: { $0.contains("README.md") }),
      "read row did not show the path, saw \(seen)"
    )
  }
}
