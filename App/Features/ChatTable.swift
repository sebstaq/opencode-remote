import SwiftUI
import UIKit

/// A `UITableView`-backed chat timeline.
///
/// Derived from SwiftChat's `MessageTableView`
/// (`third-party/swiftchat/d6f54cc/MessageTableView.swift`, MIT); see
/// `third-party/swiftchat/d6f54cc/PATCH.diff` for every change. The reason for
/// dropping to UIKit is the scroll control: `contentOffset`, `contentSize` and
/// `contentInset` are exact, `scrollToRow` is reliable, and `isDragging` is a
/// real signal — none of which SwiftUI's `ScrollView` gives us.
///
/// The rules kept from the donor:
/// - Bottom is `contentSize.height - bounds.height + contentInset.bottom`.
/// - A user drag sets `userHasScrolled`; following stops until we are back at
///   the bottom (`scrollViewDidScroll` clears it).
/// - Landing at the bottom waits for the last row to appear (`willDisplay`),
///   with a short retry, so a tall streamed row is measured first.
/// - A keyboard that opens while at the bottom re-pins.
@MainActor
struct ChatTable<Row: View>: UIViewRepresentable {
  let messages: [ChatMessage]
  let isLoading: Bool
  let expandedReasoning: Set<String>
  @Binding var isAtBottom: Bool
  @Binding var userHasScrolled: Bool
  let scrollToBottomTrigger: UUID
  let keyboardHeight: CGFloat
  let row: (ChatMessage) -> Row

  func makeUIView(context: Context) -> UITableView {
    let tableView = UITableView(frame: .zero, style: .plain)
    tableView.backgroundColor = .clear
    tableView.separatorStyle = .none
    tableView.delegate = context.coordinator
    tableView.dataSource = context.coordinator
    tableView.keyboardDismissMode = .onDrag
    tableView.allowsSelection = false
    tableView.estimatedRowHeight = 120
    tableView.rowHeight = UITableView.automaticDimension
    tableView.showsVerticalScrollIndicator = true
    tableView.contentInsetAdjustmentBehavior = .automatic
    tableView.clipsToBounds = false
    context.coordinator.tableView = tableView
    return tableView
  }

  func updateUIView(_ tableView: UITableView, context: Context) {
    context.coordinator.parent = self
    let coordinator = context.coordinator

    if coordinator.lastKeyboardHeight != keyboardHeight {
      let wasAtBottom = isAtBottom
      coordinator.lastKeyboardHeight = keyboardHeight
      if wasAtBottom && keyboardHeight > 0 {
        Task { @MainActor in
          try? await Task.sleep(for: .seconds(0.05))
          coordinator.scrollToBottom(animated: true)
        }
      }
    }

    let ids = messages.map(\.id)
    if ids != coordinator.lastMessageIds {
      let live = Set(ids)
      coordinator.boxes = coordinator.boxes.filter { live.contains($0.key) }
      coordinator.lastMessageIds = ids
    }

    let countChanged = messages.count != coordinator.lastMessageCount
    let reasoningChanged = expandedReasoning != coordinator.lastExpandedReasoning

    if countChanged {
      coordinator.lastMessageCount = messages.count
      coordinator.lastExpandedReasoning = expandedReasoning
      tableView.reloadData()
      if !userHasScrolled {
        coordinator.shouldScrollToBottomAfterLayout = true
      }
    } else if reasoningChanged {
      coordinator.lastExpandedReasoning = expandedReasoning
      tableView.reloadData()
    } else if isLoading, let last = messages.last {
      // Streaming: update the last cell in place, then stay pinned when the
      // reader has not taken over.
      coordinator.box(for: last).update(message: last)
      if !userHasScrolled {
        coordinator.scrollToBottom(animated: false)
      }
    }

    if coordinator.lastLoading != isLoading {
      coordinator.lastLoading = isLoading
      if !isLoading, let last = messages.last {
        coordinator.box(for: last).update(message: last)
      }
    }

    if coordinator.lastTrigger != scrollToBottomTrigger {
      coordinator.lastTrigger = scrollToBottomTrigger
      coordinator.shouldScrollToBottomAfterLayout = true
      coordinator.scrollToBottom(animated: false)
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(0.3))
        if coordinator.shouldScrollToBottomAfterLayout {
          coordinator.scrollToBottom(animated: false)
          coordinator.shouldScrollToBottomAfterLayout = false
        }
      }
    }

    coordinator.checkIfAtBottom()
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  @MainActor
  final class Coordinator: NSObject, UITableViewDelegate, UITableViewDataSource {
    var parent: ChatTable
    weak var tableView: UITableView?
    var boxes: [String: ChatMessageBox] = [:]
    var lastMessageIds: [String] = []
    var lastMessageCount = 0
    var lastExpandedReasoning: Set<String> = []
    var lastLoading = false
    var lastKeyboardHeight: CGFloat = 0
    var lastTrigger: UUID?
    var shouldScrollToBottomAfterLayout = false

    init(_ parent: ChatTable) {
      self.parent = parent
    }

    func box(for message: ChatMessage) -> ChatMessageBox {
      if let existing = boxes[message.id] {
        return existing
      }
      let box = ChatMessageBox(message: message)
      boxes[message.id] = box
      return box
    }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
      parent.messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
      let identifier = "MessageCell"
      let cell =
        tableView.dequeueReusableCell(withIdentifier: identifier)
        ?? UITableViewCell(style: .default, reuseIdentifier: identifier)
      cell.selectionStyle = .none
      cell.backgroundColor = .clear

      let message = parent.messages[indexPath.row]
      let box = box(for: message)
      if box.message != message {
        box.update(message: message)
      }
      cell.contentConfiguration = UIHostingConfiguration {
        ChatTableCell(box: box, row: parent.row)
      }
      .minSize(width: 0, height: 0)
      .margins(.all, 0)
      .background(.clear)

      return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
      guard shouldScrollToBottomAfterLayout else { return }
      guard indexPath.row == tableView.numberOfRows(inSection: 0) - 1 else { return }
      scrollToBottom(animated: false)
      shouldScrollToBottomAfterLayout = false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
      checkIfAtBottom()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
      parent.userHasScrolled = true
      shouldScrollToBottomAfterLayout = false
      UIView.animate(withDuration: 0.3) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
      }
    }

    func scrollToBottom(animated: Bool) {
      guard let tableView, !parent.messages.isEmpty else { return }
      let rows = tableView.numberOfRows(inSection: 0)
      guard rows == parent.messages.count, rows > 0 else { return }
      tableView.scrollToRow(at: IndexPath(row: rows - 1, section: 0), at: .bottom, animated: animated)
    }

    /// The donor's bottom test: exact, with a generous slack so a row that is
    /// still settling does not read as "scrolled away".
    func checkIfAtBottom() {
      guard let tableView, tableView.window != nil else { return }
      let maxOffset =
        tableView.contentSize.height - tableView.bounds.height + tableView.contentInset.bottom
      let distanceFromBottom = maxOffset - tableView.contentOffset.y
      let isVisible = distanceFromBottom <= 150

      if parent.isAtBottom != isVisible {
        parent.isAtBottom = isVisible
        if isVisible {
          parent.userHasScrolled = false
        }
      }
    }
  }
}

/// Per-message box so the streaming last cell can update without a table
/// reload. Adapted from the donor's `ObservableMessageWrapper`.
@MainActor
final class ChatMessageBox: ObservableObject {
  @Published var message: ChatMessage

  init(message: ChatMessage) {
    self.message = message
  }

  func update(message: ChatMessage) {
    guard self.message != message else { return }
    // Deferred so UIHostingConfiguration sees the objectWillChange on the next
    // run loop tick (same reason as the donor).
    Task { @MainActor in
      self.message = message
    }
  }
}

private struct ChatTableCell<Row: View>: View {
  @ObservedObject var box: ChatMessageBox
  let row: (ChatMessage) -> Row

  var body: some View {
    row(box.message)
  }
}
