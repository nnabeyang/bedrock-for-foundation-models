import BedrockRuntimeAPI
import Foundation
import FoundationModels

@available(anyAppleOS 27, *)
extension JSONValue {
  /// The framework value as JSON, structurally; a kind this package doesn't
  /// know reads as `null`.
  init(_ content: GeneratedContent) {
    switch content.kind {
    case .null: self = .null
    case .bool(let value): self = .bool(value)
    case .number(let value): self = .number(value)
    case .string(let value): self = .string(value)
    case .array(let values): self = .array(values.map(JSONValue.init))
    case .structure(let properties, _): self = .object(properties.mapValues(JSONValue.init))
    @unknown default: self = .null
    }
  }

  /// A tool's parameters as the JSON Schema Bedrock accepts.
  ///
  /// `GenerationSchema` is `Codable` and encodes as JSON Schema, but with
  /// framework-specific keys (`x-order`, `title`) Converse's validator rejects,
  /// so the result is sanitized before it goes out.
  static func schema(_ schema: GenerationSchema) -> JSONValue {
    guard let value = JSONValue.encoded(schema) else { return ["type": "object"] }
    return JSONSchema.sanitized(value)
  }
}
