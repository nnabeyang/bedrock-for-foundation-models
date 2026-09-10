import Foundation
import FoundationModels
import Testing

@testable import BedrockForFoundationModels
@testable import BedrockRuntimeAPI

// `ConverseRequestBuilder` is gated `@available(anyAppleOS 27, *)`; the tests
// carry the same gate. swift-testing's `@Test` / `@Suite` macros expand fine
// under it on this toolchain.

@available(anyAppleOS 27, *)
private func buildRequest(
  _ entries: [Transcript.Entry],
  options: GenerationOptions = GenerationOptions(toolCallingMode: nil),
  tools: [Transcript.ToolDefinition] = []
) -> ConverseRequest {
  buildFullRequest(entries, options: options, tools: tools).request
}

@available(anyAppleOS 27, *)
private func buildFullRequest(
  _ entries: [Transcript.Entry],
  options: GenerationOptions = GenerationOptions(toolCallingMode: nil),
  tools: [Transcript.ToolDefinition] = [],
  schema: GenerationSchema? = nil
) -> BuiltConverseRequest {
  ConverseRequestBuilder.build(
    from: LanguageModelExecutorGenerationRequest(
      id: UUID(),
      transcript: Transcript(entries: entries),
      enabledTools: tools,
      schema: schema,
      generationOptions: options,
      contextOptions: ContextOptions(),
      metadata: [:]
    )
  )
}

@available(anyAppleOS 27, *)
@Generable
private struct WeatherInput {
  @Guide(description: "The city to look up.")
  var city: String
}

@available(anyAppleOS 27, *)
private func weatherTool() -> Transcript.ToolDefinition {
  Transcript.ToolDefinition(
    name: "get_weather",
    description: "Looks up the weather in a city.",
    parameters: WeatherInput.generationSchema
  )
}

@available(anyAppleOS 27, *)
private func textSegments(_ text: String) -> [Transcript.Segment] {
  [.text(Transcript.TextSegment(content: text))]
}

@Suite("ConverseRequestBuilder tool round-trip")
struct ConverseRequestBuilderToolTests {
  @available(anyAppleOS 27, *)
  @Test("replays a tool call with its arguments intact, not collapsed to {}")
  func replaysToolCallArguments() throws {
    let args = try GeneratedContent(json: #"{"path":"./README.md"}"#)
    let entries: [Transcript.Entry] = [
      .toolCalls(
        Transcript.ToolCalls([
          Transcript.ToolCall(id: "tu_1", toolName: "read_file", arguments: args)
        ])),
      .toolOutput(
        Transcript.ToolOutput(
          id: "tu_1", toolName: "read_file", segments: textSegments("# eich\n\nA REPL."))),
    ]

    let body = buildRequest(entries)

    #expect(body.messages.count == 2)
    #expect(body.messages[0].role == .assistant)
    guard case .toolUse(let toolUse) = body.messages[0].content.first else {
      Issue.record("expected a toolUse block, got \(body.messages[0].content)")
      return
    }
    #expect(toolUse.toolUseId == "tu_1")
    #expect(toolUse.name == "read_file")
    #expect(toolUse.input == .object(["path": .string("./README.md")]))

    #expect(body.messages[1].role == .user)
    guard case .toolResult(let result) = body.messages[1].content.first else {
      Issue.record("expected a toolResult block, got \(body.messages[1].content)")
      return
    }
    #expect(result.toolUseId == "tu_1")
    #expect(result.content == [.text("# eich\n\nA REPL.")])
  }

  @available(anyAppleOS 27, *)
  @Test("substitutes (no output) for an empty tool result")
  func emptyToolOutput() {
    let entries: [Transcript.Entry] = [
      .toolOutput(Transcript.ToolOutput(id: "tu_1", toolName: "x", segments: textSegments("")))
    ]
    let body = buildRequest(entries)
    guard case .toolResult(let result) = body.messages.first?.content.first else {
      Issue.record("expected a toolResult block")
      return
    }
    #expect(result.content == [.text("(no output)")])
  }
}

@Suite("ConverseRequestBuilder reasoning replay")
struct ConverseRequestBuilderReasoningTests {
  @available(anyAppleOS 27, *)
  @Test("drops a reasoning entry that carries no signature")
  func dropsUnsignedReasoning() {
    let entries: [Transcript.Entry] = [
      .reasoning(Transcript.Reasoning(segments: textSegments("half a thought"), signature: nil)),
      .response(Transcript.Response(assetIDs: [], segments: textSegments("answer"))),
    ]
    let body = buildRequest(entries)
    // Only the response survives.
    #expect(body.messages.count == 1)
    #expect(body.messages[0].content == [.text("answer")])
  }

  @available(anyAppleOS 27, *)
  @Test("replays a signed reasoning entry as reasoningText with the signature")
  func replaysSignedReasoning() {
    let sig = Data([1, 2, 3])
    let entries: [Transcript.Entry] = [
      .reasoning(Transcript.Reasoning(segments: textSegments("a thought"), signature: sig))
    ]
    let body = buildRequest(entries)
    guard case .reasoningContent(.reasoningText(let reasoning)) = body.messages.first?.content.first
    else {
      Issue.record("expected a reasoningText block, got \(String(describing: body.messages.first))")
      return
    }
    #expect(reasoning.text == "a thought")
    #expect(reasoning.signature == sig.base64EncodedString())
  }

  @available(anyAppleOS 27, *)
  @Test("replays a redacted-flagged reasoning entry as redactedContent")
  func replaysRedactedReasoning() {
    let sig = Data([9, 9, 9])
    let entries: [Transcript.Entry] = [
      .reasoning(
        Transcript.Reasoning(
          metadata: [redactedReasoningMetadataKey: true],
          segments: [],
          signature: sig
        ))
    ]
    let body = buildRequest(entries)
    guard case .reasoningContent(.redactedContent(let data)) = body.messages.first?.content.first
    else {
      Issue.record("expected a redactedContent block, got \(String(describing: body.messages.first))")
      return
    }
    #expect(data == sig)
  }
}

@Suite("ConverseRequestBuilder inference parameters")
struct ConverseRequestBuilderInferenceTests {
  @available(anyAppleOS 27, *)
  private static func prompt() -> [Transcript.Entry] {
    [.prompt(Transcript.Prompt(segments: textSegments("hi")))]
  }

  @available(anyAppleOS 27, *)
  @Test("sends no inferenceConfig when the caller named no parameters")
  func omitsEmptyInferenceConfig() {
    let body = buildRequest(Self.prompt())

    #expect(body.inferenceConfig == nil)
    #expect(body.additionalModelRequestFields == nil)
  }

  @available(anyAppleOS 27, *)
  @Test("carries the response token limit")
  func sendsMaximumResponseTokens() {
    let body = buildRequest(
      Self.prompt(),
      options: GenerationOptions(
        samplingMode: nil, temperature: nil, maximumResponseTokens: 512, toolCallingMode: nil))

    #expect(body.inferenceConfig == InferenceConfiguration(maxTokens: 512))
  }

  @available(anyAppleOS 27, *)
  @Test("expresses greedy sampling as temperature 0")
  func sendsGreedyAsZeroTemperature() {
    let body = buildRequest(
      Self.prompt(),
      options: GenerationOptions(
        samplingMode: .greedy, temperature: nil, maximumResponseTokens: nil, toolCallingMode: nil))

    #expect(body.inferenceConfig == InferenceConfiguration(temperature: 0))
  }

  @available(anyAppleOS 27, *)
  @Test("lets an explicit temperature override the one greedy implies")
  func explicitTemperatureWinsOverGreedy() {
    let body = buildRequest(
      Self.prompt(),
      options: GenerationOptions(
        samplingMode: .greedy, temperature: 0.7, maximumResponseTokens: nil, toolCallingMode: nil))

    #expect(body.inferenceConfig == InferenceConfiguration(temperature: 0.7))
  }

  @available(anyAppleOS 27, *)
  @Test("maps a probability threshold onto topP")
  func sendsProbabilityThresholdAsTopP() {
    let body = buildRequest(
      Self.prompt(),
      options: GenerationOptions(
        samplingMode: .random(probabilityThreshold: 0.9),
        temperature: nil,
        maximumResponseTokens: nil,
        toolCallingMode: nil))

    #expect(body.inferenceConfig == InferenceConfiguration(topP: 0.9))
  }

  @available(anyAppleOS 27, *)
  @Test("passes top-k through the model-specific fields, not inferenceConfig")
  func sendsTopKThroughAdditionalFields() {
    let body = buildRequest(
      Self.prompt(),
      options: GenerationOptions(
        samplingMode: .random(top: 40),
        temperature: nil,
        maximumResponseTokens: nil,
        toolCallingMode: nil))

    #expect(body.inferenceConfig == nil)
    #expect(body.additionalModelRequestFields == ["top_k": 40])
  }
}

@Suite("ConverseRequestBuilder tool choice")
struct ConverseRequestBuilderToolChoiceTests {
  @available(anyAppleOS 27, *)
  private static func prompt() -> [Transcript.Entry] {
    [.prompt(Transcript.Prompt(segments: textSegments("what is the weather?")))]
  }

  @available(anyAppleOS 27, *)
  private static func promptWithToolRoundTrip() -> [Transcript.Entry] {
    prompt() + [
      .toolCalls(
        Transcript.ToolCalls([
          Transcript.ToolCall(
            id: "tu_1", toolName: "get_weather", arguments: GeneratedContent(kind: .null))
        ])),
      .toolOutput(
        Transcript.ToolOutput(id: "tu_1", toolName: "get_weather", segments: textSegments("sunny"))),
    ]
  }

  @available(anyAppleOS 27, *)
  private static func options(
    _ mode: GenerationOptions.ToolCallingMode?
  ) -> GenerationOptions {
    GenerationOptions(
      samplingMode: nil, temperature: nil, maximumResponseTokens: nil, toolCallingMode: mode)
  }

  @available(anyAppleOS 27, *)
  @Test("sends no toolConfig when there are no tools")
  func omitsToolConfigWithoutTools() {
    #expect(buildRequest(Self.prompt()).toolConfig == nil)
  }

  @available(anyAppleOS 27, *)
  @Test("leaves the choice to the model when the caller named no mode")
  func omitsToolChoiceWithoutMode() {
    let body = buildRequest(Self.prompt(), options: Self.options(nil), tools: [weatherTool()])

    #expect(body.toolConfig?.tools.count == 1)
    #expect(body.toolConfig?.toolChoice == nil)
  }

  @available(anyAppleOS 27, *)
  @Test("writes allowed as auto")
  func sendsAllowedAsAuto() {
    let body = buildRequest(Self.prompt(), options: Self.options(.allowed), tools: [weatherTool()])

    #expect(body.toolConfig?.toolChoice == .auto)
  }

  @available(anyAppleOS 27, *)
  @Test("writes required as any")
  func sendsRequiredAsAny() {
    let body = buildRequest(Self.prompt(), options: Self.options(.required), tools: [weatherTool()])

    #expect(body.toolConfig?.toolChoice == .any)
  }

  @available(anyAppleOS 27, *)
  @Test("expresses disallowed by sending no tools at all")
  func sendsNoToolsWhenDisallowed() {
    let body = buildRequest(
      Self.prompt(), options: Self.options(.disallowed), tools: [weatherTool()])

    #expect(body.toolConfig == nil)
  }

  @available(anyAppleOS 27, *)
  @Test("keeps the tools when disallowed but the history already used one")
  func keepsToolsWhenHistoryMentionsThem() {
    let body = buildRequest(
      Self.promptWithToolRoundTrip(), options: Self.options(.disallowed), tools: [weatherTool()])

    // Converse rejects a history that mentions a tool the request doesn't
    // describe, so the tools stay and the choice falls back to the default.
    #expect(body.toolConfig?.tools.count == 1)
    #expect(body.toolConfig?.toolChoice == nil)
  }
}

@Suite("ConverseRequestBuilder structured output")
struct ConverseRequestBuilderStructuredOutputTests {
  @available(anyAppleOS 27, *)
  private static func prompt(
    responseFormat: Transcript.ResponseFormat? = nil
  ) -> [Transcript.Entry] {
    [
      .prompt(
        Transcript.Prompt(segments: textSegments("what is the weather?"), responseFormat: responseFormat))
    ]
  }

  @available(anyAppleOS 27, *)
  private static func toolName(_ tool: ConverseTool) -> String? {
    if case .toolSpec(let spec) = tool { spec.name } else { nil }
  }

  @available(anyAppleOS 27, *)
  @Test("synthesizes a tool for the schema and names it in the choice")
  func synthesizesToolForSchema() {
    let built = buildFullRequest(Self.prompt(), schema: WeatherInput.generationSchema)

    #expect(built.structuredOutputToolName == ConverseRequestBuilder.structuredOutputToolBaseName)
    #expect(built.request.toolConfig?.tools.count == 1)
    #expect(
      built.request.toolConfig?.toolChoice
        == .tool(name: ConverseRequestBuilder.structuredOutputToolBaseName))
  }

  @available(anyAppleOS 27, *)
  @Test("asks only that some tool runs when the caller has tools of its own")
  func leavesRoomForCallerTools() {
    let built = buildFullRequest(
      Self.prompt(), tools: [weatherTool()], schema: WeatherInput.generationSchema)

    #expect(built.request.toolConfig?.tools.count == 2)
    #expect(built.request.toolConfig?.toolChoice == .any)
  }

  @available(anyAppleOS 27, *)
  @Test("steps around a caller tool that already owns the name")
  func avoidsNameCollision() {
    let collidingTool = Transcript.ToolDefinition(
      name: ConverseRequestBuilder.structuredOutputToolBaseName,
      description: "A tool that got there first.",
      parameters: WeatherInput.generationSchema
    )

    let built = buildFullRequest(
      Self.prompt(), tools: [collidingTool], schema: WeatherInput.generationSchema)

    #expect(
      built.structuredOutputToolName == "\(ConverseRequestBuilder.structuredOutputToolBaseName)_2")
    let names = (built.request.toolConfig?.tools ?? []).compactMap(Self.toolName)
    #expect(Set(names).count == 2)
  }

  @available(anyAppleOS 27, *)
  @Test("reads the schema off the last prompt when the request carries none")
  func fallsBackToPromptResponseFormat() {
    let built = buildFullRequest(
      Self.prompt(responseFormat: Transcript.ResponseFormat(schema: WeatherInput.generationSchema)))

    #expect(built.structuredOutputToolName == ConverseRequestBuilder.structuredOutputToolBaseName)
    #expect(built.request.toolConfig?.tools.count == 1)
  }

  @available(anyAppleOS 27, *)
  @Test("synthesizes nothing when the caller asked for no particular shape")
  func synthesizesNothingWithoutSchema() {
    let built = buildFullRequest(Self.prompt())

    #expect(built.structuredOutputToolName == nil)
    #expect(built.request.toolConfig == nil)
  }
}

@Suite("ConverseResponseTranslator tool arguments")
struct ConverseResponseTranslatorArgumentsTests {
  @available(anyAppleOS 27, *)
  @Test("writes an object input as sorted JSON")
  func writesObjectInput() {
    let block = ToolUseBlock(
      toolUseId: "t", name: "x", input: ["b": 2, "a": 1])

    #expect(ConverseResponseTranslator.arguments(of: block) == #"{"a":1,"b":2}"#)
  }

  @available(anyAppleOS 27, *)
  @Test("collapses a non-object input to an empty object")
  func collapsesNonObjectInput() {
    let block = ToolUseBlock(toolUseId: "t", name: "x", input: "not an object")

    #expect(ConverseResponseTranslator.arguments(of: block) == "{}")
  }
}
