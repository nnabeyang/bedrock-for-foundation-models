import Foundation

/// Thin HTTP client for `POST /model/{modelId}/converse`.
public struct BedrockRuntimeClient: Sendable {
  public struct Configuration: Hashable, Sendable {
    public var region: String
    public var credentials: BedrockCredentials
    /// How many times a `503` is retried before the error is thrown.
    public var maxRetries: Int
    /// Delay before the first retry; each further retry doubles it.
    public var retryBaseDelay: Duration

    public init(
      region: String,
      credentials: BedrockCredentials,
      maxRetries: Int = 3,
      retryBaseDelay: Duration = .milliseconds(500)
    ) {
      self.region = region
      self.credentials = credentials
      self.maxRetries = maxRetries
      self.retryBaseDelay = retryBaseDelay
    }

    public var host: String { "bedrock-runtime.\(region).amazonaws.com" }
  }

  public let configuration: Configuration
  private let transport: any HTTPTransport
  private let now: @Sendable () -> Date

  /// Production initializer — talks to Bedrock over `URLSession`.
  public init(configuration: Configuration, session: URLSession = .shared) {
    self.init(configuration: configuration, transport: URLSessionTransport(session: session))
  }

  /// Injects the transport and the clock. Production uses the defaults; tests
  /// pass a fake transport and a fixed date so the signature is reproducible.
  public init(
    configuration: Configuration,
    transport: any HTTPTransport,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.configuration = configuration
    self.transport = transport
    self.now = now
  }

  /// Runs one Converse turn.
  public func converse(
    modelId: String,
    request: ConverseRequest
  ) async throws -> ConverseResponse {
    let urlRequest = try urlRequest(modelId: modelId, request: request)

    // Bedrock answers 503 under transient congestion, so retry with
    // exponential backoff before giving up.
    var lastError: any Error = BedrockRuntimeError.invalidResponse("no attempts made")
    for attempt in 0...max(0, configuration.maxRetries) {
      if attempt > 0 {
        try await Task.sleep(for: configuration.retryBaseDelay * (1 << (attempt - 1)))
      }
      let (data, response) = try await transport.data(for: urlRequest)
      guard let http = response as? HTTPURLResponse else {
        throw BedrockRuntimeError.invalidResponse("non-HTTP response")
      }
      guard http.statusCode != 200 else {
        do {
          return try JSONDecoder().decode(ConverseResponse.self, from: data)
        } catch {
          throw BedrockRuntimeError.invalidResponse(String(describing: error))
        }
      }
      lastError = Self.error(from: http, body: data)
      if http.statusCode != 503 { break }
    }
    throw lastError
  }

  // MARK: - Request building

  func urlRequest(modelId: String, request: ConverseRequest) throws -> URLRequest {
    let host = configuration.host
    let encodedModelId =
      modelId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelId
    let path = "/model/\(encodedModelId)/converse"
    guard let url = URL(string: "https://\(host)\(path)") else {
      throw BedrockRuntimeError.invalidURL("https://\(host)\(path)")
    }

    // Encoded once: SigV4 signs these exact bytes, so re-encoding for the body
    // would risk a different key order and a broken signature.
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let body = try encoder.encode(request)

    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.httpBody = body
    urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")

    switch configuration.credentials {
    case .apiKey(let apiKey):
      guard !apiKey.isEmpty else { throw BedrockRuntimeError.missingCredentials }
      urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    case .sigV4(let accessKeyId, let secretKey, let sessionToken):
      guard !accessKeyId.isEmpty, !secretKey.isEmpty else {
        throw BedrockRuntimeError.missingCredentials
      }
      let signer = SigV4Signer(
        credentials: .init(
          accessKeyId: accessKeyId, secretKey: secretKey, sessionToken: sessionToken),
        region: configuration.region
      )
      let headers = signer.headers(
        method: "POST", path: path, host: host, body: body, date: now())
      for (name, value) in headers {
        urlRequest.setValue(value, forHTTPHeaderField: name)
      }
    }
    return urlRequest
  }

  // MARK: - Errors

  static func error(from response: HTTPURLResponse, body: Data) -> BedrockRuntimeError {
    let envelope = try? JSONDecoder().decode(BedrockErrorEnvelope.self, from: body)
    let exceptionType =
      response.value(forHTTPHeaderField: "x-amzn-ErrorType") ?? envelope?.type ?? ""
    // Cap the excerpt so an unexpected error page can't flood logs through
    // errorDescription.
    let maxBodyExcerpt = 512
    let message =
      envelope?.message
      ?? {
        var excerpt = String(decoding: body.prefix(maxBodyExcerpt), as: UTF8.self)
        if body.count > maxBodyExcerpt {
          excerpt += "… [truncated, \(body.count) bytes total]"
        }
        return excerpt
      }()
    return .httpError(
      statusCode: response.statusCode,
      kind: .init(exceptionType: exceptionType),
      message: message
    )
  }
}
