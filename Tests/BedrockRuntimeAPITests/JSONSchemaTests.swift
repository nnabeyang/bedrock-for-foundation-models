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

  @Test("keeps the validation keywords that constrain generated arguments")
  func keepsValidationKeywords() {
    // Everything here is what `@Guide` puts in the schema: `.range(1...10)`
    // becomes minimum/maximum, `.count(_:)` becomes minItems/maxItems, and so
    // on. None of it may be dropped, or the constraint never reaches the model.
    let schema: JSONValue = [
      "type": "object",
      "properties": [
        "count": ["type": "integer", "minimum": 1, "maximum": 10],
        "tags": ["type": "array", "minItems": 2, "maxItems": 3, "items": ["type": "string"]],
        "code": ["type": "string", "pattern": "^[A-Z]{3}$", "minLength": 3, "maxLength": 3],
        "ratio": [
          "type": "number", "exclusiveMinimum": 0, "exclusiveMaximum": 1, "multipleOf": 0.25,
        ],
      ],
      "required": ["count"],
    ]

    #expect(JSONSchema.sanitized(schema) == schema)
  }

  @Test("leaves scalars untouched")
  func leavesScalarsUntouched() {
    #expect(JSONSchema.sanitized("string") == "string")
    #expect(JSONSchema.sanitized(42) == 42)
    #expect(JSONSchema.sanitized(nil) == .null)
  }
}
