import XCTest

/// E2E for the per-row archive flow: long-press a session row, pick Archive in
/// the context menu and the row disappears — first optimistically, then it must
/// stay hidden after a fresh list load (the API's list does not hide archived
/// sessions, filtering happens in the model).
///
/// Needs OPENCODE_E2E_URL (fixture server or real server), so it skips when run
/// bare. When OPENCODE_ARCHIVE_SHOTS=1 an extra test records the flow as
/// keepAlways screenshots in the result bundle: list before, the context menu
/// popover, and the list after the row is gone.
@MainActor
final class SessionArchiveE2ETests: XCTestCase {
  private let url = ProcessInfo.processInfo.environment["OPENCODE_E2E_URL"] ?? ""
  private let devPassword = ProcessInfo.processInfo.environment["OPENCODE_E2E_PASSWORD"] ?? ""
  private let shots = ProcessInfo.processInfo.environment["OPENCODE_ARCHIVE_SHOTS"] == "1"

  override func setUp() {
    continueAfterFailure = false
  }

  private func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["OPENCODE_E2E_URL"] = url
    app.launchEnvironment["OPENCODE_E2E_PASSWORD"] = devPassword
    app.launchEnvironment["OPENCODE_E2E_NAME"] = "Archive E2E"
    app.launch()
    return app
  }

  private func rowCount(_ app: XCUIApplication) -> Int {
    app.descendants(matching: .any).matching(identifier: "session.row").count
  }

  private func openSidebar(_ app: XCUIApplication) {
    app.buttons["chat.menu"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "session.row")
        .firstMatch.waitForExistence(timeout: 20)
    )
  }

  private func firstRow(_ app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "session.row").firstMatch
  }

  private func archive(_ app: XCUIApplication, initialCount: Int) {
    firstRow(app).press(forDuration: 1.2)
    let archiveButton = app.buttons["session.archive"]
    XCTAssertTrue(archiveButton.waitForExistence(timeout: 10), "context menu did not show Archive")
    archiveButton.tap()

    var gone = false
    let optimistic = Date().addingTimeInterval(10)
    while Date() < optimistic && !gone {
      gone = rowCount(app) == initialCount - 1
      usleep(500_000)
    }
    XCTAssertTrue(gone, "row did not disappear right after Archive")
  }

  /// Proves both halves of the contract: the optimistic hide and the persistent
  /// one (server accepted the PATCH, model filter hides it on a fresh load).
  func testArchiveRowDisappearsAndStaysHiddenAfterRefresh() throws {
    try XCTSkipIf(url.isEmpty, "OPENCODE_E2E_URL is not set")
    let app = launch()
    openSidebar(app)
    let before = rowCount(app)
    XCTAssertGreaterThanOrEqual(before, 1, "expected at least one session row")

    archive(app, initialCount: before)

    app.buttons["sidebar.computer"].tap()
    XCTAssertTrue(app.buttons["Refresh sessions"].waitForExistence(timeout: 10))
    app.buttons["Refresh sessions"].tap()

    var reconciled = false
    let deadline = Date().addingTimeInterval(20)
    while Date() < deadline && !reconciled {
      reconciled = rowCount(app) == before - 1
      usleep(1_000_000)
    }
    XCTAssertEqual(rowCount(app), before - 1, "archived row re-appeared after refresh")
  }

  /// Records what the long-press popover actually looks like. Skipped unless
  /// OPENCODE_ARCHIVE_SHOTS=1 so normal runs stay quiet. Frames are embedded in
  /// the result bundle as keepAlways attachments (archive-1-list,
  /// archive-2-popover, archive-3-after) and exported by the driver script.
  func testArchivePopoverScreenshots() throws {
    try XCTSkipIf(!shots || url.isEmpty, "needs OPENCODE_ARCHIVE_SHOTS=1 and OPENCODE_E2E_URL")
    let app = launch()
    openSidebar(app)
    usleep(800_000)
    attach("archive-1-list")

    firstRow(app).press(forDuration: 1.2)
    let archiveButton = app.buttons["session.archive"]
    XCTAssertTrue(archiveButton.waitForExistence(timeout: 10), "context menu did not show Archive")
    usleep(8_000_000)
    attach("archive-2-popover")

    let before = rowCount(app)
    archiveButton.tap()
    usleep(600_000)
    attach("archive-3-after")

    var gone = false
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline && !gone {
      gone = rowCount(app) == before - 1
      usleep(500_000)
    }
    XCTAssertTrue(gone, "row did not disappear after Archive")
    usleep(4_000_000)
  }

  private func attach(_ name: String) {
    let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
    let dir =
      FileManager.default.temporaryDirectory
      .appendingPathComponent("archive-shots", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let data = XCUIScreen.main.screenshot().pngRepresentation
    try? data.write(to: dir.appendingPathComponent("\(name).png"))
  }
}
