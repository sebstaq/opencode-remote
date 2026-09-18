import Foundation
import Observation

/// The saved computers, persisted through `Preferences` like every other
/// preference — passwords stay in the Keychain.
@MainActor
@Observable
final class ComputerStore {
  private let prefs: Preferences

  init(prefs: Preferences) {
    self.prefs = prefs
  }

  var computers: [Computer] {
    get { prefs[.computers] }
    set { prefs[.computers] = newValue }
  }

  /// The computer the user last connected to, falling back to the last added
  /// one when no choice has been recorded yet.
  var lastUsed: Computer? {
    if let id = prefs[.lastComputerID], let match = computers.first(where: { $0.id.uuidString == id }) {
      return match
    }
    return computers.last
  }

  func markUsed(_ computer: Computer) {
    prefs[.lastComputerID] = computer.id.uuidString
  }

  func add(_ computer: Computer) {
    var list = computers
    if let index = list.firstIndex(where: { $0.url == computer.url }) {
      list[index].name = computer.name
    } else {
      list.append(computer)
    }
    computers = list
  }

  func remove(_ computer: Computer) {
    try? Keychain.deletePassword(for: computer.id)
    var list = computers
    list.removeAll { $0.id == computer.id }
    computers = list
  }
}
