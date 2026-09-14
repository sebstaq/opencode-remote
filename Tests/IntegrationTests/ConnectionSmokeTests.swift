import XCTest

final class ConnectionSmokeTests: XCTestCase {
  func testFixtureServerIsReachable() async throws {
    let environment = ProcessInfo.processInfo.environment
    let base = URL(string: environment["OPENCODE_BASE_URL"] ?? "http://127.0.0.1:4096")!
    var request = URLRequest(url: base.appending(path: "global/health"))
    request.timeoutInterval = 5
    let (data, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    XCTAssertFalse(data.isEmpty)
  }
}
