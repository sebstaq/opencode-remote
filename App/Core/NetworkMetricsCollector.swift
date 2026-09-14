import Foundation

final class NetworkMetricsCollector: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private var latest: URLSessionTaskMetrics?

  func take() -> URLSessionTaskMetrics? {
    lock.lock()
    defer { lock.unlock() }
    let value = latest
    latest = nil
    return value
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didFinishCollecting metrics: URLSessionTaskMetrics
  ) {
    lock.lock()
    latest = metrics
    lock.unlock()
  }
}
