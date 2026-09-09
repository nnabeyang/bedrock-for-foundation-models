import BedrockRuntimeAPI
import Foundation

/// Credentials used to access the Amazon Bedrock Runtime API.
public enum BedrockAuth: Hashable, Sendable {
  /// A Bedrock API key sent as a bearer token.
  case apiKey(String)

  /// AWS SigV4 credentials, including an optional temporary session token.
  case sigV4(accessKeyId: String, secretKey: String, sessionToken: String?)

  var credentials: BedrockCredentials {
    switch self {
    case .apiKey(let apiKey):
      .apiKey(apiKey)
    case .sigV4(let accessKeyId, let secretKey, let sessionToken):
      .sigV4(accessKeyId: accessKeyId, secretKey: secretKey, sessionToken: sessionToken)
    }
  }
}
