import XCTest

// Live-server suite: needs a real OpenCode server with a working model over
// Tailscale (`OPENCODE_E2E_URL` / `OPENCODE_E2E_PASSWORD`). Skipped when unset,
// so the offline CI pass is unaffected. Run locally via `make e2e`.
//
// The prompt reads a path outside the workspace, which makes the server raise
// an `external_directory` permission (the default action is `ask`). That gives
// the app a real pending request to show, persist and resolve.
@MainActor
final class PermissionLiveE2ETests: XCTestCase {
  private let tailnetURL = ProcessInfo.processInfo.environment["OPENCODE_E2E_URL"] ?? ""
  private let devPassword = ProcessInfo.processInfo.environment["OPENCODE_E2E_PASSWORD"] ?? ""
  private let shots = ProcessInfo.processInfo.environment["OPENCODE_PERMISSION_SHOTS"] == "1"

  override func setUp() {
    continueAfterFailure = false
  }

  /// Writes a frame to the result bundle and to the simulator's tmp dir (picked
  /// up by the driver script). Only when `OPENCODE_PERMISSION_SHOTS=1`.
  private func attach(_ name: String) {
    guard shots else { return }
    let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("permission-shots", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let data = XCUIScreen.main.screenshot().pngRepresentation
    try? data.write(to: dir.appendingPathComponent("\(name).png"))
  }

  private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func launch(draft: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["OPENCODE_E2E_URL"] = tailnetURL
    app.launchEnvironment["OPENCODE_E2E_PASSWORD"] = devPassword
    app.launchEnvironment["OPENCODE_E2E_NAME"] = "E2E permission"
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

  func testPermissionCardRendersInTimelinePersistsAndResolves() throws {
    try XCTSkipIf(tailnetURL.isEmpty, "OPENCODE_E2E_URL is not set; skipping live-server test")
    let app = launch(
      draft:
        "Use the read tool to read the file /etc/hostname exactly once, then reply with exactly one word: PERMISSIONOK. Do not use any other tool."
    )
    openNewSession(app)

    let send = element(app, "composer.send")
    XCTAssertTrue(send.waitForExistence(timeout: 10))
    send.tap()

    // The request renders as a timeline item, not a modal: the composer stays
    // available while it is pending.
    let allow = element(app, "permission.allow")
    XCTAssertTrue(allow.waitForExistence(timeout: 120), "permission card did not appear")
    XCTAssertTrue(element(app, "permission.always").exists)
    XCTAssertTrue(element(app, "permission.deny").exists)
    XCTAssertTrue(element(app, "composer.field").exists)
    attach("permission-1-card")

    // Anchoring, deterministic and independent of a model reply: the card sits
    // under the tool block it belongs to. A tail-rendered card would be after
    // every message.
    let readBlock = app.staticTexts.matching(
      NSPredicate(format: "label BEGINSWITH[c] %@", "read")
    ).firstMatch
    XCTAssertTrue(readBlock.waitForExistence(timeout: 30), "tool block missing")
    let card = element(app, "permission.allow")
    XCTAssertGreaterThan(
      card.frame.minY, readBlock.frame.maxY - 1, "card is not under its tool block")

    // Persistence: a relaunch must recover the still-pending request from
    // `GET /permission`, because `/event` has no replay.
    app.terminate()
    app.launch()
    let menu = element(app, "chat.menu")
    XCTAssertTrue(menu.waitForExistence(timeout: 30))
    menu.tap()
    let row = app.descendants(matching: .any).matching(identifier: "session.row").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 30))
    row.tap()
    let recovered = element(app, "permission.allow")
    XCTAssertTrue(recovered.waitForExistence(timeout: 30), "pending permission did not survive relaunch")
    attach("permission-2-recovered")

    // Resolving clears the buttons, the run finishes, and the answer streams
    // into the same thread.
    recovered.tap()
    XCTAssertTrue(element(app, "composer.send").waitForExistence(timeout: 120))
    XCTAssertFalse(element(app, "permission.allow").exists)
    attach("permission-3-resolved")

    // The record is kept, still under the tool block.
    let history = app.staticTexts["Allowed once"]
    XCTAssertTrue(history.waitForExistence(timeout: 30), "resolved permission was not kept as a record")
    XCTAssertGreaterThan(
      history.frame.minY, readBlock.frame.maxY - 1, "record is not under its tool block")
  }
}
