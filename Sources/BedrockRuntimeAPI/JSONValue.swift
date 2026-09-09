import Foundation

/// Loosely-typed JSON, for the parts of the Converse payload whose shape the
/// API does not fix: tool inputs, tool results and JSON Schemas.
public enum JSONValue: Sendable, Hashable, Codable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  public init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
      return
    }
    // Bool is probed before Double: decoding `true` as a number would succeed
    // on some platforms and collapse it to 1.
    if let v = try? c.decode(Bool.self) {
      self = .bool(v)
      return
    }
    if let v = try? c.decode(Double.self) {
      self = .number(v)
      return
    }
    if let v = try? c.decode(String.self) {
      self = .string(v)
      return
    }
    if let v = try? c.decode([JSONValue].self) {
      self = .array(v)
      return
    }
    if let v = try? c.decode([String: JSONValue].self) {
      self = .object(v)
      return
    }
    throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .null: try c.encodeNil()
    case .bool(let v): try c.encode(v)
    case .number(let v): try c.encode(v)
    case .string(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    case .object(let v): try c.encode(v)
    }
  }
}

extension JSONValue {
  /// The named field of an object; `nil` for a missing field or a non-object.
  public subscript(field: String) -> JSONValue? {
    if case .object(let fields) = self { fields[field] } else { nil }
  }

  /// Decodes the value into a `Decodable` type by round-tripping through
  /// `Data` — payload shapes are small, so clarity wins over speed.
  public func decoded<Value: Decodable>() -> Value? {
    guard let data = try? JSONEncoder().encode(self) else { return nil }
    return try? JSONDecoder().decode(Value.self, from: data)
  }

  public static func encoded(_ value: some Encodable) -> JSONValue? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return try? JSONDecoder().decode(JSONValue.self, from: data)
  }

  public static func parsed(_ json: String) -> JSONValue? {
    try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
  }

  /// Compact JSON text with object keys sorted, so equal values always produce
  /// equal text. Integral numbers are written without a fractional part.
  public var jsonText: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    // Encoding a JSONValue cannot fail: every case maps to a JSON value.
    return String(decoding: try! encoder.encode(self), as: UTF8.self)
  }
}

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral,
  ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
  ExpressibleByStringLiteral, ExpressibleByArrayLiteral,
  ExpressibleByDictionaryLiteral
{
  public init(nilLiteral: ()) { self = .null }
  public init(booleanLiteral value: Bool) { self = .bool(value) }
  public init(integerLiteral value: Int) { self = .number(Double(value)) }
  public init(floatLiteral value: Double) { self = .number(value) }
  public init(stringLiteral value: String) { self = .string(value) }
  public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
  public init(dictionaryLiteral elements: (String, JSONValue)...) {
    self = .object(.init(uniqueKeysWithValues: elements))
  }
}
