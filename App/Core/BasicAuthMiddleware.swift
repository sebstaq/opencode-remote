import Foundation
import HTTPTypes
import OpenAPIRuntime

struct BasicAuthMiddleware: ClientMiddleware {
  let username: String
  let password: String

  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String,
    next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPResponse, HTTPBody?) {
    var request = request
    let credentials = Data("\(username):\(password)".utf8).base64EncodedString()
    request.headerFields[.authorization] = "Basic \(credentials)"
    return try await next(request, body, baseURL)
  }
}
