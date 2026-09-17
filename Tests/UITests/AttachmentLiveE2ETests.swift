import XCTest

// Live-server suite: needs a real OpenCode server over Tailscale. Credentials
// come from the environment (see .env.example); the test is skipped when they
// are not set. It pins a vision-capable model and seeds a solid-red image
// (DEBUG seam, `OPENCODE_UI_ATTACHMENT`) so the picker is not driven.
@MainActor
final class AttachmentLiveE2ETests: XCTestCase {
  private let tailnetURL = ProcessInfo.processInfo.environment["OPENCODE_E2E_URL"] ?? ""
  private let devPassword = ProcessInfo.processInfo.environment["OPENCODE_E2E_PASSWORD"] ?? ""

  override func setUp() {
    continueAfterFailure = false
  }

  private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
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

  func testSendImageGetsVisionReply() throws {
    try XCTSkipIf(tailnetURL.isEmpty, "OPENCODE_E2E_URL is not set; skipping live-server test")

    let app = XCUIApplication()
    app.launchEnvironment["OPENCODE_E2E_URL"] = tailnetURL
    app.launchEnvironment["OPENCODE_E2E_PASSWORD"] = devPassword
    app.launchEnvironment["OPENCODE_E2E_NAME"] = "E2E attachment"
    app.launchEnvironment["OPENCODE_UI_DRAFT"] = "What color is this image? Reply with one word."
    app.launchEnvironment["OPENCODE_UI_ATTACHMENT"] = "1"
    app.launchEnvironment["OPENCODE_UI_MODEL"] = "opencode/muse-spark-1.3-contributor-free"
    app.launch()
    openNewSession(app)

    // The seeded image shows as a removable composer attachment.
    XCTAssertTrue(element(app, "composer.removeAttachment").waitForExistence(timeout: 10))

    let send = element(app, "composer.send")
    XCTAssertTrue(send.waitForExistence(timeout: 10))
    send.tap()

    // The sent user message renders the image, and the model sees the colour.
    // The assistant reply is a markdown `TextView`, not a `StaticText`.
    XCTAssertTrue(element(app, "timeline.image").waitForExistence(timeout: 30))
    let reply = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", "red", "red")
    ).firstMatch
    XCTAssertTrue(reply.waitForExistence(timeout: 180))
  }
}
