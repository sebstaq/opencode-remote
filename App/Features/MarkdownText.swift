import SwiftUI

/// Renders assistant text as a document instead of a bubble: headings,
/// paragraphs, lists, blockquotes and fenced code blocks with inline
/// markdown (bold, italic, inline code, links) resolved through
/// `AttributedString`.
///
/// Deliberately dependency-free: the assistant emits a small, well-behaved
/// subset of markdown, which is parsed once in `init` so scrolling inside a
/// `LazyVStack` does not re-parse on every layout pass.
struct MarkdownText: View {
  private let blocks: [Block]

  init(_ source: String) {
    blocks = Self.parse(source)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(blocks) { block in
        blockView(block)
      }
    }
  }

  @ViewBuilder
  private func blockView(_ block: Block) -> some View {
    switch block.content {
    case .paragraph(let text):
      documentText(text)
    case .heading(let level, let text):
      documentText(text, font: headingFont(level))
    case .quote(let text):
      HStack(alignment: .top, spacing: 10) {
        RoundedRectangle(cornerRadius: 2)
          .fill(Theme.Color.line)
          .frame(width: 3)
        documentText(text)
      }
    case .code(let text, _):
      Text(text)
        .font(.footnote.monospaced())
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.Color.fillComposer, in: RoundedRectangle(cornerRadius: 10))
    case .list(let items, let ordered):
      VStack(alignment: .leading, spacing: 6) {
        ForEach(items.indices, id: \.self) { index in
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(ordered ? "\(index + 1)." : "•")
              .font(.body)
              .foregroundStyle(Theme.Color.inkSecondary)
            documentText(items[index])
          }
        }
      }
    }
  }

  private func documentText(_ text: AttributedString, font: Font = .body) -> some View {
    Text(text)
      .font(font)
      .textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func headingFont(_ level: Int) -> Font {
    switch level {
    case 1: .title3.bold()
    case 2: .headline
    default: .subheadline.bold()
    }
  }
}

// MARK: - Parsing

extension MarkdownText {
  /// One rendered block. `id` is the parse-order index, which is stable for
  /// the lifetime of the view instance.
  fileprivate struct Block: Identifiable {
    enum Content {
      case paragraph(AttributedString)
      case heading(level: Int, text: AttributedString)
      case quote(AttributedString)
      case code(text: String, language: String?)
      case list(items: [AttributedString], ordered: Bool)
    }

    let id: Int
    let content: Content
  }

  fileprivate static func parse(_ source: String) -> [Block] {
    var blocks: [Block] = []
    var paragraph: [String] = []
    var quote: [String] = []
    var list: [(marker: String, text: String)] = []
    var fence: (info: String, lines: [String])?

    func inline(_ text: String) -> AttributedString {
      inlineMarkdown(text)
    }

    func flushParagraph() {
      guard !paragraph.isEmpty else { return }
      blocks.append(.init(id: blocks.count, content: .paragraph(inline(paragraph.joined(separator: " ")))))
      paragraph.removeAll()
    }

    func flushQuote() {
      guard !quote.isEmpty else { return }
      blocks.append(.init(id: blocks.count, content: .quote(inline(quote.joined(separator: " ")))))
      quote.removeAll()
    }

    func flushList() {
      guard !list.isEmpty else { return }
      let ordered = list.allSatisfy { $0.marker.first?.isNumber == true }
      blocks.append(
        .init(id: blocks.count, content: .list(items: list.map { inline($0.text) }, ordered: ordered))
      )
      list.removeAll()
    }

    func flushAll() {
      flushParagraph()
      flushQuote()
      flushList()
    }

    for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(rawLine)
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if fence != nil {
        if isFenceDelimiter(trimmed) {
          blocks.append(
            .init(
              id: blocks.count,
              content: .code(text: fence!.lines.joined(separator: "\n"), language: fenceLanguage(fence!.info))
            )
          )
          fence = nil
        } else {
          fence?.lines.append(line)
        }
        continue
      }

      if isFenceDelimiter(trimmed) {
        flushAll()
        fence = (info: String(trimmed.dropFirst(3)), lines: [])
        continue
      }

      if trimmed.isEmpty {
        flushAll()
        continue
      }

      if let heading = headingLevel(trimmed) {
        flushAll()
        blocks.append(
          .init(id: blocks.count, content: .heading(level: heading.level, text: inline(heading.text)))
        )
        continue
      }

      if trimmed.hasPrefix(">") {
        flushParagraph()
        flushList()
        let text = trimmed.dropFirst().drop(while: { $0 == " " })
        quote.append(String(text))
        continue
      }

      if let item = listItem(trimmed) {
        flushParagraph()
        flushQuote()
        list.append(item)
        continue
      }

      flushQuote()
      flushList()
      paragraph.append(trimmed)
    }

    if let fence {
      let text = fence.lines.joined(separator: "\n")
      blocks.append(.init(id: blocks.count, content: .code(text: text, language: fenceLanguage(fence.info))))
    }
    flushAll()
    return blocks
  }

  /// "```" or "~~~" (optionally followed by an info string). Also closes a fence.
  private static func isFenceDelimiter(_ line: String) -> Bool {
    line.hasPrefix("```") || line.hasPrefix("~~~")
  }

  private static func fenceLanguage(_ info: String) -> String? {
    let trimmed = info.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// "# Heading" .. "###### Heading"; requires a space after the markers.
  private static func headingLevel(_ line: String) -> (level: Int, text: String)? {
    var level = 0
    var rest = Substring(line)
    while rest.first == "#", level < 6 {
      level += 1
      rest = rest.dropFirst()
    }
    guard level > 0, rest.first == " " else { return nil }
    let text = rest.dropFirst().trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return nil }
    return (level, text)
  }

  /// "- item", "* item", "+ item", "1. item", "1) item".
  private static func listItem(_ line: String) -> (marker: String, text: String)? {
    if let first = line.first, "-*+".contains(first), line.dropFirst().first == " " {
      return (String(first), String(line.dropFirst(2)))
    }
    let digits = line.prefix(while: \.isNumber)
    guard !digits.isEmpty, digits.count <= 9 else { return nil }
    let rest = line.dropFirst(digits.count)
    guard rest.first == "." || rest.first == ")", rest.dropFirst().first == " " else { return nil }
    let marker = String(digits) + String(rest.first!)
    return (marker, String(rest.dropFirst(2)))
  }

  /// Inline-only markdown (bold, italic, inline code, links); block syntax
  /// inside a single line is left as literal text rather than misinterpreted.
  private static func inlineMarkdown(_ text: String) -> AttributedString {
    do {
      return try AttributedString(
        markdown: text,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
      )
    } catch {
      return AttributedString(text)
    }
  }
}
