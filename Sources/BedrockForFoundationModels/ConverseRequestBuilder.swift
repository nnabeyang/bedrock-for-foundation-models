import BedrockRuntimeAPI
import Foundation
import FoundationModels

/// Marks a reasoning transcript entry the service redacted — replayed verbatim
/// as `redactedContent` rather than a `reasoningText` block. Set by
/// ``ConverseResponseTranslator`` when it sees a `redactedContent` block, read
/// back here on the following turn.
let redactedReasoningMetadataKey = "bedrock.redactedReasoning"

/// Pure translation: framework request → Converse request body.
@available(anyAppleOS 27, *)
enum ConverseRequestBuilder {
  static func build(from request: LanguageModelExecutorGenerationRequest) -> ConverseRequest {
    var systemParts: [String] = []
    var messages: [ConverseMessage] = []

    for entry in request.transcript {
      switch entry {
      case .instructions(let instructions):
        let text = text(of: instructions.segments)
        if !text.isEmpty { systemParts.append(text) }

      case .prompt(let prompt):
        let content = contentBlocks(from: prompt.segments)
        if !content.isEmpty { messages.append(.init(role: .user, content: content)) }

      case .response(let response):
        let content = contentBlocks(from: response.segments)
        if !content.isEmpty { messages.append(.init(role: .assistant, content: content)) }

      case .toolCalls(let calls):
        let content = calls.map { call in
          ConverseContentBlock.toolUse(
            .init(toolUseId: call.id, name: call.toolName, input: toolInput(call.arguments))
          )
        }
        if !content.isEmpty { messages.append(.init(role: .assistant, content: content)) }

      case .toolOutput(let output):
        let text = text(of: output.segments)
        messages.append(
          .init(
            role: .user,
            content: [
              .toolResult(
                .init(
                  toolUseId: output.id,
                  content: [.text(text.isEmpty ? "(no output)" : text)]
                )
              )
            ]
          )
        )

      case .reasoning(let reasoning):
        // Send the thinking block back on the next turn; its signature has to
        // be replayed with it. The framework holds the signature as bytes and
        // the wire carries a string, so it crosses base64-encoded.
        //
        // Bedrock rejects a replayed reasoning block that precedes `toolUse` on
        // a thinking turn unless it carries a valid signature, and dropping the
        // rejected assistant turn takes any merged `toolUse` blocks with it —
        // breaking the toolUse/toolResult pairing. A signature-less entry
        // (prior-turn thinking, or thinking this executor never enabled) is
        // safe to omit, so only signed entries replay.
        guard let signature = reasoning.signature else { break }
        let reasoningBlock: ConverseContentBlock =
          isRedactedReasoning(reasoning)
          ? .reasoningContent(.redactedContent(signature))
          : .reasoningContent(
            .reasoningText(
              .init(
                text: text(of: reasoning.segments),
                signature: signature.base64EncodedString()
              )
            )
          )
        messages.append(.init(role: .assistant, content: [reasoningBlock]))

      @unknown default:
        break
      }
    }

    var body = ConverseRequest(messages: messages.mergingConsecutiveSameRole())

    let options = request.generationOptions
    body.inferenceConfig = inferenceConfiguration(for: options)
    if case .randomTopK(let topK, _)? = options.samplingMode?.kind {
      // top-k is not one of Converse's base parameters, so it rides in the
      // model-specific passthrough. The spelling is Anthropic's; a model family
      // that doesn't know the key answers 400, which tells the caller their
      // sampling mode didn't apply instead of quietly ignoring it.
      body.additionalModelRequestFields = ["top_k": .number(Double(topK))]
    }

    if !systemParts.isEmpty {
      body.system = [.text(systemParts.joined(separator: "\n\n"))]
    }

    body.toolConfig = toolConfiguration(
      for: options.toolCallingMode,
      tools: request.enabledToolDefinitions.map(tool(from:)),
      messages: body.messages
    )

    return body
  }

  // MARK: - Private helpers

  /// The tools this turn may use, and how freely, or `nil` when none go out.
  ///
  /// Converse has no "never call a tool" choice, so a caller who forbids tool
  /// calling is served by sending no tools at all. That is not always available:
  /// once the transcript contains a tool round-trip, the request is rejected
  /// without a `toolConfig` describing the tools it mentions. The tools then
  /// stay and the choice is left at the model's default, which is the closest
  /// the API allows.
  private static func toolConfiguration(
    for mode: GenerationOptions.ToolCallingMode?,
    tools: [ConverseTool],
    messages: [ConverseMessage]
  ) -> ToolConfiguration? {
    guard !tools.isEmpty else { return nil }

    switch mode?.kind {
    case .allowed:
      return ToolConfiguration(tools: tools, toolChoice: .auto)
    case .required:
      return ToolConfiguration(tools: tools, toolChoice: .any)
    case .disallowed:
      return messages.containsToolBlocks ? ToolConfiguration(tools: tools) : nil
    case .none:
      return ToolConfiguration(tools: tools)
    @unknown default:
      return ToolConfiguration(tools: tools)
    }
  }

  /// The base inference parameters, or `nil` when the caller named none.
  ///
  /// `maxTokens` only goes out when the framework asked for a limit: left
  /// alone, Bedrock applies its own default, and overshooting it makes the
  /// service answer 503.
  ///
  /// The seed a sampling mode may carry is dropped. Converse has no parameter
  /// for it, and there is nowhere to put it that would make generation
  /// reproducible.
  private static func inferenceConfiguration(
    for options: GenerationOptions
  ) -> InferenceConfiguration? {
    var configuration = InferenceConfiguration(maxTokens: options.maximumResponseTokens)

    switch options.samplingMode?.kind {
    case .greedy:
      // Converse has no "greedy" switch; temperature 0 is how the same
      // intent — take the most likely token — is expressed on the wire.
      configuration.temperature = 0
    case .randomProbabilityThreshold(let threshold, _):
      configuration.topP = threshold
    case .randomTopK, .none:
      break
    @unknown default:
      break
    }

    // An explicit temperature is the more specific instruction, so it overrides
    // the one implied by a sampling mode.
    if let temperature = options.temperature {
      configuration.temperature = temperature
    }

    return configuration == InferenceConfiguration() ? nil : configuration
  }

  private static func text(of segments: [Transcript.Segment]) -> String {
    segments.compactMap { segment -> String? in
      switch segment {
      case .text(let text): text.content.isEmpty ? nil : text.content
      case .structure(let structure): structure.content.jsonString
      case .attachment: nil
      @unknown default: nil
      }
    }
    .joined(separator: "\n")
  }

  private static func contentBlocks(
    from segments: [Transcript.Segment]
  ) -> [ConverseContentBlock] {
    segments.compactMap { segment -> ConverseContentBlock? in
      switch segment {
      case .text(let text) where !text.content.isEmpty: .text(text.content)
      case .structure(let structure): .text(structure.content.jsonString)
      default: nil
      }
    }
  }

  private static func toolInput(_ arguments: GeneratedContent) -> JSONValue {
    let input = JSONValue(arguments)
    return if case .object = input { input } else { [:] }
  }

  private static func isRedactedReasoning(_ reasoning: Transcript.Reasoning) -> Bool {
    guard let flag = reasoning.metadata[redactedReasoningMetadataKey] else { return false }
    if case .bool(true) = flag.kind { return true }
    return false
  }

  private static func tool(from definition: Transcript.ToolDefinition) -> ConverseTool {
    .toolSpec(
      .init(
        name: definition.name,
        description: definition.description,
        inputSchema: .json(.schema(definition.parameters))
      )
    )
  }
}
