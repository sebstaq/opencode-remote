import XCTest

@testable import OpenCodeRemote

/// Deterministic coverage for the event subset the chat acts on. The live UI
/// suites exercise the end-to-end flow; these pin the payload shapes, where the
/// server's `permission.replied` / `question.replied` use `requestID`.
final class ServerEventDecoderTests: XCTestCase {
  private func decode(_ json: String) -> ServerEvent? {
    ServerEventDecoder.decode(Data(json.utf8))
  }

  func testPermissionRepliedReadsRequestID() throws {
    let event = try XCTUnwrap(
      decode(
        #"{"type":"permission.replied","properties":{"sessionID":"ses_1","requestID":"per_abc","reply":"once"}}"#
      )
    )
    guard case .permissionResolved(let id) = event else {
      return XCTFail("expected permissionResolved, got \(event)")
    }
    XCTAssertEqual(id, "per_abc")
  }

  func testPermissionRepliedAcceptsLegacyID() throws {
    let event = try XCTUnwrap(
      decode(#"{"type":"permission.replied","properties":{"id":"per_legacy"}}"#)
    )
    guard case .permissionResolved(let id) = event else {
      return XCTFail("expected permissionResolved, got \(event)")
    }
    XCTAssertEqual(id, "per_legacy")
  }

  func testQuestionRepliedReadsRequestID() throws {
    let event = try XCTUnwrap(
      decode(
        #"{"type":"question.replied","properties":{"sessionID":"ses_1","requestID":"que_1","answers":[["Yes"]]}}"#
      )
    )
    guard case .questionResolved(let id) = event else {
      return XCTFail("expected questionResolved, got \(event)")
    }
    XCTAssertEqual(id, "que_1")
  }

  func testQuestionRejectedReadsRequestID() throws {
    let event = try XCTUnwrap(
      decode(#"{"type":"question.rejected","properties":{"sessionID":"ses_1","requestID":"que_2"}}"#)
    )
    guard case .questionResolved(let id) = event else {
      return XCTFail("expected questionResolved, got \(event)")
    }
    XCTAssertEqual(id, "que_2")
  }

  func testPermissionAskedMapsFields() throws {
    let event = try XCTUnwrap(
      decode(
        #"{"type":"permission.asked","properties":{"id":"per_9","sessionID":"ses_9","permission":"external_directory","patterns":["/etc/*"],"metadata":{},"always":["/etc/*"]}}"#
      )
    )
    guard case .permissionAsked(let request) = event else {
      return XCTFail("expected permissionAsked, got \(event)")
    }
    XCTAssertEqual(request.id, "per_9")
    XCTAssertEqual(request.sessionID, "ses_9")
    XCTAssertEqual(request.permission, "external_directory")
    XCTAssertEqual(request.patterns, ["/etc/*"])
    XCTAssertEqual(request.always, ["/etc/*"])
  }

  func testQuestionAskedMapsFirstQuestion() throws {
    let event = try XCTUnwrap(
      decode(
        #"{"type":"question.asked","properties":{"id":"que_9","sessionID":"ses_9","questions":[{"question":"Which?","header":"Pick","options":[{"label":"A","description":"first"}],"multiple":false,"custom":true}]}}"#
      )
    )
    guard case .questionAsked(let request) = event else {
      return XCTFail("expected questionAsked, got \(event)")
    }
    XCTAssertEqual(request.id, "que_9")
    XCTAssertEqual(request.header, "Pick")
    XCTAssertEqual(request.question, "Which?")
    XCTAssertEqual(request.options, [QuestionOption(label: "A", description: "first")])
    XCTAssertFalse(request.multiple)
    XCTAssertTrue(request.custom)
  }

  func testUnknownEventIsDropped() {
    XCTAssertNil(decode(#"{"type":"server.heartbeat","properties":{}}"#))
  }
}
