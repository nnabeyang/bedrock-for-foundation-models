import CoreGraphics
import Foundation
import FoundationModels
import ImageIO
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
) throws -> ConverseRequest {
  try buildFullRequest(entries, options: options, tools: tools).request
}

@available(anyAppleOS 27, *)
private func buildFullRequest(
  _ entries: [Transcript.Entry],
  options: GenerationOptions = GenerationOptions(toolCallingMode: nil),
  tools: [Transcript.ToolDefinition] = [],
  schema: GenerationSchema? = nil
) throws -> BuiltConverseRequest {
  try ConverseRequestBuilder.build(
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

    let body = try buildRequest(entries)

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
  func emptyToolOutput() throws {
    let entries: [Transcript.Entry] = [
      .toolOutput(Transcript.ToolOutput(id: "tu_1", toolName: "x", segments: textSegments("")))
    ]
    let body = try buildRequest(entries)
    guard case .toolResult(let result) = body.messages.first?.content.first else {
      Issue.record("expected a toolResult block")
      return
    }
    #expect(result.content == [.text("(no output)")])
  }
}

@available(anyAppleOS 27, *)
@Generable
private struct SearchInput {
  @Guide(description: "How many results to return.", .range(1...10))
  var limit: Int

  @Guide(description: "Tags the result must carry.", .count(2...3))
  var tags: [String]

  @Guide(description: "The first day to include, as YYYY-MM-DD.", /^\d{4}-\d{2}-\d{2}$/)
  var since: String?
}

// `JSONSchemaTests` checks the sanitizer against hand-written JSON. These run
// the schema `@Guide` actually generates through the builder, so a change in
// how the framework encodes a guide shows up here rather than at Bedrock.
@Suite("ConverseRequestBuilder tool schema")
struct ConverseRequestBuilderToolSchemaTests {
  @available(anyAppleOS 27, *)
  private static func inputSchema() throws -> JSONValue? {
    let tool = Transcript.ToolDefinition(
      name: "search_items",
      description: "Searches the items.",
      parameters: SearchInput.generationSchema
    )
    let body = try buildRequest(
      [.prompt(Transcript.Prompt(segments: textSegments("find the items")))], tools: [tool])
    guard case .toolSpec(let spec) = body.toolConfig?.tools.first,
      case .json(let schema) = spec.inputSchema
    else { return nil }
    return schema
  }

  @available(anyAppleOS 27, *)
  @Test("keeps the validation keywords @Guide generates")
  func keepsGuideConstraints() throws {
    let properties = try #require(try Self.inputSchema()?["properties"])

    #expect(properties["limit"]?["minimum"] == 1)
    #expect(properties["limit"]?["maximum"] == 10)
    #expect(properties["tags"]?["minItems"] == 2)
    #expect(properties["tags"]?["maxItems"] == 3)
    // The framework decides how the regex is spelled (it writes `-` as `\-`),
    // so only the keyword's presence is pinned here.
    guard case .string = properties["since"]?["pattern"] else {
      Issue.record("expected a string pattern, got \(String(describing: properties["since"]))")
      return
    }
  }

  @available(anyAppleOS 27, *)
  @Test("leaves an optional property out of required")
  func leavesOptionalOutOfRequired() throws {
    guard case .array(let required) = try #require(try Self.inputSchema()?["required"]) else {
      Issue.record("expected required to be an array")
      return
    }

    #expect(Set(required) == ["limit", "tags"])
  }

  @available(anyAppleOS 27, *)
  @Test("drops the generator's bookkeeping keys from the generated schema")
  func dropsBookkeepingKeys() throws {
    let schema = try #require(try Self.inputSchema())

    #expect(schema["title"] == nil)
    #expect(schema["x-order"] == nil)
    #expect(schema["additionalProperties"] == nil)
  }
}

@Suite("ConverseRequestBuilder reasoning replay")
struct ConverseRequestBuilderReasoningTests {
  @available(anyAppleOS 27, *)
  @Test("drops a reasoning entry that carries no signature")
  func dropsUnsignedReasoning() throws {
    let entries: [Transcript.Entry] = [
      .reasoning(Transcript.Reasoning(segments: textSegments("half a thought"), signature: nil)),
      .response(Transcript.Response(assetIDs: [], segments: textSegments("answer"))),
    ]
    let body = try buildRequest(entries)
    // Only the response survives.
    #expect(body.messages.count == 1)
    #expect(body.messages[0].content == [.text("answer")])
  }

  @available(anyAppleOS 27, *)
  @Test("replays a signed reasoning entry as reasoningText with the signature")
  func replaysSignedReasoning() throws {
    let sig = Data([1, 2, 3])
    let entries: [Transcript.Entry] = [
      .reasoning(Transcript.Reasoning(segments: textSegments("a thought"), signature: sig))
    ]
    let body = try buildRequest(entries)
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
  func replaysRedactedReasoning() throws {
    let sig = Data([9, 9, 9])
    let entries: [Transcript.Entry] = [
      .reasoning(
        Transcript.Reasoning(
          metadata: [redactedReasoningMetadataKey: true],
          segments: [],
          signature: sig
        ))
    ]
    let body = try buildRequest(entries)
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
  func omitsEmptyInferenceConfig() throws {
    let body = try buildRequest(Self.prompt())

    #expect(body.inferenceConfig == nil)
    #expect(body.additionalModelRequestFields == nil)
  }

  @available(anyAppleOS 27, *)
  @Test("carries the response token limit")
  func sendsMaximumResponseTokens() throws {
    let body = try buildRequest(
      Self.prompt(),
      options: GenerationOptions(
        samplingMode: nil, temperature: nil, maximumResponseTokens: 512, toolCallingMode: nil))

    #expect(body.inferenceConfig == InferenceConfiguration(maxTokens: 512))
  }

  @available(anyAppleOS 27, *)
  @Test("expresses greedy sampling as temperature 0")
  func sendsGreedyAsZeroTemperature() throws {
    let body = try buildRequest(
      Self.prompt(),
      options: GenerationOptions(
        samplingMode: .greedy, temperature: nil, maximumResponseTokens: nil, toolCallingMode: nil))

    #expect(body.inferenceConfig == InferenceConfiguration(temperature: 0))
  }

  @available(anyAppleOS 27, *)
  @Test("lets an explicit temperature override the one greedy implies")
  func explicitTemperatureWinsOverGreedy() throws {
    let body = try buildRequest(
      Self.prompt(),
      options: GenerationOptions(
        samplingMode: .greedy, temperature: 0.7, maximumResponseTokens: nil, toolCallingMode: nil))

    #expect(body.inferenceConfig == InferenceConfiguration(temperature: 0.7))
  }

  @available(anyAppleOS 27, *)
  @Test("maps a probability threshold onto topP")
  func sendsProbabilityThresholdAsTopP() throws {
    let body = try buildRequest(
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
  func sendsTopKThroughAdditionalFields() throws {
    let body = try buildRequest(
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
  func omitsToolConfigWithoutTools() throws {
    #expect(try buildRequest(Self.prompt()).toolConfig == nil)
  }

  @available(anyAppleOS 27, *)
  @Test("leaves the choice to the model when the caller named no mode")
  func omitsToolChoiceWithoutMode() throws {
    let body = try buildRequest(Self.prompt(), options: Self.options(nil), tools: [weatherTool()])

    #expect(body.toolConfig?.tools.count == 1)
    #expect(body.toolConfig?.toolChoice == nil)
  }

  @available(anyAppleOS 27, *)
  @Test("writes allowed as auto")
  func sendsAllowedAsAuto() throws {
    let body = try buildRequest(Self.prompt(), options: Self.options(.allowed), tools: [weatherTool()])

    #expect(body.toolConfig?.toolChoice == .auto)
  }

  @available(anyAppleOS 27, *)
  @Test("writes required as any")
  func sendsRequiredAsAny() throws {
    let body = try buildRequest(Self.prompt(), options: Self.options(.required), tools: [weatherTool()])

    #expect(body.toolConfig?.toolChoice == .any)
  }

  @available(anyAppleOS 27, *)
  @Test("expresses disallowed by sending no tools at all")
  func sendsNoToolsWhenDisallowed() throws {
    let body = try buildRequest(
      Self.prompt(), options: Self.options(.disallowed), tools: [weatherTool()])

    #expect(body.toolConfig == nil)
  }

  @available(anyAppleOS 27, *)
  @Test("keeps the tools when disallowed but the history already used one")
  func keepsToolsWhenHistoryMentionsThem() throws {
    let body = try buildRequest(
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
  func synthesizesToolForSchema() throws {
    let built = try buildFullRequest(Self.prompt(), schema: WeatherInput.generationSchema)

    #expect(built.structuredOutputToolName == ConverseRequestBuilder.structuredOutputToolBaseName)
    #expect(built.request.toolConfig?.tools.count == 1)
    #expect(
      built.request.toolConfig?.toolChoice
        == .tool(name: ConverseRequestBuilder.structuredOutputToolBaseName))
  }

  @available(anyAppleOS 27, *)
  @Test("asks only that some tool runs when the caller has tools of its own")
  func leavesRoomForCallerTools() throws {
    let built = try buildFullRequest(
      Self.prompt(), tools: [weatherTool()], schema: WeatherInput.generationSchema)

    #expect(built.request.toolConfig?.tools.count == 2)
    #expect(built.request.toolConfig?.toolChoice == .any)
  }

  @available(anyAppleOS 27, *)
  @Test("steps around a caller tool that already owns the name")
  func avoidsNameCollision() throws {
    let collidingTool = Transcript.ToolDefinition(
      name: ConverseRequestBuilder.structuredOutputToolBaseName,
      description: "A tool that got there first.",
      parameters: WeatherInput.generationSchema
    )

    let built = try buildFullRequest(
      Self.prompt(), tools: [collidingTool], schema: WeatherInput.generationSchema)

    #expect(
      built.structuredOutputToolName == "\(ConverseRequestBuilder.structuredOutputToolBaseName)_2")
    let names = (built.request.toolConfig?.tools ?? []).compactMap(Self.toolName)
    #expect(Set(names).count == 2)
  }

  @available(anyAppleOS 27, *)
  @Test("reads the schema off the last prompt when the request carries none")
  func fallsBackToPromptResponseFormat() throws {
    let built = try buildFullRequest(
      Self.prompt(responseFormat: Transcript.ResponseFormat(schema: WeatherInput.generationSchema)))

    #expect(built.structuredOutputToolName == ConverseRequestBuilder.structuredOutputToolBaseName)
    #expect(built.request.toolConfig?.tools.count == 1)
  }

  @available(anyAppleOS 27, *)
  @Test("synthesizes nothing when the caller asked for no particular shape")
  func synthesizesNothingWithoutSchema() throws {
    let built = try buildFullRequest(Self.prompt())

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

@available(anyAppleOS 27, *)
private func sampleImageAttachment(
  width: Int, height: Int, orientation: CGImagePropertyOrientation? = nil
) throws -> Transcript.ImageAttachment {
  let context = try #require(
    CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  return Transcript.ImageAttachment(try #require(context.makeImage()), orientation: orientation)
}

@Suite("ConverseRequestBuilder attachments")
struct ConverseRequestBuilderAttachmentTests {
  @available(anyAppleOS 27, *)
  @Test("sends an image attachment in the prompt as an image block after the text")
  func sendsPromptImage() throws {
    let attachment = try sampleImageAttachment(width: 8, height: 4)
    let entries: [Transcript.Entry] = [
      .prompt(
        Transcript.Prompt(segments: [
          .text(Transcript.TextSegment(content: "What is in this picture?")),
          .attachment(Transcript.AttachmentSegment(content: .image(attachment), label: "photo")),
        ]))
    ]

    let body = try buildRequest(entries)

    #expect(body.messages.count == 1)
    #expect(body.messages[0].role == .user)
    #expect(body.messages[0].content.count == 2)
    #expect(body.messages[0].content[0] == .text("What is in this picture?"))
    guard case .image(let image) = body.messages[0].content[1] else {
      Issue.record("expected an image block, got \(body.messages[0].content)")
      return
    }
    #expect(image.format == .jpeg)
    #expect(image.source.bytes.prefix(2) == Data([0xFF, 0xD8]))
  }

  @available(anyAppleOS 27, *)
  @Test("puts an image in a tool result next to its text")
  func sendsToolOutputImage() throws {
    let attachment = try sampleImageAttachment(width: 4, height: 4)
    let entries: [Transcript.Entry] = [
      .toolOutput(
        Transcript.ToolOutput(
          id: "tu_1", toolName: "fetch_image",
          segments: [
            .text(Transcript.TextSegment(content: "photo.jpg")),
            .attachment(Transcript.AttachmentSegment(content: .image(attachment))),
          ]))
    ]

    let body = try buildRequest(entries)

    guard case .toolResult(let result) = body.messages.first?.content.first else {
      Issue.record("expected a toolResult block")
      return
    }
    #expect(result.content.count == 2)
    #expect(result.content[0] == .text("photo.jpg"))
    guard case .image(let image) = result.content[1] else {
      Issue.record("expected an image block in the tool result")
      return
    }
    #expect(image.format == .jpeg)
  }

  @available(anyAppleOS 27, *)
  @Test("sends only the image when a tool result has no text")
  func sendsImageOnlyToolOutput() throws {
    let attachment = try sampleImageAttachment(width: 4, height: 4)
    let entries: [Transcript.Entry] = [
      .toolOutput(
        Transcript.ToolOutput(
          id: "tu_1", toolName: "fetch_image",
          segments: [.attachment(Transcript.AttachmentSegment(content: .image(attachment)))]))
    ]

    let body = try buildRequest(entries)

    guard case .toolResult(let result) = body.messages.first?.content.first,
      case .image? = result.content.first
    else {
      Issue.record("expected a toolResult with an image block")
      return
    }
    #expect(result.content.count == 1)
  }
}
