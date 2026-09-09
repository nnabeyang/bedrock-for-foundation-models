import Foundation
import Testing

@testable import BedrockForFoundationModels
@testable import BedrockRuntimeAPI

// `BedrockAuth` and `BedrockError` carry no availability constraint, so these
// tests need no gate. The rest of the bridge is gated `@available(anyAppleOS
// 27, *)`; it is exercised under that same gate in `ConverseRequestBuilderTests`
// and `ConverseResponseTranslatorTests`.

@Suite("BedrockAuth")
struct BedrockAuthTests {
  @Test("carries an API key through to the client's credentials")
  func mapsAPIKey() {
    #expect(BedrockAuth.apiKey("secret").credentials == .apiKey("secret"))
  }

  @Test("carries SigV4 credentials through, session token included")
  func mapsSigV4() {
    let auth = BedrockAuth.sigV4(
      accessKeyId: "AKID", secretKey: "SECRET", sessionToken: "TOKEN")
    #expect(
      auth.credentials
        == .sigV4(accessKeyId: "AKID", secretKey: "SECRET", sessionToken: "TOKEN"))
  }

  @Test("keeps an absent session token absent")
  func mapsSigV4WithoutSessionToken() {
    let auth = BedrockAuth.sigV4(accessKeyId: "AKID", secretKey: "SECRET", sessionToken: nil)
    #expect(auth.credentials == .sigV4(accessKeyId: "AKID", secretKey: "SECRET", sessionToken: nil))
  }
}

@Suite("BedrockError")
struct BedrockErrorTests {
  @Test("keeps the status and message when mapping an HTTP failure")
  func mapsHTTPError() {
    let error = BedrockError(
      .httpError(statusCode: 400, kind: .validation, message: "bad input"))
    guard case .httpError(let statusCode, let message) = error else {
      Issue.record("wrong case")
      return
    }
    #expect(statusCode == 400)
    #expect(message == "bad input")
  }

  @Test("maps the remaining client failures onto their counterparts")
  func mapsOtherFailures() {
    #expect(BedrockError(.missingCredentials).errorDescription?.contains("Missing AWS") == true)
    #expect(BedrockError(.invalidURL("x")).errorDescription == "Invalid Bedrock URL: x")
    #expect(
      BedrockError(.invalidResponse("nope")).errorDescription == "Bedrock invalid response: nope")
  }
}
