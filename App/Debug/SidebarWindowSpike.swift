#if DEBUG
  import SwiftUI
  import UIKit

  /// Spike: can the system keyboard be translated to follow the chat panel?
  /// `OPENCODE_UI_SPIKE=window` (sidebar + offset chat window, keyboard moved).
  struct SidebarWindowSpike: View {
    @State private var chatWindow: ChatWindow?
    private let variant = ProcessInfo.processInfo.environment["OPENCODE_UI_SPIKE"] ?? "window"

    var body: some View {
      ZStack(alignment: .topLeading) {
        Color(red: 0.97, green: 0.97, blue: 0.98)
          .ignoresSafeArea()
        VStack(alignment: .leading, spacing: 8) {
          Text("SIDEBAR")
            .font(.system(size: 30, weight: .bold))
          Text("main window, stationary")
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
        }
        .padding(24)
      }
      .onAppear { openChatWindow() }
    }

    private func openChatWindow() {
      guard chatWindow == nil,
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
      else { return }
      let window = ChatWindow(scene: scene, sidebarWidth: 330)
      window.show()
      chatWindow = window
      if variant == "windowonly" {
        for other in scene.windows where other !== window.window {
          other.isHidden = true
        }
      }
    }
  }

  @MainActor
  final class ChatWindow {
    let window: UIWindow
    private let sidebarWidth: CGFloat

    init(scene: UIWindowScene, sidebarWidth: CGFloat) {
      self.sidebarWidth = sidebarWidth
      let bounds = scene.coordinateSpace.bounds
      window = UIWindow(windowScene: scene)
      window.frame = CGRect(
        x: sidebarWidth, y: 0, width: bounds.width - sidebarWidth, height: bounds.height)
      window.windowLevel = .normal
      window.backgroundColor = .clear

      let root = UIHostingController(rootView: ChatPanelSpike())
      root.view.backgroundColor = .white
      root.view.layer.cornerRadius = 16
      root.view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
      root.view.layer.cornerCurve = .continuous
      root.view.layer.masksToBounds = true
      window.rootViewController = root
    }

    func show() {
      window.isHidden = false
      window.makeKeyAndVisible()
    }
  }

  @MainActor
  enum KeyboardMover {
    /// The keyboard lives in its own window; translate it to follow the panel.
    static func windows() -> [UIWindow] {
      let all = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
      return all.filter { window in
        let name = String(describing: type(of: window)).lowercased()
        return name.contains("keyboard") || name.contains("remote") || name.contains("textEffects")
          || window.windowLevel.rawValue > 0
      }
    }

    static func translate(by dx: CGFloat) {
      for window in windows() {
        window.transform = CGAffineTransform(translationX: dx, y: 0)
      }
    }

    static func reset() {
      for window in windows() {
        window.transform = .identity
      }
    }

    static func describe() -> String {
      let all = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
      let lines = all.map {
        "\(String(describing: type(of: $0))) L\($0.windowLevel.rawValue) x\(Int($0.frame.minX)) w\(Int($0.frame.width))"
      }
      let effects = all.first { String(describing: type(of: $0)).contains("TextEffects") }
      let subs = effects?.subviews.map { String(describing: type(of: $0)) } ?? []
      return (lines + ["subviews:", subs.joined(separator: ",")]).joined(separator: "\n")
    }
  }

  struct ChatPanelSpike: View {
    @State private var text = ""
    @State private var diagnostics = "windows: …"
    @FocusState private var focused: Bool
    private let sidebarWidth: CGFloat = 330

    var body: some View {
      ZStack {
        Color.white
        VStack(alignment: .leading, spacing: 10) {
          Text("CHAT WINDOW")
            .font(.system(size: 18, weight: .semibold))
          Text(diagnostics)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.red)
          Spacer()
          TextField("Ask anything…", text: $text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
            .focused($focused)
            .accessibilityIdentifier("spike.field")
        }
        .padding(18)
      }
      .onAppear {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { focused = true }
      }
      .onReceive(
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
      ) { _ in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          KeyboardMover.translate(by: sidebarWidth)
          diagnostics = KeyboardMover.describe()
        }
      }
      .onReceive(
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
      ) { _ in
        KeyboardMover.reset()
      }
    }
  }
#endif
