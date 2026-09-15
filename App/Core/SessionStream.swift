import Foundation
import OpenAPIRuntime
import OpenCodeAPI

/// Consumes `GET /event` (server-sent events) and yields the decoded subset we act on.
/// Reconnects with backoff until the consuming task is cancelled.
struct SessionStream: Sendable {
  let client: Client
  let isCurrent: @Sendable () async -> Bool
  let onSubscribed: @Sendable () async -> Void
  let onHealth: @Sendable (Bool) -> Void

  private let activityGate = ActivityGate()

  func events() -> AsyncStream<ServerEvent> {
    AsyncStream { continuation in
      let task = Task {
        var delay = Duration.milliseconds(300)
        while !Task.isCancelled {
          guard await isCurrent() else { break }
          do {
            try await pump(continuation)
            delay = .milliseconds(300)
          } catch {
            onHealth(false)
            if Task.isCancelled { break }
          }
          if Task.isCancelled { break }
          try? await Task.sleep(for: delay)
          delay = min(delay * 2, .seconds(5))
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func pump(_ continuation: AsyncStream<ServerEvent>.Continuation) async throws {
    let output = try await client.event_period_subscribe()
    guard case .ok(let ok) = output, case .text_event_hyphen_stream(let body) = ok.body else {
      throw URLError(.badServerResponse)
    }

    onHealth(true)
    await onSubscribed()

    var buffer = Data()
    for try await chunk in body {
      if activityGate.isDue() {
        onHealth(true)
      }
      buffer.append(contentsOf: chunk)
      while let newline = buffer.firstIndex(of: 0x0A) {
        let line = Data(buffer[buffer.startIndex..<newline])
        buffer.removeSubrange(buffer.startIndex...newline)
        emit(line: line, to: continuation)
      }
    }
  }

  private func emit(line: Data, to continuation: AsyncStream<ServerEvent>.Continuation) {
    guard let text = String(data: line, encoding: .utf8) else { return }
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("data:") else { return }
    let json = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
    guard let data = json.data(using: .utf8), let event = ServerEventDecoder.decode(data) else {
      return
    }
    continuation.yield(event)
  }

  private final class ActivityGate: @unchecked Sendable {
    private let lock = NSLock()
    private var last: ContinuousClock.Instant?

    func isDue() -> Bool {
      lock.lock()
      defer { lock.unlock() }
      let now = ContinuousClock.now
      if let last, last.duration(to: now) < .seconds(1) {
        return false
      }
      last = now
      return true
    }
  }
}
