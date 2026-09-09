import Foundation
import Testing

@testable import BedrockRuntimeAPI

/// Replays a canned sequence of responses and records what it was asked for.
/// The last response repeats once the sequence runs out.
private actor FakeTransport: HTTPTransport {
  struct Response: Sendable {
    var status: Int
    var body: Data
    var headers: [String: String] = [:]
  }

  private let responses: [Response]
  private(set) var requests: [URLRequest] = []

  init(_ responses: [Response]) {
    self.responses = responses
  }

  init(status: Int, json: String, headers: [String: String] = [:]) {
    self.init([.init(status: status, body: Data(json.utf8), headers: headers)])
  }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    let response = responses[min(requests.count, responses.count - 1)]
    requests.append(request)
    return (
      response.body,
      HTTPURLResponse(
        url: request.url!,
        statusCode: response.status,
        httpVersion: nil,
        headerFields: response.headers
      )!
    )
  }
}

private let successBody = """
  {"output":{"message":{"role":"assistant","content":[{"text":"hi"}]}},
   "stopReason":"end_turn","usage":{"inputTokens":1,"outputTokens":2,"totalTokens":3}}
  """

private func makeClient(
  transport: any HTTPTransport,
  credentials: BedrockCredentials = .apiKey("secret")
) -> BedrockRuntimeClient {
  BedrockRuntimeClient(
    configuration: .init(
      region: "us-east-1",
      credentials: credentials,
      retryBaseDelay: .zero
    ),
    transport: transport,
    now: { Date(timeIntervalSince1970: 1_757_376_000) }
  )
}

@Suite("BedrockRuntimeClient")
struct BedrockRuntimeClientTests {
  @Test("posts to the model's converse path with the API key as a bearer token")
  func postsWithBearerToken() async throws {
    let transport = FakeTransport(status: 200, json: successBody)
    let response = try await makeClient(transport: transport)
      .converse(modelId: "us.anthropic.claude-sonnet-5-20250929-v1:0", request: .init(messages: []))

    #expect(response.output.message?.content == [.text("hi")])

    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "POST")
    // The colon of an inference-profile id is percent-encoded, and the same
    // encoded path is what SigV4 signs.
    #expect(
      request.url?.absoluteString
        == "https://bedrock-runtime.us-east-1.amazonaws.com/model/us.anthropic.claude-sonnet-5-20250929-v1%3A0/converse"
    )
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")
  }

  @Test("signs the request when given SigV4 credentials")
  func signsWithSigV4() async throws {
    let transport = FakeTransport(status: 200, json: successBody)
    _ = try await makeClient(
      transport: transport,
      credentials: .sigV4(accessKeyId: "AKID", secretKey: "SECRET", sessionToken: "TOKEN")
    ).converse(modelId: "test-model", request: .init(messages: []))

    let request = try #require(await transport.requests.first)
    #expect(request.value(forHTTPHeaderField: "x-amz-date") == "20250909T000000Z")
    #expect(request.value(forHTTPHeaderField: "x-amz-security-token") == "TOKEN")
    #expect(
      request.value(forHTTPHeaderField: "Authorization")?
        .hasPrefix("AWS4-HMAC-SHA256 Credential=AKID/20250909/us-east-1/bedrock/aws4_request")
        == true
    )
  }

  @Test("rejects empty credentials before making a request")
  func rejectsEmptyCredentials() async throws {
    let transport = FakeTransport(status: 200, json: successBody)
    await #expect(throws: BedrockRuntimeError.missingCredentials) {
      try await makeClient(transport: transport, credentials: .apiKey(""))
        .converse(modelId: "test-model", request: .init(messages: []))
    }
    #expect(await transport.requests.isEmpty)
  }

  @Test("retries a 503 and returns the response that follows")
  func retriesServiceUnavailable() async throws {
    let transport = FakeTransport([
      .init(status: 503, body: Data(#"{"message":"busy"}"#.utf8)),
      .init(status: 503, body: Data(#"{"message":"busy"}"#.utf8)),
      .init(status: 200, body: Data(successBody.utf8)),
    ])
    let response = try await makeClient(transport: transport)
      .converse(modelId: "test-model", request: .init(messages: []))

    #expect(response.stopReason == .endTurn)
    #expect(await transport.requests.count == 3)
  }

  @Test("gives up after the retry budget and reports the last error")
  func givesUpAfterRetries() async throws {
    let transport = FakeTransport(status: 503, json: #"{"message":"still busy"}"#)
    await #expect(
      throws: BedrockRuntimeError.httpError(
        statusCode: 503, kind: .other(""), message: "still busy")
    ) {
      try await makeClient(transport: transport)
        .converse(modelId: "test-model", request: .init(messages: []))
    }
    // The first attempt plus three retries.
    #expect(await transport.requests.count == 4)
  }

  @Test("does not retry a status other than 503")
  func doesNotRetryOtherStatuses() async throws {
    let transport = FakeTransport(
      status: 400,
      json: #"{"message":"bad input"}"#,
      headers: ["x-amzn-ErrorType": "ValidationException:http://internal.amazon.com/"]
    )
    await #expect(
      throws: BedrockRuntimeError.httpError(
        statusCode: 400, kind: .validation, message: "bad input")
    ) {
      try await makeClient(transport: transport)
        .converse(modelId: "test-model", request: .init(messages: []))
    }
    #expect(await transport.requests.count == 1)
  }

  @Test("falls back to a truncated body when the error envelope is unreadable")
  func fallsBackToRawBody() async throws {
    let transport = FakeTransport(status: 502, json: "<html>gateway</html>")
    await #expect(
      throws: BedrockRuntimeError.httpError(
        statusCode: 502, kind: .other(""), message: "<html>gateway</html>")
    ) {
      try await makeClient(transport: transport)
        .converse(modelId: "test-model", request: .init(messages: []))
    }
  }

  @Test("reports an undecodable success body as an invalid response")
  func reportsUndecodableSuccessBody() async throws {
    let transport = FakeTransport(status: 200, json: #"{"unexpected":true}"#)
    await #expect(throws: BedrockRuntimeError.self) {
      try await makeClient(transport: transport)
        .converse(modelId: "test-model", request: .init(messages: []))
    }
  }
}

@Suite("BedrockRuntimeError.Kind")
struct BedrockErrorKindTests {
  @Test("strips the decoration around an exception name")
  func stripsDecoration() {
    #expect(BedrockRuntimeError.Kind(exceptionType: "ThrottlingException") == .throttling)
    #expect(
      BedrockRuntimeError.Kind(exceptionType: "ValidationException:http://example.com/")
        == .validation)
    #expect(
      BedrockRuntimeError.Kind(exceptionType: "com.amazonaws.bedrock#ModelNotReadyException")
        == .modelNotReady)
  }

  @Test("carries an unrecognized exception name through")
  func carriesUnknownNameThrough() {
    #expect(
      BedrockRuntimeError.Kind(exceptionType: "BrandNewException") == .other("BrandNewException"))
  }
}
