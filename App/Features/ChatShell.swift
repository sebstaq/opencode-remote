import OpenCodeAPI
import SwiftUI

struct ChatShell: View {
  let service: ConnectionService
  let store: ComputerStore
  let sessions: SessionsModel
  let shell: ShellModel
  let client: Client
  let computer: Computer

  private let sidebarWidth: CGFloat = 330
  @GestureState private var drag: CGFloat = 0

  var body: some View {
    ZStack(alignment: .leading) {
      SessionsSidebar(
        computer: computer,
        store: store,
        service: service,
        sessions: sessions,
        shell: shell,
        onSwitch: switchTo
      )
      .frame(width: sidebarWidth)
      .accessibilityHidden(!shell.showSidebar)

      panel
        .offset(x: offset)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 22, x: -8)
    }
    .contentShape(Rectangle())
    .highPriorityGesture(dragGesture)
    .sheet(item: sheetBinding) { sheet in
      switch sheet {
      case .settings:
        SettingsSheet(service: service, store: store, client: client)
          .presentationDetents([.fraction(0.68)])
      case .newSession:
        NewSessionSheet(client: client) { row in
          shell.selectedSession = row
          shell.showSidebar = false
          Task { await sessions.load(client: client) }
        }
        .presentationDetents([.fraction(0.64)])
      }
    }
    .task { await sessions.load(client: client) }
  }

  // MARK: - Panel

  private var panel: some View {
    NavigationStack {
      timeline
        .navigationTitle(shell.selectedSession?.title ?? computer.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              setSidebar(true)
            } label: {
              Image(systemName: "line.3.horizontal")
            }
            .accessibilityIdentifier("chat.menu")
          }
          ToolbarItem(placement: .topBarTrailing) {
            statusMenu
          }
        }
    }
    .background(Color(.systemBackground))
  }

  /// The chat panel travels right; the sidebar stays put underneath.
  private var offset: CGFloat {
    let base = shell.showSidebar ? sidebarWidth : 0
    return min(max(base + drag, 0), sidebarWidth)
  }

  private var corner: CGFloat {
    // Round the leading corners as the panel leaves the edge.
    offset > 1 ? 18 : 0
  }

  private var dragGesture: some Gesture {
    DragGesture(minimumDistance: 12)
      .updating($drag) { value, state, _ in
        let dx = value.translation.width
        guard abs(dx) > abs(value.translation.height) else { return }
        state = dx
      }
      .onEnded { value in
        let dx = value.translation.width
        guard abs(dx) > abs(value.translation.height) else { return }
        if shell.showSidebar {
          setSidebar(dx > -60)
        } else if value.startLocation.x < 44 {
          setSidebar(dx > 60)
        }
      }
  }

  private func setSidebar(_ open: Bool) {
    let keepKeyboard = ProcessInfo.processInfo.environment["OPENCODE_UI_KEEP_KEYBOARD"] == "1"
    if open, !keepKeyboard {
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: open ? 0.40 : 0.35)) {
      shell.showSidebar = open
    }
  }

  // MARK: - Toolbar status

  private var statusMenu: some View {
    Menu {
      Button("Refresh sessions") {
        Task { await sessions.load(client: client) }
      }
      Button("Disconnect", role: .destructive) {
        service.disconnect()
      }
    } label: {
      Image(systemName: "circle.fill")
        .font(.system(size: 9))
        .foregroundStyle(statusColor)
    }
    .accessibilityIdentifier("chat.status")
  }

  private var sheetBinding: Binding<ShellModel.Sheet?> {
    Binding(
      get: { shell.sheet },
      set: { shell.sheet = $0 }
    )
  }

  @ViewBuilder
  private var timeline: some View {
    if let session = shell.selectedSession {
      SessionTimeline(sessionID: session.id, client: client)
    } else {
      ContentUnavailableView(
        "Select a session",
        systemImage: "bubble.left.and.bubble.right",
        description: Text("Open the sidebar and pick a session.")
      )
    }
  }

  private func switchTo(_ computer: Computer) {
    Task {
      guard let password = try? Keychain.password(for: computer.id) else {
        return
      }
      await service.connect(to: computer, password: password)
      if let client = service.apiClient {
        await sessions.load(client: client)
      }
    }
  }

  private var statusColor: Color {
    switch service.state {
    case .connected: .green
    case .connecting, .reconnecting: .orange
    case .idle, .offline: .gray
    }
  }
}
