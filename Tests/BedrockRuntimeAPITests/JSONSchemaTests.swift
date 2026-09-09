import Foundation
import Testing

@testable import BedrockRuntimeAPI

@Suite("JSONSchema.sanitized")
struct JSONSchemaTests {
  @Test("drops the keys Bedrock rejects and keeps the rest")
  func dropsRejectedKeys() {
    let schema: JSONValue = [
      "type": "object",
      "description": "A tool input",
      "required": ["city"],
      "additionalProperties": false,
      "title": "WeatherInput",
      "x-order": 1,
    ]

    #expect(
      JSONSchema.sanitized(schema) == [
        "type": "object",
        "description": "A tool input",
        "required": ["city"],
      ])
  }

  @Test("recurses into properties without treating property names as schema keys")
  func recursesIntoProperties() {
    let schema: JSONValue = [
      "type": "object",
      "properties": [
        // A property literally named "title" must survive as a property name.
        "title": ["type": "string", "title": "Title", "x-order": 0],
        "count": ["type": "integer", "additionalProperties": false],
      ],
    ]

    #expect(
      JSONSchema.sanitized(schema) == [
        "type": "object",
        "properties": [
          "title": ["type": "string"],
          "count": ["type": "integer"],
        ],
      ])
  }

  @Test("recurses into items, $defs and composition keywords")
  func recursesIntoNestedSchemas() {
    let schema: JSONValue = [
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

    #expect(
      JSONSchema.sanitized(schema) == [
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
      ])
  }

  @Test("leaves scalars untouched")
  func leavesScalarsUntouched() {
    #expect(JSONSchema.sanitized("string") == "string")
    #expect(JSONSchema.sanitized(42) == 42)
    #expect(JSONSchema.sanitized(nil) == .null)
  }
}
