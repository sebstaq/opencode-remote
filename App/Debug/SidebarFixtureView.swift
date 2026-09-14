#if DEBUG
  import SwiftUI

  /// Renders the sidebar with the wireframe's sample content so `scripts/ui-diff.sh`
  /// compares the design against the reference, not against the connected server's data.
  /// Selected at launch with `OPENCODE_UI_FIXTURE=wireframe`.
  struct SidebarFixtureView: View {
    @State private var service = ConnectionService(state: .connected(version: "1.18.30"))
    @State private var store = ComputerStore()
    @State private var sessions = SessionsModel(phase: .loaded(Self.sampleRows()))
    @State private var shell = ShellModel()

    private static let computer = Computer(
      name: "Mac Studio",
      url: URL(string: "https://mac.tailnet.ts.net")!
    )

    var body: some View {
      ZStack(alignment: .leading) {
        Color.black.opacity(0.16)
          .ignoresSafeArea()
        SessionsSidebar(
          computer: Self.computer,
          store: store,
          service: service,
          sessions: sessions,
          shell: shell,
          onSwitch: { _ in }
        )
      }
    }

    private static func sampleRows() -> [SessionRow] {
      let now = Date()
      return [
        SessionRow(
          id: "1", title: "Rate limiting on /login", updated: now,
          status: .busy, group: "beta-api"),
        SessionRow(
          id: "2", title: "Investigate test failure",
          updated: now.addingTimeInterval(-12 * 60), status: .idle, group: "beta-api",
          isChild: true),
        SessionRow(
          id: "3", title: "Refactor auth middleware",
          updated: now.addingTimeInterval(-26 * 3600), status: .retry, group: "beta-api"),
        SessionRow(
          id: "4", title: "Update landing page",
          updated: now.addingTimeInterval(-3 * 86400), status: .idle, group: "web"),
      ]
    }
  }
#endif
