import XCTest

/// Live pagination E2E: seeds a real session with 60 messages (no model needed —
/// `noReply` appends user messages) and drives the app's "load older" flow
/// against a real server. Gated on both the tailnet URL and an explicit opt-in,
/// so ordinary runs and CI stay quiet.
///
///   OPENCODE_E2E_URL=https://host  OPENCODE_E2E_PASSWORD=…  OPENCODE_UI_PAGINATION_LIVE=1
@MainActor
final class PaginationLiveE2ETests: XCTestCase {
  private let url = ProcessInfo.processInfo.environment["OPENCODE_E2E_URL"] ?? ""
  private let password = ProcessInfo.processInfo.environment["OPENCODE_E2E_PASSWORD"] ?? ""
  private let live = ProcessInfo.processInfo.environment["OPENCODE_UI_PAGINATION_LIVE"] == "1"
  private let count = Int(ProcessInfo.processInfo.environment["OPENCODE_UI_PAGINATION_COUNT"] ?? "") ?? 60

  override func setUp() {
    continueAfterFailure = false
  }

  func testLoadOlderPagesThroughLiveHistory() throws {
    try XCTSkipIf(url.isEmpty || !live, "needs OPENCODE_E2E_URL and OPENCODE_UI_PAGINATION_LIVE=1")

    let expectation = expectation(description: "seeded")
    var seeded: Result<String, Error>?
    Task {
      do { seeded = .success(try await seed()) } catch { seeded = .failure(error) }
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 180)
    _ = try seeded?.get()

    let app = XCUIApplication()
    app.launchEnvironment["OPENCODE_E2E_URL"] = url
    app.launchEnvironment["OPENCODE_E2E_PASSWORD"] = password
    app.launchEnvironment["OPENCODE_E2E_NAME"] = "Pagination live"
    app.launch()

    app.buttons["chat.menu"].tap()
    let row = app.descendants(matching: .any).matching(identifier: "session.row").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 30), "no sessions in the sidebar")
    row.tap()

    let button = app.buttons["timeline.loadOlder"]
    let appearDeadline = Date().addingTimeInterval(30)
    while Date() < appearDeadline && !button.exists {
      app.swipeDown()
      usleep(300_000)
    }
    XCTAssertTrue(button.exists, "load-older button did not appear for a long live session")
    XCTAssertFalse(app.staticTexts["marker 001"].exists, "oldest message present before paging")

    // One page covers 50 of 60; the remaining 10 come from a single tap.
    button.tap()
    var reached = false
    let reachDeadline = Date().addingTimeInterval(30)
    while Date() < reachDeadline && !reached {
      app.swipeDown()
      reached = app.staticTexts["marker 001"].exists
      usleep(300_000)
    }
    XCTAssertTrue(reached, "the first live message did not appear after loading older history")
    XCTAssertFalse(button.exists, "load-older button should hide once the history is exhausted")
  }

  private func seed() async throws -> String {
    let sessionID = try await post("/session", body: ["title": "Pagination live"])["id"] as? String ?? ""
    guard !sessionID.isEmpty else { throw XCTSkip("server did not create a session") }
    for i in 1...count {
      let marker = String(format: "marker %03d", i)
      _ = try await post(
        "/session/\(sessionID)/message",
        body: ["parts": [["type": "text", "text": marker]], "noReply": true])
    }
    return sessionID
  }

  private func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
    var request = URLRequest(url: URL(string: url + path)!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let credentials = Data("opencode:\(password)".utf8).base64EncodedString()
    request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, _) = try await URLSession.shared.data(for: request)
    return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
  }
}
