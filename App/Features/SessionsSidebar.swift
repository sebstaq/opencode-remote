import SwiftUI

/// Design tokens taken 1:1 from `docs/wireframes/index.html` (CSS px == pt).
private enum Wire {
  // Geometry tokens from `docs/wireframes/index.html` (CSS px == pt); all
  // colors come from `Theme` so light and dark stay one design.

  static let drawerWidth: CGFloat = 330
  static let hPadding: CGFloat = 16
  static let listBottomPadding: CGFloat = 92

  enum Header {
    static let titleSize: CGFloat = 22
    static let titleTop: CGFloat = 6
    static let titleBottom: CGFloat = 2
    static let top: CGFloat = 6
    static let bottom: CGFloat = 12
    static let rowSpacing: CGFloat = 12
    static let rowPadding: CGFloat = 8
    static let iconSize: CGFloat = 36
    static let iconRadius: CGFloat = 10
    static let nameSize: CGFloat = 16
    static let subtitleSize: CGFloat = 12
    static let chevronSize: CGFloat = 12
  }

  enum Group {
    /// 35pt is what WebKit renders for `.group` (padding 16/4 + line height).
    static let height: CGFloat = 35
    static let top: CGFloat = 16
    static let bottom: CGFloat = 4
    static let spacing: CGFloat = 6
    static let fontSize: CGFloat = 12
    static let tracking: CGFloat = 0.6
    static let chevronSize: CGFloat = 10
  }

  enum Row {
    /// 54pt is what WebKit renders for `.sess`, not the DOM box's 52pt.
    static let height: CGFloat = 54
    static let hPadding: CGFloat = 16
    static let childIndent: CGFloat = 34
    static let spacing: CGFloat = 10
    static let dotSize: CGFloat = 8
    static let titleSize: CGFloat = 14
    static let subtitleSize: CGFloat = 12
  }

  enum Actions {
    static let top: CGFloat = 20
    static let bottom: CGFloat = 24
    static let hPadding: CGFloat = 18
    static let composeTextSize: CGFloat = 14
    static let composeIconSize: CGFloat = 18
    static let composeSpacing: CGFloat = 9
    static let composeHPadding: CGFloat = 20
    static let composeVPadding: CGFloat = 13
    static let gearSize: CGFloat = 46
    static let gearIconSize: CGFloat = 18
  }
}

struct SessionsSidebar: View {
  let computer: Computer?
  let store: ComputerStore
  let service: ConnectionService
  let sessions: SessionsModel
  let shell: ShellModel
  let width: CGFloat
  let onSwitch: (Computer) -> Void

  var body: some View {
    ZStack(alignment: .bottom) {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Text("Sessions")
            .font(.system(size: Wire.Header.titleSize, weight: .bold))
            .foregroundStyle(Theme.Color.ink)
            .padding(.horizontal, Wire.hPadding)
            .padding(.top, Wire.Header.titleTop)
            .padding(.bottom, Wire.Header.titleBottom)

          computerRow
            .padding(.horizontal, Wire.hPadding)
            .padding(.top, Wire.Header.top)
            .padding(.bottom, Wire.Header.bottom)

          content
        }
        .padding(.bottom, Wire.listBottomPadding)
      }
      .scrollIndicators(.hidden)
      // Prevent scroll content from bleeding above the sidebar's own top
      // edge (into the status-bar strip).
      .clipped()

      actions
    }
    .frame(width: width)
    .frame(maxHeight: .infinity, alignment: .topLeading)
    .background(Theme.Color.surface.ignoresSafeArea())
    // The wireframe pins the bottom actions 24pt from the physical bottom edge.
    .ignoresSafeArea(edges: .bottom)
  }

  private var computerRow: some View {
    Menu {
      ForEach(store.computers) { stored in
        Button {
          onSwitch(stored)
        } label: {
          Label(
            stored.name,
            systemImage: stored.id == computer?.id ? "checkmark" : "desktopcomputer"
          )
        }
      }
      Divider()
      Button("Refresh sessions") {
        if let client = service.apiClient {
          Task { await sessions.load(client: client) }
        }
      }
      Button("Disconnect", role: .destructive) {
        service.disconnect()
      }
      Divider()
      Button {
        shell.sheet = .settings
      } label: {
        Label("Manage computers…", systemImage: "gearshape")
      }
    } label: {
      HStack(spacing: Wire.Header.rowSpacing) {
        RoundedRectangle(cornerRadius: Wire.Header.iconRadius, style: .continuous)
          .fill(Theme.Color.fillSelected)
          .frame(width: Wire.Header.iconSize, height: Wire.Header.iconSize)
        VStack(alignment: .leading, spacing: 2) {
          Text(computer?.name ?? "OpenCode Remote")
            .font(.system(size: Wire.Header.nameSize, weight: .semibold))
            .foregroundStyle(Theme.Color.ink)
            .lineLimit(1)
          Text(connectionSubtitle)
            .font(.system(size: Wire.Header.subtitleSize))
            .foregroundStyle(Theme.Color.inkSecondary)
            .lineLimit(1)
        }
        Spacer(minLength: 4)
        Image(systemName: "chevron.down")
          .font(.system(size: Wire.Header.chevronSize, weight: .regular))
          .foregroundStyle(Theme.Color.inkSecondary)
      }
      .padding(.vertical, Wire.Header.rowPadding)
      .contentShape(Rectangle())
    }
    .tint(Theme.Color.ink)
    .accessibilityIdentifier("sidebar.computer")
  }

  @ViewBuilder
  private var content: some View {
    switch sessions.phase {
    case .loading:
      HStack {
        Spacer()
        ProgressView()
        Spacer()
      }
      .padding(.top, 40)
    case .failed(let message):
      Text(message)
        .font(.system(size: Wire.Row.subtitleSize))
        .foregroundStyle(Theme.Color.inkSecondary)
        .padding(.horizontal, Wire.hPadding)
    case .loaded(let rows):
      if rows.isEmpty {
        Text("No sessions yet")
          .font(.system(size: Wire.Row.subtitleSize))
          .foregroundStyle(Theme.Color.inkSecondary)
          .padding(.horizontal, Wire.hPadding)
      } else {
        ForEach(grouped(rows), id: \.key) { group in
          Button {
            sessions.toggleGroup(group.key)
          } label: {
            HStack(spacing: Wire.Group.spacing) {
              Image(
                systemName: sessions.isCollapsed(group.key)
                  ? "chevron.down" : "chevron.up"
              )
              .font(.system(size: Wire.Group.chevronSize, weight: .semibold))
              Text(group.key.uppercased())
                .font(.system(size: Wire.Group.fontSize, weight: .semibold))
                .tracking(Wire.Group.tracking)
            }
          }
          .tint(Theme.Color.inkSecondary)
          .accessibilityIdentifier("session.group")
          .accessibilityLabel(
            sessions.isCollapsed(group.key) ? "Collapse group: expand" : "Collapse group"
          )
          .padding(.horizontal, Wire.hPadding)
          .padding(.top, Wire.Group.top)
          .padding(.bottom, Wire.Group.bottom)
          .frame(height: Wire.Group.height, alignment: .leading)
          .contentShape(Rectangle())

          if !sessions.isCollapsed(group.key) {
            ForEach(group.rows) { row in
              Button {
                shell.selectedSession = row
                shell.showSidebar = false
              } label: {
                rowView(row)
              }
              .tint(Theme.Color.ink)
              .accessibilityIdentifier("session.row")
              .contextMenu {
                Button {
                  if let client = service.apiClient {
                    Task { await sessions.archive(row.id, client: client) }
                  }
                } label: {
                  Label("Archive", systemImage: "archivebox")
                }
                .accessibilityIdentifier("session.archive")
              }
            }
          }
        }
      }
    }
  }

  private var actions: some View {
    HStack(spacing: 0) {
      Button {
        shell.sheet = .newSession
      } label: {
        HStack(spacing: Wire.Actions.composeSpacing) {
          Image(systemName: "square.and.pencil")
            .font(.system(size: Wire.Actions.composeIconSize, weight: .medium))
            .frame(width: Wire.Actions.composeIconSize, height: Wire.Actions.composeIconSize)
          Text("New session")
            .font(.system(size: Wire.Actions.composeTextSize, weight: .semibold))
        }
        .foregroundStyle(Theme.Color.surface)
        .padding(.horizontal, Wire.Actions.composeHPadding)
        .padding(.vertical, Wire.Actions.composeVPadding)
        .background(Theme.Color.fillInverted, in: Capsule())
      }
      .accessibilityIdentifier("sidebar.newSession")

      Spacer(minLength: 0)

      Button {
        shell.sheet = .settings
      } label: {
        Image(systemName: "gearshape")
          .font(.system(size: Wire.Actions.gearIconSize))
          .foregroundStyle(Theme.Color.ink)
          .frame(width: Wire.Actions.gearSize, height: Wire.Actions.gearSize)
          .background(Theme.Color.surface, in: Circle())
          .overlay(Circle().stroke(Theme.Color.line, lineWidth: 1))
      }
      .accessibilityIdentifier("sidebar.settings")
    }
    .padding(.leading, Wire.Actions.hPadding)
    .padding(.trailing, Wire.Actions.hPadding)
    .padding(.top, Wire.Actions.top)
    .padding(.bottom, Wire.Actions.bottom)
    .background(
      LinearGradient(
        colors: [Theme.Color.surface.opacity(0), Theme.Color.surface],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }

  private func rowView(_ row: SessionRow) -> some View {
    HStack(alignment: .center, spacing: Wire.Row.spacing) {
      statusIndicator(row.status)
      VStack(alignment: .leading, spacing: 0) {
        Text(row.title)
          .font(.system(size: Wire.Row.titleSize, weight: .medium))
          .foregroundStyle(Theme.Color.ink)
          .lineLimit(1)
        Text(subtitle(row))
          .font(.system(size: Wire.Row.subtitleSize))
          .foregroundStyle(Theme.Color.inkSecondary)
      }
      Spacer(minLength: 0)
    }
    .padding(.leading, row.isChild ? Wire.Row.childIndent : Wire.Row.hPadding)
    .padding(.trailing, Wire.Row.hPadding)
    // Pinned so the row pitch matches the wireframe instead of SwiftUI's line height.
    .frame(height: Wire.Row.height, alignment: .leading)
    .contentShape(Rectangle())
  }

  private var connectionSubtitle: String {
    if case .connected(let version) = service.state {
      return "connected · v\(version)"
    }
    if case .offline(let failure) = service.state {
      return failure.title
    }
    if computer == nil {
      return "add a computer"
    }
    return "connecting"
  }

  private func subtitle(_ row: SessionRow) -> String {
    let state: String
    switch row.status {
    case .idle: state = "done"
    case .busy: state = "running"
    case .retry: state = "retrying"
    }
    return "\(relative(row.updated)) · \(state)"
  }

  private func relative(_ date: Date) -> String {
    let seconds = Date().timeIntervalSince(date)
    if seconds < 60 {
      return "now"
    }
    if seconds < 3600 {
      return "\(Int(seconds / 60)) min"
    }
    if seconds < 86400 {
      return "\(Int(seconds / 3600)) h"
    }
    if seconds < 172800 {
      return "yesterday"
    }
    return "\(Int(seconds / 86400)) days"
  }

  private func color(for status: SessionRow.Status) -> Color {
    switch status {
    case .idle: Theme.Color.inkSecondary.opacity(0.55)
    case .busy: Color.blue
    case .retry: Color.orange
    }
  }

  private func accessibilityLabel(for status: SessionRow.Status) -> String {
    switch status {
    case .idle: "Session idle"
    case .busy: "Session running"
    case .retry: "Session retrying"
    }
  }

  @ViewBuilder
  private func statusIndicator(_ status: SessionRow.Status) -> some View {
    Group {
      if status == .busy {
        PulsingDot(color: color(for: status), size: Wire.Row.dotSize)
      } else {
        Circle()
          .fill(color(for: status))
          .frame(width: Wire.Row.dotSize, height: Wire.Row.dotSize)
      }
    }
    .accessibilityIdentifier("session.status")
    .accessibilityLabel(accessibilityLabel(for: status))
  }

  private func grouped(_ rows: [SessionRow]) -> [(key: String, rows: [SessionRow])] {
    var order: [String] = []
    var buckets: [String: [SessionRow]] = [:]
    for row in rows {
      if buckets[row.group] == nil {
        order.append(row.group)
      }
      buckets[row.group, default: []].append(row)
    }
    return order.map { (key: $0, rows: buckets[$0] ?? []) }
  }
}

private struct PulsingDot: View {
  let color: Color
  let size: CGFloat
  @State private var pulsing = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      Circle()
        .fill(color.opacity(0.35))
        .scaleEffect(reduceMotion ? 1 : (pulsing ? 1.8 : 0.9))
      Circle()
        .fill(color)
    }
    .frame(width: size, height: size)
    .onAppear {
      guard !reduceMotion else { return }
      withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
        pulsing = true
      }
    }
  }
}
