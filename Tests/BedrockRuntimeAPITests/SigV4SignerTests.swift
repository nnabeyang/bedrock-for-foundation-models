import Foundation
import Testing

@testable import BedrockRuntimeAPI

@Suite("SigV4Signer")
struct SigV4SignerTests {
  private let date = Date(timeIntervalSince1970: 1_757_376_000)  // 2025-09-09T00:00:00Z

  private func signer(sessionToken: String? = nil) -> SigV4Signer {
    SigV4Signer(
      credentials: .init(
        accessKeyId: "AKIDEXAMPLE",
        secretKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
        sessionToken: sessionToken
      ),
      region: "us-east-1"
    )
  }

  @Test("formats the signing timestamp as YYYYMMDD'T'HHMMSS'Z' in UTC")
  func formatsTimestamp() {
    #expect(SigV4Signer.amzDate(from: date) == "20250909T000000Z")
  }

  @Test("produces a stable Authorization header for a fixed date and body")
  func producesStableSignature() {
    let headers = signer().headers(
      method: "POST",
      path: "/model/test-model/converse",
      host: "bedrock-runtime.us-east-1.amazonaws.com",
      body: Data(#"{"messages":[]}"#.utf8),
      date: date
    )

    #expect(headers["host"] == "bedrock-runtime.us-east-1.amazonaws.com")
    #expect(headers["x-amz-date"] == "20250909T000000Z")
    #expect(headers["x-amz-security-token"] == nil)
    #expect(
      headers["Authorization"] == """
        AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20250909/us-east-1/bedrock/aws4_request, \
        SignedHeaders=content-type;host;x-amz-date, \
        Signature=6a4e89c1c7bf313e117e131256946bb73491c1b0a58b465d68216d765d5baea8
        """)
  }

  @Test("signs the session token in when one is present")
  func signsSessionToken() {
    let headers = signer(sessionToken: "session-token").headers(
      method: "POST",
      path: "/model/test-model/converse",
      host: "bedrock-runtime.us-east-1.amazonaws.com",
      body: Data(#"{"messages":[]}"#.utf8),
      date: date
    )

    #expect(headers["x-amz-security-token"] == "session-token")
    let authorization = headers["Authorization"] ?? ""
    #expect(authorization.contains("SignedHeaders=content-type;host;x-amz-date;x-amz-security-token"))
  }

  @Test("a different body yields a different signature")
  func bodyChangesSignature() {
    func authorization(body: String) -> String? {
      signer().headers(
        method: "POST",
        path: "/model/test-model/converse",
        host: "bedrock-runtime.us-east-1.amazonaws.com",
        body: Data(body.utf8),
        date: date
      )["Authorization"]
    }
    #expect(authorization(body: #"{"a":1}"#) != authorization(body: #"{"a":2}"#))
  }
}
