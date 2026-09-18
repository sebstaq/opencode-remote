import XCTest

@testable import OpenCodeRemote

/// The viewport's rules are the whole point of the component, so they are
/// pinned here: start pinned, follow height growth, release on a user scroll
/// away, and never move a released viewport.
@MainActor
final class ViewportStateTests: XCTestCase {
  private let content: CGFloat = 1000
  private let container: CGFloat = 500

  func testStartsPinnedAndNearBottom() {
    let state = ViewportState()
    XCTAssertTrue(state.isPinnedToBottom)
    XCTAssertTrue(state.isNearBottom)
  }

  func testInitialGrowthPinsToBottom() {
    var state = ViewportState()
    let effect = state.reduce(
      offsetY: 0, contentHeight: content, containerHeight: container, isUserDriven: false)
    XCTAssertEqual(effect, .pinToBottom)
    XCTAssertEqual(state.distanceFromBottom, 500)
    XCTAssertTrue(state.isPinnedToBottom)
  }

  func testPinnedAtBottomIsAStableNoOp() {
    var state = ViewportState()
    _ = state.reduce(
      offsetY: 0, contentHeight: content, containerHeight: container, isUserDriven: false)
    let effect = state.reduce(
      offsetY: 500, contentHeight: content, containerHeight: container, isUserDriven: false)
    XCTAssertEqual(effect, .none)
    XCTAssertEqual(state.distanceFromBottom, 0)
  }

  func testGrowthWhilePinnedFollows() {
    var state = ViewportState()
    _ = state.reduce(
      offsetY: 500, contentHeight: content, containerHeight: container, isUserDriven: false)
    let effect = state.reduce(
      offsetY: 500, contentHeight: 1200, containerHeight: container, isUserDriven: false)
    XCTAssertEqual(effect, .pinToBottom)
  }

  func testContainerShrinkWhilePinnedRepinsForTheKeyboard() {
    var state = ViewportState()
    _ = state.reduce(
      offsetY: 500, contentHeight: content, containerHeight: container, isUserDriven: false)
    let effect = state.reduce(
      offsetY: 500, contentHeight: content, containerHeight: 300, isUserDriven: false)
    XCTAssertEqual(effect, .pinToBottom)
  }

  func testUserScrollAwayReleases() {
    var state = ViewportState()
    _ = state.reduce(
      offsetY: 500, contentHeight: content, containerHeight: container, isUserDriven: false)
    let effect = state.reduce(
      offsetY: 100, contentHeight: content, containerHeight: container, isUserDriven: true)
    XCTAssertEqual(effect, .release(atOffsetY: 100))
    XCTAssertFalse(state.isPinnedToBottom)
    XCTAssertEqual(state.distanceFromBottom, 400)
  }

  func testUserScrollWithinThresholdStaysPinned() {
    var state = ViewportState()
    _ = state.reduce(
      offsetY: 500, contentHeight: content, containerHeight: container, isUserDriven: false)
    let effect = state.reduce(
      offsetY: 460, contentHeight: content, containerHeight: container, isUserDriven: true)
    XCTAssertEqual(effect, .none)
    XCTAssertTrue(state.isPinnedToBottom)
  }

  func testReleasedViewportIgnoresGrowth() {
    var state = ViewportState()
    _ = state.reduce(
      offsetY: 100, contentHeight: content, containerHeight: container, isUserDriven: true)
    let effect = state.reduce(
      offsetY: 100, contentHeight: 2000, containerHeight: container, isUserDriven: false)
    XCTAssertEqual(effect, .none)
    XCTAssertFalse(state.isPinnedToBottom)
  }

  func testReturningNearBottomRepins() {
    var state = ViewportState()
    _ = state.reduce(
      offsetY: 100, contentHeight: content, containerHeight: container, isUserDriven: true)
    let effect = state.reduce(
      offsetY: 470, contentHeight: content, containerHeight: container, isUserDriven: true)
    XCTAssertEqual(effect, .pinToBottom)
    XCTAssertTrue(state.isPinnedToBottom)
  }

  func testResetReturnsToTheInitialState() {
    var state = ViewportState()
    _ = state.reduce(
      offsetY: 100, contentHeight: content, containerHeight: container, isUserDriven: true)
    state.reset()
    XCTAssertTrue(state.isPinnedToBottom)
    XCTAssertEqual(state.distanceFromBottom, 0)
  }
}
