import XCTest

@testable import OpenCodeRemote

/// Where a prompt lands in the timeline: at the tool call it belongs to, or in
/// the tail when there is no tool (or the tool's message is not loaded).
@MainActor
final class InlinePromptTests: XCTestCase {
  private func permission(
    id: String, tool: ToolRef?
  ) -> PermissionPrompt {
    PermissionPrompt(
      request: PermissionRequest(
        id: id,
        sessionID: "ses_1",
        permission: "external_directory",
        patterns: ["/etc/*"],
        always: ["/etc/*"],
        tool: tool
      )
    )
  }

  private func toolBlock(_ name: String, _ status: ToolCallStatus, callID: String) -> ChatBlock {
    ChatBlock(
      id: "prt_\(callID)",
      kind: .tool(
        ToolCallPresenter.presentation(
          tool: name, status: status, title: nil, input: nil, metadata: nil),
        callID: callID
      )
    )
  }

  private func toolMessage(id: String, callID: String) -> ChatMessage {
    ChatMessage(
      id: id,
      role: .assistant,
      blocks: [toolBlock("read", .running, callID: callID)]
    )
  }

  func testPromptAnchorsToItsToolMessage() {
    let model = SessionChatModel()
    let message = toolMessage(id: "msg_1", callID: "call_1")
    model.seedForTesting(
      messages: [message],
      permissions: [permission(id: "per_1", tool: ToolRef(messageID: "msg_1", callID: "call_1"))]
    )

    XCTAssertEqual(model.inlinePrompts(for: "msg_1").map(\.id), ["permission-per_1"])
    XCTAssertTrue(model.tailPrompts.isEmpty)
    XCTAssertTrue(model.inlinePrompts(for: "msg_other").isEmpty)
  }

  func testPromptWithoutToolFallsBackToTail() {
    let model = SessionChatModel()
    model.seedForTesting(
      messages: [toolMessage(id: "msg_1", callID: "call_1")],
      permissions: [permission(id: "per_2", tool: nil)]
    )

    XCTAssertTrue(model.inlinePrompts(for: "msg_1").isEmpty)
    XCTAssertEqual(model.tailPrompts.map(\.id), ["permission-per_2"])
  }

  func testPromptForUnloadedMessageFallsBackToTail() {
    let model = SessionChatModel()
    model.seedForTesting(
      messages: [toolMessage(id: "msg_1", callID: "call_1")],
      permissions: [permission(id: "per_3", tool: ToolRef(messageID: "msg_missing", callID: "call_3"))]
    )

    XCTAssertTrue(model.inlinePrompts(for: "msg_1").isEmpty)
    XCTAssertEqual(model.tailPrompts.map(\.id), ["permission-per_3"])
  }

  func testLastToolAnchorIsNewestToolBlock() {
    let model = SessionChatModel()
    model.seedForTesting(messages: [
      ChatMessage(
        id: "msg_1", role: .assistant,
        blocks: [toolBlock("read", .completed, callID: "call_1")]),
      ChatMessage(
        id: "msg_2", role: .assistant,
        blocks: [
          ChatBlock(id: "prt_2", kind: .text("thinking")),
          toolBlock("bash", .running, callID: "call_2"),
        ]),
    ])

    XCTAssertEqual(model.lastToolAnchor, ToolRef(messageID: "msg_2", callID: "call_2"))
  }

  func testLastToolAnchorNilWithoutToolBlocks() {
    let model = SessionChatModel()
    model.seedForTesting(messages: [
      ChatMessage(id: "msg_1", role: .assistant, blocks: [ChatBlock(id: "prt_1", kind: .text("hi"))])
    ])

    XCTAssertNil(model.lastToolAnchor)
  }

  func testToolBlockExposesCallID() {
    let model = SessionChatModel()
    let message = toolMessage(id: "msg_1", callID: "call_1")
    model.seedForTesting(messages: [message])

    XCTAssertEqual(model.messages.first?.blocks.first?.toolCallID, "call_1")
  }
}
