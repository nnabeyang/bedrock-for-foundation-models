import Foundation

/// The HTTP seam ``BedrockRuntimeClient`` talks through. Production uses
/// ``URLSessionTransport``; tests inject a fake so the client can be exercised
/// without a network.
public protocol HTTPTransport: Sendable {
  func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// `URLSession`-backed transport used in production.
public struct URLSessionTransport: HTTPTransport {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    try await session.data(for: request)
  }
}
