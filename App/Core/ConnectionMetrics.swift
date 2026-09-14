import Foundation
import os

@MainActor
final class ConnectionMetrics {
  private let signposter = OSSignposter(subsystem: "dev.sebstaq.opencode.remote", category: "connection")
  private let clock = ContinuousClock()
  private let start: ContinuousClock.Instant
  private var interval: OSSignpostIntervalState?
  private(set) var seconds: [String: Double] = [:]

  init() {
    start = clock.now
    interval = signposter.beginInterval("connect")
  }

  func mark(_ name: String) {
    seconds[name] = elapsed
    signposter.emitEvent("milestone", "\(name)")
  }

  func addNetwork(_ metrics: URLSessionTaskMetrics?) {
    guard let transaction = metrics?.transactionMetrics.last else {
      return
    }
    if let begin = transaction.domainLookupStartDate, let end = transaction.domainLookupEndDate {
      seconds["network.dns"] = end.timeIntervalSince(begin)
    }
    if let begin = transaction.connectStartDate, let end = transaction.connectEndDate {
      seconds["network.tcp"] = end.timeIntervalSince(begin)
    }
    if let begin = transaction.secureConnectionStartDate, let end = transaction.secureConnectionEndDate {
      seconds["network.tls"] = end.timeIntervalSince(begin)
    }
    if let begin = transaction.requestStartDate, let end = transaction.responseStartDate {
      seconds["network.ttfb"] = end.timeIntervalSince(begin)
    }
  }

  func finish() {
    seconds["total"] = elapsed
    if let interval {
      signposter.endInterval("connect", interval)
    }
    interval = nil
  }

  private var elapsed: Double {
    let duration = start.duration(to: clock.now)
    return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
  }
}
