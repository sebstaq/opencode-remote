import Foundation
import QuartzCore
import SwiftUI
import os

/// DEBUG-only frame-budget meter for streaming verification. Counts missed
/// display-link ticks while the app runs; the measurement script reads the
/// tally from the unified log after a fixture run.
@MainActor
final class FrameDropMonitor {
  static let shared = FrameDropMonitor()

  private static let logger = Logger(
    subsystem: "dev.sebstaq.opencode", category: "frameDrop")
  private var link: CADisplayLink?
  private var lastTick: CFTimeInterval?

  private init() {}

  func start() {
    guard link == nil else { return }
    let link = CADisplayLink(target: self, selector: #selector(tick))
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  @objc private func tick(_ link: CADisplayLink) {
    let now = link.timestamp
    defer { lastTick = now }
    guard let lastTick else { return }
    let expected = max(link.targetTimestamp - link.timestamp, 1.0 / 120.0)
    let interval = now - lastTick
    guard interval > expected * 1.75 else { return }
    Self.logger.notice("drop interval=\(interval, format: .fixed(precision: 3))s")
  }
}
