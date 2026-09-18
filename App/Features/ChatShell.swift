import OpenCodeAPI
import SwiftUI

/// Chat + sidebar layout, per `docs/sidebar-reveal.md` (behaviour spec).
///
/// Geometry is explicit (GeometryReader): the sidebar occupies 85% of the
/// width; the chat card is a full-screen panel translated right when the
/// sidebar is open, clipped to rounded corners with a card shadow. No
/// implicit full-bleed backgrounds, no child windows.
///
/// - Open: menu button or edge-swipe from the left edge (a narrow strip that
///   exists only while the sidebar is closed, so it never competes with the
///   timeline's scroll gesture).
/// - Close: tap anywhere on the shifted card (it is non-interactive while
///   open), drag it back, or the menu button again.
/// - Opening dismisses the keyboard first.
/// - Motion: open 400 ms / close 350 ms, ease-smooth-out, reduce-motion =
///   instant.
struct ChatShell: View {
  let service: ConnectionService
  let store: ComputerStore
  let sessions: SessionsModel
  let runState: RunStateStore
  let shell: ShellModel
  let prefs: Preferences
  let client: Client?
  let computer: Computer?

  var body: some View {
    GeometryReader { geo in
      let width = geo.size.width
      let height = geo.size.height
      let topInset = statusBarHeight
      let sidebarWidth = width * 0.85
      let cardOffset = shell.showSidebar ? sidebarWidth : 0
      let corner = shell.showSidebar ? 18.0 : 0.0

      ZStack(alignment: .topLeading) {
        SessionsSidebar(
          computer: computer,
          store: store,
          service: service,
          sessions: sessions,
          runState: runState,
          shell: shell,
          width: sidebarWidth,
          onSwitch: switchTo
        )
        .frame(width: sidebarWidth, height: height - topInset, alignment: .topLeading)
        .offset(y: topInset)
        .accessibilityHidden(!shell.showSidebar)

        // Card backdrop + shadow as its own sibling (plain shape + .shadow is
        // safe; .shadow on a view containing a NavigationStack blanks the
        // navigation bar on iOS 26).
        RoundedRectangle(cornerRadius: corner, style: .continuous)
          .fill(Theme.Color.surface)
          .frame(width: width, height: height)
          .offset(x: cardOffset)
          .shadow(
            color: .black.opacity(shell.showSidebar ? 0.16 : 0),
            radius: shell.showSidebar ? 22 : 0,
            x: -8
          )

        panel
          .frame(width: width, height: height)
          .offset(x: cardOffset)
          .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))

        if shell.showSidebar {
          cardControls
            .frame(width: width - sidebarWidth, height: height)
            .offset(x: sidebarWidth)
        }
      }
      // Status-bar cover: opaque at the very top, fading out below it, so
      // sidebar content scrolls away smoothly instead of being sliced.
      .overlay(alignment: .top) {
        LinearGradient(
          stops: [
            .init(color: Theme.Color.surface, location: 0),
            .init(color: Theme.Color.surface, location: topInset / (topInset + 16)),
            .init(color: Theme.Color.surface.opacity(0), location: 1),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
        .frame(height: topInset + 14)
        .frame(maxWidth: .infinity)
      }
      .task(id: service.generation) { if let client { await activityFeed(client: client) } }
      .overlay(alignment: .topLeading) {
        if !shell.showSidebar {
          edgeSwipeStrip(width: width)
        }
      }
    }
    .ignoresSafeArea()
    // Attached outside the GeometryReader: a sheet anchored to a view that
    // ignores the safe areas can present without its backing card.
    .sheet(item: sheetBinding) { sheet in
      switch sheet {
      case .settings:
        SettingsSheet(service: service, store: store, client: client, reauth: shell.reauthComputer)
          .presentationBackground(Theme.Color.surface)
          .presentationDetents([.fraction(0.68)])
      case .newSession:
        if let client {
          NewSessionSheet(client: client, prefs: prefs) { row in
            shell.selectedSession = row
            shell.showSidebar = false
            Task { await sessions.load(client: client) }
          }
          .presentationBackground(Theme.Color.surface)
          .presentationDetents([.fraction(0.64)])
        }
      }
    }
  }

  // MARK: - Panel

  /// The status-bar height (device safe-area top inset). GeometryReader
  /// reports 0 once it ignores the safe areas, so read it from the window.
  private var statusBarHeight: CGFloat {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }.first
    return scene?.windows.first { $0.isKeyWindow }?.safeAreaInsets.top ?? 0
  }

  private var panel: some View {
    NavigationStack {
      timeline
        .navigationTitle(shell.selectedSession?.title ?? computer?.name ?? "OpenCode Remote")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Color.surface, for: .navigationBar)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              setSidebar(true)
            } label: {
              Image(systemName: "line.3.horizontal")
            }
            .accessibilityIdentifier("chat.menu")
          }
        }
    }

  }

  /// Controls on the visible strip of the shifted card. Only this strip sees
  /// taps; the sidebar remains interactive underneath.
  private var cardControls: some View {
    Color.clear
      .contentShape(Rectangle())
      .onTapGesture { setSidebar(false) }
      .gesture(
        DragGesture(minimumDistance: 20)
          .onEnded { value in
            let dx = value.translation.width
            guard abs(dx) > abs(value.translation.height) else { return }
            if dx < -60 {
              setSidebar(false)
            }
          }
      )
      .accessibilityIdentifier("chat.card")
  }

  /// A narrow strip at the leading edge that opens the sidebar on swipe.
  /// Exists only while the sidebar is closed; never overlaps the timeline,
  /// so scrolling is unaffected.
  private func edgeSwipeStrip(width: CGFloat) -> some View {
    Color.clear
      .frame(width: 26, height: width * 2)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 20)
          .onEnded { value in
            let dx = value.translation.width
            guard abs(dx) > abs(value.translation.height) else { return }
            if dx > 60 {
              setSidebar(true)
            }
          }
      )
  }

  private func setSidebar(_ open: Bool) {
    if open {
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: open ? 0.40 : 0.35)) {
      shell.showSidebar = open
    }
  }

  private var sheetBinding: Binding<ShellModel.Sheet?> {
    Binding(
      get: { shell.sheet },
      set: {
        shell.sheet = $0
        // Any dismissal consumes the re-auth intent.
        if $0 == nil { shell.reauthComputer = nil }
      }
    )
  }

  @ViewBuilder
  private var timeline: some View {
    // A connection failure is shown in place — never a screen swap — and it
    // outranks the connected views even though a rebuilt client may exist.
    if case .offline(let failure) = service.state {
      ContentUnavailableView(
        failure.title,
        systemImage: "wifi.slash",
        description: Text(failure.message)
      )
    } else if let client {
      if let session = shell.selectedSession {
        let generation = service.generation
        SessionTimeline(
          sessionID: session.id,
          client: client,
          service: service,
          runState: runState,
          generation: generation,
          isCurrent: { [service = self.service] in
            await service.isCurrent(generation: generation)
          }
        )
      } else {
        ContentUnavailableView(
          "Select a session",
          systemImage: "bubble.left.and.bubble.right",
          description: Text("Open the sidebar and pick a session.")
        )
      }
    } else {
      ContentUnavailableView(
        "Select a computer",
        systemImage: "desktopcomputer",
        description: Text("Open the sidebar to pick or add one.")
      )
    }
  }

  /// Loads the session list, then follows this connection's run state until the
  /// generation changes. `SessionActivityModel` owns the subscription and the
  /// periodic reconcile; every view reads `RunStateStore`, so the sidebar
  /// spinner and the composer's stop button cannot disagree.
  private func activityFeed(client: Client) async {
    let generation = service.generation
    await sessions.load(client: client)
    shell.validateSelection(in: sessions)
    let activity = SessionActivityModel(store: runState)
    await activity.run(
      client: client,
      isCurrent: { [service = self.service] in await service.isCurrent(generation: generation) }
    )
  }

  private func switchTo(_ computer: Computer) {
    store.markUsed(computer)
    shell.selectedSession = nil
    Task {
      guard let password = try? Keychain.password(for: computer.id) else {
        shell.reauthComputer = computer
        shell.sheet = .settings
        return
      }
      await service.connect(to: computer, password: password)
      if let client = service.apiClient {
        await sessions.load(client: client)
      }
    }
  }
}
