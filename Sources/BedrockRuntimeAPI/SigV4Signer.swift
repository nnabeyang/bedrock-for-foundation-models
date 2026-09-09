import CommonCrypto
import Foundation

/// Signs a request with AWS Signature Version 4.
///
/// The signing date is a parameter rather than read from the clock inside, so
/// a signature can be reproduced exactly in a test.
public struct SigV4Signer: Sendable {
  public struct Credentials: Hashable, Sendable {
    public var accessKeyId: String
    public var secretKey: String
    public var sessionToken: String?

    public init(accessKeyId: String, secretKey: String, sessionToken: String? = nil) {
      self.accessKeyId = accessKeyId
      self.secretKey = secretKey
      self.sessionToken = sessionToken
    }
  }

  public let credentials: Credentials
  public let region: String
  public let service: String

  public init(credentials: Credentials, region: String, service: String = "bedrock") {
    self.credentials = credentials
    self.region = region
    self.service = service
  }

  /// Every header the signed request needs, `Authorization` included. The
  /// caller must send exactly these alongside `content-type`, since they are
  /// what the signature covers.
  public func headers(
    method: String,
    path: String,
    host: String,
    contentType: String = "application/json",
    body: Data,
    date: Date
  ) -> [String: String] {
    let amzDate = Self.amzDate(from: date)
    let dateStamp = String(amzDate.prefix(8))

    // Canonical headers are sorted by name; these four already are.
    var canonicalHeaders = "content-type:\(contentType)\nhost:\(host)\nx-amz-date:\(amzDate)\n"
    var signedHeaderNames = ["content-type", "host", "x-amz-date"]
    if let sessionToken = credentials.sessionToken {
      canonicalHeaders += "x-amz-security-token:\(sessionToken)\n"
      signedHeaderNames.append("x-amz-security-token")
    }
    let signedHeaders = signedHeaderNames.joined(separator: ";")

    let canonicalRequest = [
      method, path, "", canonicalHeaders, signedHeaders, Self.sha256Hex(body),
    ].joined(separator: "\n")

    let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
    let stringToSign = [
      "AWS4-HMAC-SHA256", amzDate, credentialScope,
      Self.sha256Hex(Data(canonicalRequest.utf8)),
    ].joined(separator: "\n")

    let signingKey = deriveSigningKey(dateStamp: dateStamp)
    let signature = Self.hmacSHA256Hex(key: signingKey, data: Data(stringToSign.utf8))

    var headers = [
      "host": host,
      "x-amz-date": amzDate,
      "Authorization": """
      AWS4-HMAC-SHA256 Credential=\(credentials.accessKeyId)/\(credentialScope), \
      SignedHeaders=\(signedHeaders), Signature=\(signature)
      """,
    ]
    if let sessionToken = credentials.sessionToken {
      headers["x-amz-security-token"] = sessionToken
    }
    return headers
  }

  // MARK: - Private

  /// `YYYYMMDD'T'HHMMSS'Z'` in UTC, the only format SigV4 accepts.
  static func amzDate(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    return formatter.string(from: date)
  }

  private func deriveSigningKey(dateStamp: String) -> Data {
    let kDate = Self.hmacSHA256(
      key: Data("AWS4\(credentials.secretKey)".utf8), data: Data(dateStamp.utf8))
    let kRegion = Self.hmacSHA256(key: kDate, data: Data(region.utf8))
    let kService = Self.hmacSHA256(key: kRegion, data: Data(service.utf8))
    return Self.hmacSHA256(key: kService, data: Data("aws4_request".utf8))
  }

  private static func hmacSHA256(key: Data, data: Data) -> Data {
    var result = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
    key.withUnsafeBytes { keyBytes in
      data.withUnsafeBytes { dataBytes in
        result.withUnsafeMutableBytes { resultBytes in
          CCHmac(
            CCHmacAlgorithm(kCCHmacAlgSHA256),
            keyBytes.baseAddress, key.count,
            dataBytes.baseAddress, data.count,
            resultBytes.baseAddress)
        }
      }
    }
    return result
  }

  private static func hmacSHA256Hex(key: Data, data: Data) -> String {
    hmacSHA256(key: key, data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func sha256Hex(_ data: Data) -> String {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
    return hash.map { String(format: "%02x", $0) }.joined()
  }
}
