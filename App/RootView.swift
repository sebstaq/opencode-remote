import SwiftUI

struct RootView: View {
  @State private var prefs: Preferences
  @State private var service = ConnectionService()
  @State private var store: ComputerStore
  @State private var sessions: SessionsModel
  @State private var runState = RunStateStore()
  @State private var shell: ShellModel
  @Environment(\.scenePhase) private var scenePhase

  init() {
    let prefs = Preferences()
    _prefs = State(initialValue: prefs)
    _store = State(initialValue: ComputerStore(prefs: prefs))
    _sessions = State(initialValue: SessionsModel(prefs: prefs))
    _shell = State(initialValue: ShellModel(prefs: prefs))
  }

  var body: some View {
    ChatShell(
      service: service,
      store: store,
      sessions: sessions,
      runState: runState,
      shell: shell,
      prefs: prefs,
      client: service.apiClient,
      computer: currentComputer
    )
    .task { await bootstrap() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        Task {
          await service.refresh()
          // Correct any drift accumulated while the app was away.
          if let client = service.apiClient,
            let active = try? await SessionActivityModel.activeSessions(client)
          {
            runState.reconcile(active: active)
          }
        }
      }
    }
  }

  private var currentComputer: Computer? {
    service.activeComputer ?? store.lastUsed
  }

  private func bootstrap() async {
    let environment = ProcessInfo.processInfo.environment
    if let urlString = environment["OPENCODE_E2E_URL"],
      let url = URL(string: urlString),
      let password = environment["OPENCODE_E2E_PASSWORD"]
    {
      let computer = Computer(name: environment["OPENCODE_E2E_NAME"] ?? "E2E", url: url)
      store.markUsed(computer)
      await service.connect(to: computer, password: password)
      return
    }
    guard let computer = store.lastUsed else {
      return
    }
    store.markUsed(computer)
    guard let password = try? Keychain.password(for: computer.id) else {
      shell.reauthComputer = computer
      shell.sheet = .settings
      return
    }
    await service.connect(to: computer, password: password)
  }
}
