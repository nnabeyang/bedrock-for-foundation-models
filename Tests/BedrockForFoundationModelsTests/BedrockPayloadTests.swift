import Foundation
import Testing

@testable import BedrockForFoundationModels

/// Compares two JSON-compatible values by their canonical serialization, since
/// `[String: Any]` is not `Equatable`.
private func expectJSONEqual(
  _ actual: Any, _ expected: Any,
  sourceLocation: SourceLocation = #_sourceLocation
) throws {
  let options: JSONSerialization.WritingOptions = [.sortedKeys, .fragmentsAllowed]
  let actualData = try JSONSerialization.data(withJSONObject: actual, options: options)
  let expectedData = try JSONSerialization.data(withJSONObject: expected, options: options)
  #expect(
    String(decoding: actualData, as: UTF8.self) == String(decoding: expectedData, as: UTF8.self),
    sourceLocation: sourceLocation
  )
}

@Suite("sanitizeSchema")
struct SanitizeSchemaTests {
  @Test("drops the keys Bedrock rejects and keeps the rest")
  func dropsRejectedKeys() throws {
    let schema: [String: Any] = [
      "type": "object",
      "description": "A tool input",
      "required": ["city"],
      "additionalProperties": false,
      "title": "WeatherInput",
      "x-order": 1,
    ]

    let sanitized = BedrockPayload.sanitizeSchema(schema)

    try expectJSONEqual(
      sanitized,
      [
        "type": "object",
        "description": "A tool input",
        "required": ["city"],
      ] as [String: Any])
  }

  @Test("recurses into properties without treating property names as schema keys")
  func recursesIntoProperties() throws {
    let schema: [String: Any] = [
      "type": "object",
      "properties": [
        // A property literally named "title" must survive as a property name.
        "title": ["type": "string", "title": "Title", "x-order": 0],
        "count": ["type": "integer", "additionalProperties": false],
      ],
    ]

    let sanitized = BedrockPayload.sanitizeSchema(schema)

    try expectJSONEqual(
      sanitized,
      [
        "type": "object",
        "properties": [
          "title": ["type": "string"],
          "count": ["type": "integer"],
        ],
      ] as [String: Any])
  }

  @Test("recurses into items, $defs and composition keywords")
  func recursesIntoNestedSchemas() throws {
    let schema: [String: Any] = [
      "type": "array",
      "items": ["$ref": "#/$defs/Point", "title": "Item"],
      "$defs": [
        "Point": [
          "type": "object",
          "additionalProperties": false,
          "anyOf": [
            ["type": "null", "x-order": 3],
            ["type": "string"],
          ],
        ]
      ],
    ]

    let sanitized = BedrockPayload.sanitizeSchema(schema)

    try expectJSONEqual(
      sanitized,
      [
        "type": "array",
        "items": ["$ref": "#/$defs/Point"],
        "$defs": [
          "Point": [
            "type": "object",
            "anyOf": [
              ["type": "null"],
              ["type": "string"],
            ],
          ]
        ],
      ] as [String: Any])
  }

  @Test("leaves scalars untouched")
  func leavesScalarsUntouched() throws {
    try expectJSONEqual(BedrockPayload.sanitizeSchema("string"), "string")
    try expectJSONEqual(BedrockPayload.sanitizeSchema(42), 42)
  }
}

@Suite("mergeConsecutiveSameRole")
struct MergeConsecutiveSameRoleTests {
  @Test("merges the content of adjacent messages sharing a role")
  func mergesAdjacentSameRole() throws {
    let messages: [[String: Any]] = [
      ["role": "user", "content": [["text": "a"]]],
      ["role": "user", "content": [["text": "b"]]],
      ["role": "assistant", "content": [["text": "c"]]],
    ]

    let merged = BedrockPayload.mergeConsecutiveSameRole(messages)

    try expectJSONEqual(
      merged,
      [
        ["role": "user", "content": [["text": "a"], ["text": "b"]]],
        ["role": "assistant", "content": [["text": "c"]]],
      ])
  }

  @Test("keeps messages separate when the roles alternate")
  func keepsAlternatingRolesSeparate() throws {
    let messages: [[String: Any]] = [
      ["role": "user", "content": [["text": "a"]]],
      ["role": "assistant", "content": [["text": "b"]]],
      ["role": "user", "content": [["text": "c"]]],
    ]

    let merged = BedrockPayload.mergeConsecutiveSameRole(messages)

    #expect(merged.count == 3)
    try expectJSONEqual(merged, messages)
  }

  @Test("passes malformed entries through untouched")
  func passesMalformedEntriesThrough() throws {
    let messages: [[String: Any]] = [
      ["role": "user", "content": [["text": "a"]]],
      ["content": [["text": "no role"]]],
      ["role": "user", "content": [["text": "b"]]],
    ]

    let merged = BedrockPayload.mergeConsecutiveSameRole(messages)

    // The entry without a role breaks the run, so the two user messages stay apart.
    #expect(merged.count == 3)
    try expectJSONEqual(merged, messages)
  }

  @Test("returns an empty array unchanged")
  func handlesEmptyInput() {
    #expect(BedrockPayload.mergeConsecutiveSameRole([]).isEmpty)
  }
}
