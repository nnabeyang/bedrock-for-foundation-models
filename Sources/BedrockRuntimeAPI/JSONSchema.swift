import Foundation

/// JSON Schema handling for `toolSpec.inputSchema.json`.
public enum JSONSchema {
  /// Keys Converse's schema validator rejects. Everything else goes through.
  ///
  /// The list is a denylist rather than an allowlist because the validation
  /// keywords a tool's schema carries — `minimum`, `maxItems`, `pattern` and
  /// the rest — are what constrain the arguments the model generates. Passing
  /// only a known-good set silently drops every one of them, so a tool that
  /// asks for a value in `1...10` receives any integer.
  ///
  /// `additionalProperties` is denied because, unlike the Messages API,
  /// Converse rejects it. `title` / `x-order` / `order` / `$schema` are the
  /// generator's own bookkeeping and carry no meaning for the model.
  private static let deniedKeys: Set<String> = [
    "additionalProperties", "title", "x-order", "order", "$schema",
  ]

  /// Keys whose values are `{name: schema}` maps — the names are arbitrary and
  /// must be preserved; only the nested schemas are sanitized.
  private static let mapValuedKeys: Set<String> = ["properties", "$defs", "definitions"]

  /// Strips the schema keys Bedrock rejects, recursively.
  public static func sanitized(_ value: JSONValue) -> JSONValue {
    switch value {
    case .object(let fields):
      var out: [String: JSONValue] = [:]
      for (key, nested) in fields where !deniedKeys.contains(key) {
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
