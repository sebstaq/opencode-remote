import XCTest

@testable import OpenCodeRemote

/// The tool-call presentation is the whole chat experience for a call: the
/// friendly title, the one-line context, and the status. These pin the mapping
/// for the tools the app renders most, including the read line range and shell
/// exit code that only exist in the server's `metadata`.
final class ToolCallPresentationTests: XCTestCase {
  private func object(_ pairs: [String: (any Sendable)?]) -> ToolCallPresenter.Object {
    pairs
  }

  private func present(
    _ tool: String,
    _ status: ToolCallStatus = .completed,
    title: String? = nil,
    input: ToolCallPresenter.Object? = nil,
    metadata: ToolCallPresenter.Object? = nil
  ) -> ToolCallPresentation {
    ToolCallPresenter.presentation(
      tool: tool, status: status, title: title, input: input, metadata: metadata)
  }

  func testReadUsesServerTitleAndMetadataLineRange() {
    let presentation = present(
      "read", title: "src/session.ts",
      input: object(["filePath": "src/session.ts"]),
      metadata: object([
        "display": object(["lineStart": 12, "lineEnd": 40, "totalLines": 300])
      ])
    )
    XCTAssertEqual(
      presentation,
      ToolCallPresentation(
        title: "Read",
        detail: "src/session.ts · lines 12–40 of 300",
        status: .completed,
        symbol: "doc.text"
      )
    )
  }

  func testReadFullFileReportsLineCount() {
    let presentation = present(
      "read", title: "Package.swift",
      metadata: object([
        "display": object(["lineStart": 1, "lineEnd": 42, "totalLines": 42])
      ])
    )
    XCTAssertEqual(presentation.detail, "Package.swift · 42 lines")
  }

  func testReadFallsBackToInputOffsetAndLimit() {
    let presentation = present(
      "read", title: "src/app.ts",
      input: object(["filePath": "src/app.ts", "offset": 21, "limit": 20])
    )
    XCTAssertEqual(presentation.detail, "src/app.ts · lines 21–40")
  }

  func testPendingReadUsesInputPathWithoutMetadata() {
    let presentation = present(
      "read", .pending, input: object(["filePath": "src/app.ts"]))
    XCTAssertEqual(presentation.title, "Read")
    XCTAssertEqual(presentation.detail, "src/app.ts")
    XCTAssertEqual(presentation.status, .pending)
  }

  func testFailedReadKeepsFailedStatus() {
    let presentation = present(
      "read", .failed, title: "src/missing.ts",
      input: object(["filePath": "src/missing.ts"]))
    XCTAssertEqual(presentation.status, .failed)
    XCTAssertEqual(presentation.detail, "src/missing.ts")
  }

  func testBashUsesCommandAndNonZeroExit() {
    let presentation = present(
      "bash", title: "npm test",
      input: object(["command": "npm test"]),
      metadata: object(["exit": 1])
    )
    XCTAssertEqual(
      presentation,
      ToolCallPresentation(
        title: "Bash",
        detail: "npm test · exit 1",
        status: .completed,
        symbol: "terminal"
      )
    )
  }

  func testBashSuccessfulExitAddsNoNoise() {
    let presentation = present(
      "bash", title: "ls", input: object(["command": "ls"]), metadata: object(["exit": 0]))
    XCTAssertEqual(presentation.detail, "ls")
  }

  func testBashRunningWithoutTitleUsesInputCommand() {
    let presentation = present(
      "bash", .running, input: object(["command": "git status"]))
    XCTAssertEqual(presentation.title, "Bash")
    XCTAssertEqual(presentation.detail, "git status")
  }

  func testBashCommandArrayIsJoined() {
    let presentation = present(
      "shell", .running, input: object(["command": ["echo", "hello"]]))
    XCTAssertEqual(presentation.detail, "echo hello")
  }

  func testBashTruncatedOutputIsMarked() {
    let presentation = present(
      "bash", title: "cat big.log", metadata: object(["exit": 0, "truncated": true]))
    XCTAssertEqual(presentation.detail, "cat big.log · truncated")
  }

  func testGrepAndGlobUsePattern() {
    XCTAssertEqual(
      present("grep", .pending, input: object(["pattern": "toolCallID"])).detail, "toolCallID")
    XCTAssertEqual(
      present("glob", .pending, input: object(["pattern": "**/*.swift"])).detail, "**/*.swift")
  }

  func testEditWriteAndFetchUseTheirTargets() {
    XCTAssertEqual(
      present("edit", .pending, input: object(["filePath": "App/Core/Foo.swift"])).title, "Edit")
    XCTAssertEqual(
      present("write", .pending, input: object(["filePath": "App/Core/Bar.swift"])).detail,
      "App/Core/Bar.swift")
    XCTAssertEqual(
      present("webfetch", .pending, input: object(["url": "https://example.com"])).detail,
      "https://example.com")
    XCTAssertEqual(
      present("task", .pending, input: object(["description": "Inspect the repo"])).detail,
      "Inspect the repo")
  }

  func testUnknownAndMcpToolNamesAreHumanized() {
    XCTAssertEqual(present("create_agent").title, "Create agent")
    XCTAssertEqual(present("mcp__paseo__create_agent").title, "Create agent")
    XCTAssertEqual(present("paseo.list_agents").title, "List agents")
    XCTAssertEqual(present("create_agent").symbol, "wrench.and.screwdriver")
  }

  func testAccessibilityLabelCombinesTitleAndDetail() {
    let presentation = present(
      "bash", title: "npm test", input: object(["command": "npm test"]),
      metadata: object(["exit": 2]))
    XCTAssertEqual(presentation.accessibilityLabel, "Bash, npm test · exit 2")
  }
}
