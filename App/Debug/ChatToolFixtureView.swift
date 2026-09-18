#if DEBUG
  import SwiftUI

  /// Renders representative tool calls through the production presentation so UI
  /// tests can verify the rich read/bash rows without a live model. Selected at
  /// launch with `OPENCODE_UI_FIXTURE=chat-tools`.
  struct ChatToolFixtureView: View {
    private static let readDisplay: ToolCallPresenter.Object = [
      "lineStart": 12,
      "lineEnd": 40,
      "totalLines": 300,
    ]
    private static let readMetadata: ToolCallPresenter.Object = ["display": readDisplay]
    private static let readInput: ToolCallPresenter.Object = ["filePath": "src/session.ts"]
    private static let shellInput: ToolCallPresenter.Object = ["command": "npm test"]
    private static let shellMetadata: ToolCallPresenter.Object = ["exit": 1]
    private static let pendingInput: ToolCallPresenter.Object = ["command": "git status"]
    private static let grepInput: ToolCallPresenter.Object = ["pattern": "toolCallID"]

    private static let samples: [ToolCallPresentation] = [
      ToolCallPresenter.presentation(
        tool: "read", status: .completed, title: "src/session.ts", input: readInput,
        metadata: readMetadata),
      ToolCallPresenter.presentation(
        tool: "bash", status: .completed, title: "npm test", input: shellInput,
        metadata: shellMetadata),
      ToolCallPresenter.presentation(
        tool: "bash", status: .pending, title: nil, input: pendingInput, metadata: nil),
      ToolCallPresenter.presentation(
        tool: "grep", status: .pending, title: nil, input: grepInput, metadata: nil),
    ]

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          ForEach(Array(Self.samples.enumerated()), id: \.offset) { _, sample in
            ToolCallRow(presentation: sample)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
      }
    }
  }
#endif
