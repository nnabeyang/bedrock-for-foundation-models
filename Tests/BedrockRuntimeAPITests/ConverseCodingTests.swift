import Foundation
import Testing

@testable import BedrockRuntimeAPI

/// Encodes a value with sorted keys, so the wire form can be compared as text.
private func json(_ value: some Encodable) throws -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  return String(decoding: try encoder.encode(value), as: UTF8.self)
}

@Suite("ConverseContentBlock coding")
struct ConverseContentBlockCodingTests {
  @Test("encodes a text block as a single-key object")
  func encodesText() throws {
    #expect(try json(ConverseContentBlock.text("hi")) == #"{"text":"hi"}"#)
  }

  @Test("round-trips a toolUse block")
  func roundTripsToolUse() throws {
    let payload = #"{"toolUse":{"input":{"city":"SF"},"name":"get_weather","toolUseId":"tu_1"}}"#
    let block = try JSONDecoder().decode(ConverseContentBlock.self, from: Data(payload.utf8))
    guard case .toolUse(let toolUse) = block else {
      Issue.record("wrong case")
      return
    }
    #expect(toolUse.toolUseId == "tu_1")
    #expect(toolUse.name == "get_weather")
    #expect(toolUse.input == .object(["city": .string("SF")]))
    #expect(try json(block) == payload)
  }

  @Test("round-trips a toolResult block")
  func roundTripsToolResult() throws {
    let payload =
      #"{"toolResult":{"content":[{"text":"sunny"}],"status":"success","toolUseId":"tu_1"}}"#
    let block = try JSONDecoder().decode(ConverseContentBlock.self, from: Data(payload.utf8))
    guard case .toolResult(let result) = block else {
      Issue.record("wrong case")
      return
    }
    #expect(result.toolUseId == "tu_1")
    #expect(result.content == [.text("sunny")])
    #expect(result.status == .success)
    #expect(try json(block) == payload)
  }

  @Test("round-trips a reasoningContent block, keeping the signature a string")
  func roundTripsReasoning() throws {
    let payload = #"{"reasoningContent":{"reasoningText":{"signature":"c2ln","text":"think"}}}"#
    let block = try JSONDecoder().decode(ConverseContentBlock.self, from: Data(payload.utf8))
    guard case .reasoningContent(.reasoningText(let reasoning)) = block else {
      Issue.record("wrong case")
      return
    }
    #expect(reasoning.text == "think")
    #expect(reasoning.signature == "c2ln")
    #expect(try json(block) == payload)
  }

  @Test("decodes redactedContent as base64 bytes")
  func decodesRedactedContent() throws {
    let payload = #"{"reasoningContent":{"redactedContent":"AQID"}}"#
    let block = try JSONDecoder().decode(ConverseContentBlock.self, from: Data(payload.utf8))
    guard case .reasoningContent(.redactedContent(let data)) = block else {
      Issue.record("wrong case")
      return
    }
    #expect(Array(data) == [1, 2, 3])
    #expect(try json(block) == payload)
  }

  @Test("keeps an unmodelled block verbatim")
  func keepsUnknownBlockVerbatim() throws {
    let payload = #"{"cachePoint":{"type":"default"}}"#
    let block = try JSONDecoder().decode(ConverseContentBlock.self, from: Data(payload.utf8))
    guard case .other = block else {
      Issue.record("expected .other")
      return
    }
    #expect(try json(block) == payload)
  }

  @Test("keeps an image block verbatim rather than failing")
  func keepsImageBlockVerbatim() throws {
    let payload = #"{"image":{"format":"png","source":{"bytes":"AQID"}}}"#
    let block = try JSONDecoder().decode(ConverseContentBlock.self, from: Data(payload.utf8))
    #expect(try json(block) == payload)
  }
}

@Suite("Converse request coding")
struct ConverseRequestCodingTests {
  @Test("omits the fields it wasn't given")
  func omitsAbsentFields() throws {
    let request = ConverseRequest(messages: [.user("hi")])
    #expect(try json(request) == #"{"messages":[{"content":[{"text":"hi"}],"role":"user"}]}"#)
  }

  @Test("encodes a full request")
  func encodesFullRequest() throws {
    let request = ConverseRequest(
      messages: [.user("hi")],
      system: [.text("Be terse.")],
      inferenceConfig: .init(maxTokens: 1024),
      toolConfig: .init(
        tools: [
          .toolSpec(
            .init(
              name: "echo",
              description: "Echoes input",
              inputSchema: .json(["type": "object"])
            )
          )
        ],
        toolChoice: .auto
      )
    )

    #expect(
      try json(request) == """
        {"inferenceConfig":{"maxTokens":1024},\
        "messages":[{"content":[{"text":"hi"}],"role":"user"}],\
        "system":[{"text":"Be terse."}],\
        "toolConfig":{"toolChoice":{"auto":{}},\
        "tools":[{"toolSpec":{"description":"Echoes input",\
        "inputSchema":{"json":{"type":"object"}},"name":"echo"}}]}}
        """)
  }

  @Test("writes an empty object for the toolChoice variants that carry no fields")
  func writesEmptyObjectToolChoices() throws {
    #expect(try json(ToolChoice.auto) == #"{"auto":{}}"#)
    #expect(try json(ToolChoice.any) == #"{"any":{}}"#)
    #expect(try json(ToolChoice.tool(name: "echo")) == #"{"tool":{"name":"echo"}}"#)
  }

  @Test("round-trips every toolChoice variant")
  func roundTripsToolChoice() throws {
    for choice in [ToolChoice.auto, .any, .tool(name: "echo")] {
      let data = try JSONEncoder().encode(choice)
      #expect(try JSONDecoder().decode(ToolChoice.self, from: data) == choice)
    }
  }
}

@Suite("Converse response coding")
struct ConverseResponseCodingTests {
  @Test("decodes a text response with usage and metrics")
  func decodesTextResponse() throws {
    let payload = """
      {"output":{"message":{"role":"assistant","content":[{"text":"hello"}]}},
       "stopReason":"end_turn",
       "usage":{"inputTokens":10,"outputTokens":3,"totalTokens":13,"cacheReadInputTokens":4},
       "metrics":{"latencyMs":120}}
      """
    let response = try JSONDecoder().decode(ConverseResponse.self, from: Data(payload.utf8))

    #expect(response.output.message?.content == [.text("hello")])
    #expect(response.output.message?.role == .assistant)
    #expect(response.stopReason == .endTurn)
    #expect(response.usage?.inputTokens == 10)
    #expect(response.usage?.outputTokens == 3)
    #expect(response.usage?.cacheReadInputTokens == 4)
    #expect(response.metrics?.latencyMs == 120)
  }

  @Test("reads an unrecognized stop reason as unknown")
  func readsUnknownStopReason() throws {
    let payload = #"{"output":{"message":{"role":"assistant","content":[]}},"stopReason":"nope"}"#
    let response = try JSONDecoder().decode(ConverseResponse.self, from: Data(payload.utf8))
    #expect(response.stopReason == .unknown)
  }

  @Test("treats a missing token count as zero")
  func treatsMissingCountsAsZero() throws {
    let usage = try JSONDecoder().decode(TokenUsage.self, from: Data(#"{"outputTokens":5}"#.utf8))
    #expect(usage.inputTokens == 0)
    #expect(usage.outputTokens == 5)
    #expect(usage.totalTokens == nil)
  }
}
