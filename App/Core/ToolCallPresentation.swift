import Foundation
import OpenCodeAPI

/// How a tool call is progressing, independent of the server's raw status string.
enum ToolCallStatus: String, Sendable {
  case pending
  case running
  case completed
  case failed

  var label: String {
    switch self {
    case .pending: return "Pending"
    case .running: return "Running"
    case .completed: return "Done"
    case .failed: return "Failed"
    }
  }
}

/// The one-line presentation of a tool call in the timeline: a friendly title,
/// the short context that makes the call identifiable (a path, a command, a
/// query), and a status. Kept independent of the generated server types so the
/// mapping is a pure function that can be tested without a server.
struct ToolCallPresentation: Sendable, Equatable {
  var title: String
  var detail: String?
  var status: ToolCallStatus
  var symbol: String

  var accessibilityLabel: String {
    [title, detail].compactMap { $0 }.joined(separator: ", ")
  }
}

/// Maps a tool call to its timeline presentation. The server already names each
/// call (`title`: a relative path for reads, the command for shells); we fall
/// back to the raw input when it is absent and enrich reads and shells with the
/// line/exit facts the server carries in `metadata`.
enum ToolCallPresenter {
  /// The untyped JSON object shape of `OpenAPIObjectContainer.value`.
  typealias Object = [String: (any Sendable)?]

  /// Builds the presentation from the generated tool state.
  static func presentation(
    name: String,
    state: Components.Schemas.ToolState
  ) -> ToolCallPresentation {
    var status = ToolCallStatus.pending
    var title: String?
    var input: Object?
    var metadata: Object?
    if let pending = state.value1 {
      input = pending.input.value
    } else if let running = state.value2 {
      status = .running
      title = running.title
      input = running.input.value
      metadata = running.metadata?.value
    } else if let completed = state.value3 {
      status = .completed
      title = completed.title
      input = completed.input.value
      metadata = completed.metadata.value
    } else if let error = state.value4 {
      status = .failed
      input = error.input.value
      metadata = error.metadata?.value
    }
    return presentation(tool: name, status: status, title: title, input: input, metadata: metadata)
  }

  /// Pure mapping used by the tests and by the debug fixture.
  static func presentation(
    tool: String,
    status: ToolCallStatus,
    title: String?,
    input: Object?,
    metadata: Object?
  ) -> ToolCallPresentation {
    let leaf = leafName(tool)
    let descriptor = descriptor(for: leaf)
    let base = baseDetail(title: title, input: input, leaf: leaf)
    let extras = detailExtras(leaf: leaf, input: input, metadata: metadata)
    return ToolCallPresentation(
      title: descriptor.title,
      detail: joined(base, extras),
      status: status,
      symbol: descriptor.symbol
    )
  }

  // MARK: - Names

  private static let pathTools: Set<String> = [
    "read", "read_file", "readfile", "write", "write_file", "create_file", "edit", "apply_patch",
    "apply_diff", "patch",
  ]
  private static let shellTools: Set<String> = ["bash", "shell", "exec_command", "exec"]

  /// Strips provider prefixes (`mcp__server__tool`, `server.tool`) so the leaf
  /// name drives the descriptor.
  private static func leafName(_ tool: String) -> String {
    let trimmed = tool.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if trimmed.contains("__"), let leaf = trimmed.components(separatedBy: "__").last, !leaf.isEmpty {
      return leaf
    }
    if trimmed.contains("."), let leaf = trimmed.components(separatedBy: ".").last, !leaf.isEmpty {
      return leaf
    }
    return trimmed
  }

  private static func descriptor(for leaf: String) -> (title: String, symbol: String) {
    switch leaf {
    case "read", "read_file", "readfile": return ("Read", "doc.text")
    case "bash", "shell", "exec_command", "exec": return ("Bash", "terminal")
    case "grep", "search": return ("Grep", "magnifyingglass")
    case "glob": return ("Glob", "magnifyingglass")
    case "edit", "apply_patch", "apply_diff", "patch": return ("Edit", "pencil")
    case "write", "write_file", "create_file": return ("Write", "square.and.pencil")
    case "webfetch", "fetch": return ("Fetch", "globe")
    case "task", "agent": return ("Task", "person.2")
    case "todowrite", "todoread", "todo": return ("Todos", "checklist")
    case "list": return ("List", "list.bullet")
    case "skill": return ("Skill", "sparkles")
    default: return (humanize(leaf), "wrench.and.screwdriver")
    }
  }

  private static func humanize(_ name: String) -> String {
    let spaced = name.replacingOccurrences(of: "[._-]+", with: " ", options: .regularExpression)
    let collapsed = spaced.split(separator: " ").map(String.init).joined(separator: " ")
    guard let first = collapsed.first else { return name }
    return first.uppercased() + collapsed.dropFirst()
  }

  // MARK: - Detail

  private static func baseDetail(title: String?, input: Object?, leaf: String) -> String? {
    if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
      return title
    }
    guard input != nil else { return nil }
    if pathTools.contains(leaf) {
      return string(input, ["filePath", "file_path", "path"])
    }
    if shellTools.contains(leaf) {
      return command(input)
    }
    switch leaf {
    case "grep", "search": return string(input, ["pattern", "query"])
    case "glob": return string(input, ["pattern"])
    case "webfetch", "fetch": return string(input, ["url"])
    case "task", "agent": return string(input, ["description"])
    default: return nil
    }
  }

  private static func detailExtras(leaf: String, input: Object?, metadata: Object?) -> String? {
    var parts: [String] = []
    if pathTools.contains(leaf) {
      if let range = readLineRange(input: input, metadata: metadata) {
        parts.append(range)
      }
      if bool(metadata, "truncated") == true, parts.isEmpty {
        parts.append("truncated")
      }
    } else if shellTools.contains(leaf) {
      if let exit = int(metadata, "exit"), exit != 0 {
        parts.append("exit \(exit)")
      }
      if bool(metadata, "truncated") == true {
        parts.append("truncated")
      }
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  /// `lines 12–40 of 300`, `300 lines`, or the requested offset when the server
  /// reports no line facts (pending reads).
  private static func readLineRange(input: Object?, metadata: Object?) -> String? {
    let display = nestedObject(metadata, "display")
    let start = int(display, "lineStart")
    let end = int(display, "lineEnd")
    let total = int(display, "totalLines")
    if let start, let end, end >= start {
      if let total, total > end {
        return "lines \(start)–\(end) of \(total)"
      }
      if start > 1 {
        return "lines \(start)–\(end)"
      }
      if let total, total > 0 {
        return "\(total) lines"
      }
    }
    if let total, total > 0 {
      return "\(total) lines"
    }
    if let offset = int(input, "offset"), offset > 1 {
      if let limit = int(input, "limit"), limit > 0 {
        return "lines \(offset)–\(offset + limit - 1)"
      }
      return "from line \(offset)"
    }
    return nil
  }

  private static func joined(_ base: String?, _ extras: String?) -> String? {
    switch (base, extras) {
    case (let base?, let extras?): return "\(base) · \(extras)"
    case (let base?, nil): return base
    case (nil, let extras?): return extras
    case (nil, nil): return nil
    }
  }

  // MARK: - Untyped reads

  private static func string(_ object: Object?, _ keys: [String]) -> String? {
    guard let object else { return nil }
    for key in keys {
      if let value = object[key] as? String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          return trimmed
        }
      }
    }
    return nil
  }

  private static func command(_ input: Object?) -> String? {
    guard let input else { return nil }
    if let command = string(input, ["command"]) {
      return command
    }
    if let list = input["command"] as? [Any] {
      let parts = list.compactMap { $0 as? String }
      if !parts.isEmpty {
        return parts.joined(separator: " ")
      }
    }
    return string(input, ["cmd"])
  }

  private static func nestedObject(_ object: Object?, _ key: String) -> Object? {
    object?[key] as? Object
  }

  private static func int(_ object: Object?, _ key: String) -> Int? {
    guard let object else { return nil }
    if let value = object[key] as? Int {
      return value
    }
    if let value = object[key] as? Double {
      return Int(value)
    }
    return nil
  }

  private static func bool(_ object: Object?, _ key: String) -> Bool? {
    object?[key] as? Bool
  }
}
