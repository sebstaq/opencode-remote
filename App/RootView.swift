import SwiftUI

struct RootView: View {
  @State private var service = ConnectionService()
  @State private var store = ComputerStore()
  @State private var sessions = SessionsModel()
  @State private var shell = ShellModel()
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    Group {
      if case .connected = service.state, let client = service.apiClient {
        ChatShell(
          service: service,
          store: store,
          sessions: sessions,
          shell: shell,
          client: client,
          computer: currentComputer
        )
      } else {
        NavigationStack {
          AddComputerView(service: service, store: store)
        }
      }
    }
    .task { await bootstrap() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        Task { await service.refresh() }
      }
    }
  }

  private var currentComputer: Computer {
    service.activeComputer
      ?? store.computers.last
      ?? Computer(name: "Computer", url: URL(string: "https://localhost")!)
  }

  private func bootstrap() async {
    let environment = ProcessInfo.processInfo.environment
    if let urlString = environment["OPENCODE_E2E_URL"],
      let url = URL(string: urlString),
      let password = environment["OPENCODE_E2E_PASSWORD"]
    {
      let computer = Computer(name: environment["OPENCODE_E2E_NAME"] ?? "E2E", url: url)
      await service.connect(to: computer, password: password)
      return
    }
    guard let computer = store.computers.last,
      let password = try? Keychain.password(for: computer.id)
    else {
      return
    }
    await service.connect(to: computer, password: password)
  }
}
