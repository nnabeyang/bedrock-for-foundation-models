import Foundation

/// JSON Schema handling for `toolSpec.inputSchema.json`.
public enum JSONSchema {
  /// Keys Converse's schema validator accepts. Everything else is dropped —
  /// sending an unknown key is a hard 400.
  ///
  /// `additionalProperties` is deliberately absent: unlike the Messages API,
  /// Converse rejects it.
  private static let allowedKeys: Set<String> = [
    "type", "properties", "required", "items", "enum", "const",
    "anyOf", "allOf", "oneOf", "$ref", "$defs", "definitions",
    "description", "format",
  ]

  /// Keys whose values are `{name: schema}` maps — the names are arbitrary and
  /// must be preserved; only the nested schemas are sanitized.
  private static let mapValuedKeys: Set<String> = ["properties", "$defs", "definitions"]

  /// Strips the schema keys Bedrock rejects (`additionalProperties`, `title`,
  /// `x-order` and the like), recursively.
  public static func sanitized(_ value: JSONValue) -> JSONValue {
    switch value {
    case .object(let fields):
      var out: [String: JSONValue] = [:]
      for (key, nested) in fields where allowedKeys.contains(key) {
        if mapValuedKeys.contains(key), case .object(let members) = nested {
          out[key] = .object(members.mapValues(sanitized))
        } else {
          out[key] = sanitized(nested)
        }
      }
      return .object(out)
    case .array(let elements):
      return .array(elements.map(sanitized))
    case .null, .bool, .number, .string:
      return value
    }
  }
}
