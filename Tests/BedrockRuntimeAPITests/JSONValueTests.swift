import Foundation
import Testing

@testable import BedrockRuntimeAPI

@Suite("JSONValue")
struct JSONValueTests {
  @Test("round-trips every JSON kind")
  func roundTripsEveryKind() throws {
    let value: JSONValue = [
      "null": nil,
      "bool": true,
      "number": 1.5,
      "int": 42,
      "string": "hi",
      "array": [1, "two", false],
      "object": ["nested": true],
    ]

    let data = try JSONEncoder().encode(value)
    #expect(try JSONDecoder().decode(JSONValue.self, from: data) == value)
  }

  @Test("keeps booleans out of the number case")
  func keepsBooleansDistinct() throws {
    let decoded = try #require(JSONValue.parsed(#"{"a":true,"b":1}"#))
    #expect(decoded["a"] == .bool(true))
    #expect(decoded["b"] == .number(1))
  }

  @Test("writes integral numbers without a fractional part")
  func writesIntegralNumbersPlainly() {
    #expect(JSONValue.object(["n": 42]).jsonText == #"{"n":42}"#)
  }

  @Test("sorts object keys in jsonText")
  func sortsKeys() {
    let value: JSONValue = ["b": 1, "a": 2]
    #expect(value.jsonText == #"{"a":2,"b":1}"#)
  }

  @Test("subscript reads object fields only")
  func subscriptReadsObjectFields() {
    let object: JSONValue = ["a": 1]
    #expect(object["a"] == .number(1))
    #expect(object["missing"] == nil)
    #expect(JSONValue.string("x")["a"] == nil)
  }
}
