import BedrockRuntimeAPI
import Foundation

/// Errors the Bedrock provider surfaces that don't map onto a
/// `LanguageModelError` case.
enum BedrockError: Error, LocalizedError {
  case missingCredentials
  case invalidURL(String)
  case httpError(Int, String)
  case invalidResponse(String)
  case unsupportedAttachment
  case unencodableImage
  case imageTooLarge(Int)

  var errorDescription: String? {
    switch self {
    case .missingCredentials:
      return
        "Missing AWS credentials. Provide either a Bedrock API key or an access key ID and secret access key."
    case .invalidURL(let url): return "Invalid Bedrock URL: \(url)"
    case .httpError(let code, let body): return "Bedrock HTTP error \(code): \(body)"
    case .invalidResponse(let msg): return "Bedrock invalid response: \(msg)"
    case .unsupportedAttachment:
      return "Bedrock cannot send this kind of attachment; only images are supported."
    case .unencodableImage: return "The image attachment could not be encoded as JPEG."
    case .imageTooLarge(let byteCount):
      return "The image attachment is too large for Bedrock (\(byteCount) bytes after compression)."
    }
  }
}

extension BedrockError {
  /// Maps a client-level failure onto the provider's own error vocabulary, so
  /// the wire layer's types don't leak out of the package's public surface.
  init(_ error: BedrockRuntimeError) {
    switch error {
    case .missingCredentials:
      self = .missingCredentials
    case .invalidURL(let url):
      self = .invalidURL(url)
    case .httpError(let statusCode, _, let message):
      self = .httpError(statusCode, message)
    case .invalidResponse(let message):
      self = .invalidResponse(message)
    }
  }
}
