import SwiftUI

/// Design tokens taken 1:1 from `docs/wireframes/index.html` (CSS px == pt).
private enum Wire {
  static let ink = Color(red: 0x11 / 255, green: 0x12 / 255, blue: 0x14 / 255)
  static let muted = Color(red: 0x6B / 255, green: 0x72 / 255, blue: 0x80 / 255)
  static let line = Color(red: 0xD5 / 255, green: 0xD7 / 255, blue: 0xDB / 255)
  static let fill2 = Color(red: 0xE6 / 255, green: 0xE8 / 255, blue: 0xEB / 255)
  static let idleDot = Color(red: 0x9C / 255, green: 0xA3 / 255, blue: 0xAF / 255)

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
  let computer: Computer
  let store: ComputerStore
  let service: ConnectionService
  let sessions: SessionsModel
  let shell: ShellModel
  let onSwitch: (Computer) -> Void

  var body: some View {
    ZStack(alignment: .bottom) {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Text("Sessions")
            .font(.system(size: Wire.Header.titleSize, weight: .bold))
            .foregroundStyle(Wire.ink)
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

      actions
    }
    .frame(width: Wire.drawerWidth)
    .frame(maxHeight: .infinity, alignment: .topLeading)
    .background(Color(.systemBackground).ignoresSafeArea())
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
            systemImage: stored.id == computer.id ? "checkmark" : "desktopcomputer"
          )
        }
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
          .fill(Wire.fill2)
          .frame(width: Wire.Header.iconSize, height: Wire.Header.iconSize)
        VStack(alignment: .leading, spacing: 2) {
          Text(computer.name)
            .font(.system(size: Wire.Header.nameSize, weight: .semibold))
            .foregroundStyle(Wire.ink)
            .lineLimit(1)
          Text(connectionSubtitle)
            .font(.system(size: Wire.Header.subtitleSize))
            .foregroundStyle(Wire.muted)
            .lineLimit(1)
        }
        Spacer(minLength: 4)
        Image(systemName: "chevron.down")
          .font(.system(size: Wire.Header.chevronSize, weight: .regular))
          .foregroundStyle(Wire.muted)
      }
      .padding(.vertical, Wire.Header.rowPadding)
      .contentShape(Rectangle())
    }
    .tint(Wire.ink)
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
        .foregroundStyle(Wire.muted)
        .padding(.horizontal, Wire.hPadding)
    case .loaded(let rows):
      if rows.isEmpty {
        Text("No sessions yet")
          .font(.system(size: Wire.Row.subtitleSize))
          .foregroundStyle(Wire.muted)
          .padding(.horizontal, Wire.hPadding)
      } else {
        ForEach(grouped(rows), id: \.key) { group in
          HStack(spacing: Wire.Group.spacing) {
            Image(systemName: "chevron.up")
              .font(.system(size: Wire.Group.chevronSize, weight: .semibold))
            Text(group.key.uppercased())
              .font(.system(size: Wire.Group.fontSize, weight: .semibold))
              .tracking(Wire.Group.tracking)
          }
          .foregroundStyle(Wire.muted)
          .padding(.horizontal, Wire.hPadding)
          .padding(.top, Wire.Group.top)
          .padding(.bottom, Wire.Group.bottom)
          .frame(height: Wire.Group.height, alignment: .leading)

          ForEach(group.rows) { row in
            Button {
              shell.selectedSession = row
              shell.showSidebar = false
            } label: {
              rowView(row)
            }
            .tint(Wire.ink)
            .accessibilityIdentifier("session.row")
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
        .foregroundStyle(.white)
        .padding(.horizontal, Wire.Actions.composeHPadding)
        .padding(.vertical, Wire.Actions.composeVPadding)
        .background(Wire.ink, in: Capsule())
      }
      .accessibilityIdentifier("sidebar.newSession")

      Spacer(minLength: 0)

      Button {
        shell.sheet = .settings
      } label: {
        Image(systemName: "gearshape")
          .font(.system(size: Wire.Actions.gearIconSize))
          .foregroundStyle(Wire.ink)
          .frame(width: Wire.Actions.gearSize, height: Wire.Actions.gearSize)
          .background(Color(.systemBackground), in: Circle())
          .overlay(Circle().stroke(Wire.line, lineWidth: 1))
      }
      .accessibilityIdentifier("sidebar.settings")
    }
    .padding(.leading, Wire.Actions.hPadding)
    .padding(.trailing, Wire.Actions.hPadding)
    .padding(.top, Wire.Actions.top)
    .padding(.bottom, Wire.Actions.bottom)
    .background(
      LinearGradient(
        colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }

  private func rowView(_ row: SessionRow) -> some View {
    HStack(alignment: .center, spacing: Wire.Row.spacing) {
      Circle()
        .fill(color(for: row.status))
        .frame(width: Wire.Row.dotSize, height: Wire.Row.dotSize)
      VStack(alignment: .leading, spacing: 0) {
        Text(row.title)
          .font(.system(size: Wire.Row.titleSize, weight: .medium))
          .foregroundStyle(Wire.ink)
          .lineLimit(1)
        Text(subtitle(row))
          .font(.system(size: Wire.Row.subtitleSize))
          .foregroundStyle(Wire.muted)
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
    case .idle: Wire.idleDot
    case .busy: Wire.ink
    case .retry: Wire.muted
    }
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
