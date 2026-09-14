import Foundation

@MainActor
final class ComputerStore {
  private let defaultsKey = "computers"
  private let defaults = UserDefaults.standard
  private(set) var computers: [Computer] = []

  init() {
    guard let data = defaults.data(forKey: defaultsKey),
      let decoded = try? JSONDecoder().decode([Computer].self, from: data)
    else {
      return
    }
    computers = decoded
  }

  func add(_ computer: Computer) {
    if let index = computers.firstIndex(where: { $0.url == computer.url }) {
      computers[index].name = computer.name
    } else {
      computers.append(computer)
    }
    save()
  }

  func remove(_ computer: Computer) {
    try? Keychain.deletePassword(for: computer.id)
    computers.removeAll { $0.id == computer.id }
    save()
  }

  private func save() {
    guard let data = try? JSONEncoder().encode(computers) else {
      return
    }
    defaults.set(data, forKey: defaultsKey)
  }
}
