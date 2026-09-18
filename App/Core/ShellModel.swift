import Foundation
import Observation

@MainActor
@Observable
final class ShellModel {
  enum Sheet: String, Identifiable {
    case settings
    case newSession

    var id: String { rawValue }
  }

  private let prefs: Preferences

  init(prefs: Preferences) {
    self.prefs = prefs
  }

  /// Ephemeral: the sidebar always starts closed, and a sheet never survives a
  /// launch.
  var showSidebar = false
  var sheet: Sheet?
  /// A stored computer needing its password re-entered; Settings opens on
  /// the pre-filled add form.
  var reauthComputer: Computer?

  /// The open conversation. Persisted through `Preferences`, so a launch lands
  /// straight in the last one (`ChatShell` clears it if the server no longer
  /// has it).
  var selectedSession: SessionRow? {
    get { prefs[.selectedSession] }
    set { prefs[.selectedSession] = newValue }
  }

  /// Drops a restored selection the server no longer lists, so a stale
  /// conversation cannot linger after an archive or a switch of computer.
  func validateSelection(in sessions: SessionsModel) {
    guard let selected = selectedSession,
      case .loaded(let rows) = sessions.phase,
      !rows.contains(where: { $0.id == selected.id })
    else { return }
    selectedSession = nil
  }
}
