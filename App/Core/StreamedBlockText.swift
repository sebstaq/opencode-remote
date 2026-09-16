import Foundation
import SwiftStreamingMarkdown
import SwiftUI
import UIKit
import os

/// Feeds the live (still-growing) markdown of one chat block into
/// `StreamedMarkdownView`. The model yields complete snapshots on each flush;
/// the library parses each snapshot incrementally on a background queue.
@MainActor
final class StreamedBlockText: ObservableObject, StreamedMarkdownSource {
  let text: AsyncStream<String>
  private var continuation: AsyncStream<String>.Continuation
  private(set) var current = ""
  private var lastYield: ContinuousClock.Instant?

  init() {
    var captured: AsyncStream<String>.Continuation?
    self.text = AsyncStream { captured = $0 }
    self.continuation = captured!
  }

  /// The library re-parses and re-renders the whole snapshot per emission, so
  /// the per-update main-thread cost grows with the block. Long blocks
  /// therefore update the view at a reduced cadence; the model still mutates
  /// on the fixed flush tick, and `finish()` always yields the final text.
  func update(_ full: String) {
    current = full
    let now = ContinuousClock.now
    if let lastYield {
      let minimum = full.count > 1_500 ? Duration.milliseconds(400) : .zero
      guard lastYield.duration(to: now) >= minimum else { return }
    }
    lastYield = now
    continuation.yield(full)
  }

  /// Signals that the block will not grow anymore; the view stops observing.
  func finish() {
    continuation.finish()
  }
}

/// Font sets for the document renderer, mapped to our theme sizes.
/// `MDFont` is `UIFont`; sizes are Dynamic-Type scaled like the library does.
enum DocFonts {
  static let body = set(17, weight: .regular)
  static let small = set(15, weight: .regular)

  static let mono = TextFonts(
    normal: MDFont.monospacedSystemFont(ofSize: scaled(14), weight: .regular),
    italic: nil,
    bold: MDFont.monospacedSystemFont(ofSize: scaled(14), weight: .semibold),
    boldItalic: nil,
    preferredLetterSpacing: nil,
    preferredLineHeight: nil
  )

  struct Heading {
    let h1: TextFonts
    let h2: TextFonts
    let h3: TextFonts
  }

  static let heading = Heading(
    h1: set(22, weight: .bold),
    h2: set(17, weight: .semibold),
    h3: set(15, weight: .semibold)
  )

  private static func scaled(_ size: CGFloat) -> CGFloat {
    UIFontMetrics.default.scaledValue(for: size)
  }

  private static func set(_ size: CGFloat, weight: MDFont.Weight) -> TextFonts {
    let scaledSize = scaled(size)
    let normal = MDFont.systemFont(ofSize: scaledSize, weight: weight)
    let semibold = MDFont.systemFont(ofSize: scaledSize, weight: .semibold)
    return TextFonts(
      normal: normal,
      italic: Self.italicized(normal),
      bold: semibold,
      boldItalic: Self.italicized(semibold),
      preferredLetterSpacing: nil,
      preferredLineHeight: nil
    )
  }

  private static func italicized(_ font: MDFont) -> MDFont {
    guard let traits = font.fontDescriptor.withSymbolicTraits(.traitItalic) else { return font }
    return MDFont(descriptor: traits, size: font.pointSize)
  }
}
