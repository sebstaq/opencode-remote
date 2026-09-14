import Foundation

enum ConnectionState: Equatable, Sendable {
  case idle
  case connecting
  case connected(version: String)
  case reconnecting
  case offline(ConnectionFailure)
}
