import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

public enum OpenCodeAPIClient {
  public static func make(
    serverURL: URL,
    session: URLSession = .shared,
    middlewares: [any ClientMiddleware] = []
  ) -> Client {
    Client(
      serverURL: serverURL,
      transport: URLSessionTransport(configuration: .init(session: session)),
      middlewares: middlewares
    )
  }
}
