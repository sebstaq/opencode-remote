import XCTest

@MainActor
final class AppLaunchUITests: XCTestCase {
  func testLaunches() {
    let app = XCUIApplication()
    app.launch()
    XCTAssertTrue(app.waitForExistence(timeout: 10))
  }
}
