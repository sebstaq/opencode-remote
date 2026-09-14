import Observation

@MainActor
@Observable
final class ShellModel {
  enum Sheet: String, Identifiable {
    case settings
    case newSession

    var id: String { rawValue }
  }

  var showSidebar = false
  var sheet: Sheet?
  var selectedSession: SessionRow?
}
