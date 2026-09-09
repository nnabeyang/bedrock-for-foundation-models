import Foundation

/// Failures ``BedrockRuntimeClient`` reports.
public enum BedrockRuntimeError: Error, Hashable, Sendable {
  /// The configured credentials were empty.
  case missingCredentials
  case invalidURL(String)
  /// The service answered with an error status. `kind` comes from the
  /// `x-amzn-ErrorType` header or the body's `__type`, whichever is present.
  case httpError(statusCode: Int, kind: Kind, message: String)
  /// The response reached us but could not be read as a Converse response.
  case invalidResponse(String)

  /// The exception the service named. Bedrock keeps adding these, so an
  /// unrecognized name is carried through rather than lost.
  public enum Kind: Hashable, Sendable {
    case accessDenied
    case internalServer
    case modelError
    case modelNotReady
    case modelTimeout
    case resourceNotFound
    case serviceQuotaExceeded
    case serviceUnavailable
    case throttling
    case validation
    case other(String)

    /// Reads the exception name out of an `x-amzn-ErrorType` header or a
    /// `__type` body field. Both may carry decoration the name has to be
    /// stripped of: `ValidationException:http://…` and
    /// `com.amazonaws.bedrock#ValidationException`.
    public init(exceptionType: String) {
      var name = exceptionType
      if let colon = name.firstIndex(of: ":") { name = String(name[name.startIndex..<colon]) }
      if let hash = name.lastIndex(of: "#") { name = String(name[name.index(after: hash)...]) }
      self =
        switch name {
        case "AccessDeniedException": .accessDenied
        case "InternalServerException": .internalServer
        case "ModelErrorException": .modelError
        case "ModelNotReadyException": .modelNotReady
        case "ModelTimeoutException": .modelTimeout
        case "ResourceNotFoundException": .resourceNotFound
        case "ServiceQuotaExceededException": .serviceQuotaExceeded
        case "ServiceUnavailableException": .serviceUnavailable
        case "ThrottlingException": .throttling
        case "ValidationException": .validation
        default: .other(name)
        }
    }

    public var name: String {
      switch self {
      case .accessDenied: "AccessDeniedException"
      case .internalServer: "InternalServerException"
      case .modelError: "ModelErrorException"
      case .modelNotReady: "ModelNotReadyException"
      case .modelTimeout: "ModelTimeoutException"
      case .resourceNotFound: "ResourceNotFoundException"
      case .serviceQuotaExceeded: "ServiceQuotaExceededException"
      case .serviceUnavailable: "ServiceUnavailableException"
      case .throttling: "ThrottlingException"
      case .validation: "ValidationException"
      case .other(let name): name
      }
    }
  }
}

extension BedrockRuntimeError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .missingCredentials:
      "Missing AWS credentials. Provide either a Bedrock API key or an access key ID and secret access key."
    case .invalidURL(let url):
      "Invalid Bedrock URL: \(url)"
    case .httpError(let statusCode, let kind, let message):
      "Bedrock HTTP error \(statusCode) (\(kind.name)): \(message)"
    case .invalidResponse(let message):
      "Bedrock invalid response: \(message)"
    }
  }
}

/// Error body Bedrock returns: `{ "message": "…" }`, sometimes with a `__type`
/// naming the exception. Some fronting layers capitalize `Message`.
struct BedrockErrorEnvelope: Decodable {
  var message: String?
  var type: String?

  private enum CodingKeys: String, CodingKey {
    case message
    case capitalizedMessage = "Message"
    case type = "__type"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    message =
      try c.decodeIfPresent(String.self, forKey: .message)
      ?? c.decodeIfPresent(String.self, forKey: .capitalizedMessage)
    type = try c.decodeIfPresent(String.self, forKey: .type)
  }
}
