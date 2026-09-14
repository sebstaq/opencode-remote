import Foundation

enum ConnectionFailure: Equatable, Sendable {
  case invalidURL
  case unreachable
  case tls
  case unauthorized
  case timedOut
  case unsupportedVersion(server: String, minimum: String)
  case unknown(String)

  var title: String {
    switch self {
    case .invalidURL: "Invalid URL"
    case .unreachable: "Can't reach the computer"
    case .tls: "Secure connection failed"
    case .unauthorized: "Wrong password"
    case .timedOut: "Connection timed out"
    case .unsupportedVersion: "Server version not supported"
    case .unknown: "Something went wrong"
    }
  }

  var message: String {
    switch self {
    case .invalidURL: "Use a full https URL."
    case .unreachable: "Check that OpenCode is running and that Tailscale is connected on both devices."
    case .tls: "The secure connection to the server failed."
    case .unauthorized: "Check the server password and try again."
    case .timedOut: "The server did not respond in time."
    case .unsupportedVersion(let server, let minimum):
      "This computer runs OpenCode \(server). OpenCode Remote needs \(minimum) or newer."
    case .unknown(let detail): detail
    }
  }
}
