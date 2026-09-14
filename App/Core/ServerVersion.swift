import Foundation

struct ServerVersion: Comparable, Sendable {
  let raw: String
  private let numbers: [Int]

  init(_ raw: String) {
    self.raw = raw
    let core = raw.split(separator: "-", maxSplits: 1).first.map(String.init) ?? raw
    numbers = core.split(separator: ".").map { part in
      Int(part.prefix { $0.isNumber }) ?? 0
    }
  }

  static func < (lhs: ServerVersion, rhs: ServerVersion) -> Bool {
    let count = max(lhs.numbers.count, rhs.numbers.count)
    for index in 0..<count {
      let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
      let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
      if left != right {
        return left < right
      }
    }
    return false
  }

  static let minimumSupported = ServerVersion("1.18.30")
}
