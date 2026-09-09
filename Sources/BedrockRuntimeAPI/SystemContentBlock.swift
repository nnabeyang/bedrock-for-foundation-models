import Foundation

/// One block of the system prompt. Bedrock also accepts `guardContent` and
/// `cachePoint` here; those decode as ``other``.
public enum SystemContentBlock: Sendable, Hashable, Codable {
  case text(String)
  case other(JSONValue)

  private enum CodingKeys: String, CodingKey {
    case text
  }

  public init(from decoder: Decoder) throws {
    guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
      self = .other(try JSONValue(from: decoder))
      return
    }
    if let text = try c.decodeIfPresent(String.self, forKey: .text) {
      self = .text(text)
    } else {
      self = .other(try JSONValue(from: decoder))
    }
  }

  public func encode(to encoder: Encoder) throws {
    if case .other(let value) = self {
      try value.encode(to: encoder)
      return
    }
    var c = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .text(let text): try c.encode(text, forKey: .text)
    case .other: break
    }
  }
}
