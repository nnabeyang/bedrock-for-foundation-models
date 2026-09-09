import Foundation

/// Credentials the Bedrock Runtime endpoint accepts.
public enum BedrockCredentials: Hashable, Sendable {
  /// A Bedrock API key, sent as a bearer token.
  case apiKey(String)

  /// AWS SigV4 credentials, including an optional temporary session token.
  case sigV4(accessKeyId: String, secretKey: String, sessionToken: String?)
}
