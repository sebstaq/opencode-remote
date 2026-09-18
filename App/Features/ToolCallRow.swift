import SwiftUI

/// One tool call in the timeline: an icon, the friendly tool name, the short
/// context that identifies the call (a path, a command, a query), and a status
/// affordance. The detail line stays on one line so a long path or command can
/// never push the status out of view.
struct ToolCallRow: View {
  let presentation: ToolCallPresentation

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: presentation.symbol)
        .font(.footnote)
        .foregroundStyle(Theme.Color.inkSecondary)
      Text(presentation.title)
        .font(.footnote.weight(.medium))
      if let detail = presentation.detail {
        Text(detail)
          .font(.footnote.monospaced())
          .foregroundStyle(Theme.Color.inkSecondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      statusIndicator
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.Color.line))
    .accessibilityElement(children: .ignore)
    .accessibilityIdentifier("timeline.tool")
    .accessibilityLabel(presentation.accessibilityLabel)
    .accessibilityValue(presentation.status.label)
  }

  @ViewBuilder
  private var statusIndicator: some View {
    switch presentation.status {
    case .pending, .running:
      ProgressView()
        .scaleEffect(0.7)
    case .completed:
      Image(systemName: "checkmark")
        .font(.caption2)
        .foregroundStyle(Theme.Color.inkSecondary)
    case .failed:
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.caption2)
        .foregroundStyle(Theme.Color.inkSecondary)
    }
  }
}
