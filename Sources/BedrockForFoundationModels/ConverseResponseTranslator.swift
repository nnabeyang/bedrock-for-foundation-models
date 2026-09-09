import BedrockRuntimeAPI
import Foundation
import FoundationModels

/// Pure translation: Converse response → the framework's generation channel.
@available(anyAppleOS 27, *)
enum ConverseResponseTranslator {
  static func send(
    _ response: ConverseResponse,
    into channel: LanguageModelExecutorGenerationChannel
  ) async throws {
    guard let message = response.output.message else {
      throw BedrockError.invalidResponse("output.message missing")
    }

    try throwIfStopReasonUnusable(response, message: message)

    let responseEntryID = UUID().uuidString
    let toolCallsEntryID = UUID().uuidString

    for block in message.content {
      switch block {
      case .text(let text) where !text.isEmpty:
        await channel.send(
          .response(
            entryID: responseEntryID,
            action: .appendText(text, tokenCount: 1)
          ))

      case .toolUse(let toolUse):
        // Open the tool call with an empty argument chunk, then append the
        // full JSON. A non-object `input` (Bedrock should never send one for a
        // schema-shaped tool) collapses to `{}`, mirroring the request side's
        // `toolInput(_:)`, so the round-trip stays consistent.
        let argumentsJSON: String
        if case .object = toolUse.input {
          argumentsJSON = toolUse.input.jsonText
        } else {
          argumentsJSON = "{}"
        }
        await channel.send(
          .toolCalls(
            entryID: toolCallsEntryID,
            action: .toolCall(
              id: toolUse.toolUseId,
              name: toolUse.name,
              action: .appendArguments("", tokenCount: 0)
            )
          ))
        await channel.send(
          .toolCalls(
            entryID: toolCallsEntryID,
            action: .toolCall(
              id: toolUse.toolUseId,
              name: toolUse.name,
              action: .appendArguments(argumentsJSON, tokenCount: 1)
            )
          ))

      case .reasoningContent(.reasoningText(let reasoning)):
        let reasoningEntryID = UUID().uuidString
        if !reasoning.text.isEmpty {
          await channel.send(
            .reasoning(
              entryID: reasoningEntryID,
              action: .appendText(reasoning.text, tokenCount: 1)
            ))
        }
        // The wire signature is an opaque string; the framework stores bytes.
        if let signature = reasoning.signature, !signature.isEmpty,
          let data = Data(base64Encoded: signature)
        {
          await channel.send(
            .reasoning(
              entryID: reasoningEntryID,
              action: .updateSignature(data, tokenCount: 0)
            ))
        }

      case .reasoningContent(.redactedContent(let data)):
        // Reasoning the service withheld. Keep it: surface a signature-only
        // reasoning entry, flagged so the request builder replays it verbatim
        // as `redactedContent` (Bedrock requires redacted thoughts back exactly
        // as received to keep the thought chain verifiable).
        let reasoningEntryID = UUID().uuidString
        await channel.send(
          .reasoning(
            entryID: reasoningEntryID,
            action: .updateMetadata([redactedReasoningMetadataKey: true])
          ))
        await channel.send(
          .reasoning(
            entryID: reasoningEntryID,
            action: .updateSignature(data, tokenCount: 0)
          ))

      case .text, .toolResult, .reasoningContent, .other:
        break
      }
    }

    if let usage = response.usage {
      await channel.send(
        .response(
          entryID: responseEntryID,
          action: .updateUsage(
            input: .init(
              totalTokenCount: usage.inputTokens,
              cachedTokenCount: usage.cacheReadInputTokens ?? 0
            ),
            output: .init(totalTokenCount: usage.outputTokens, reasoningTokenCount: 0)
          )
        ))
    }
  }

  /// The translator only forwards content; `stopReason` says whether that
  /// content is trustworthy. Turn the reasons that mean "the turn is unusable"
  /// into a thrown error so the session doesn't silently accept a filtered,
  /// truncated, or malformed answer.
  static func throwIfStopReasonUnusable(
    _ response: ConverseResponse,
    message: ConverseMessage
  ) throws {
    switch response.stopReason {
    case .modelContextWindowExceeded:
      // Phrased to contain the substring eich's `BedrockAgentBackend` matches
      // on to reset the session and retry.
      throw BedrockError.invalidResponse(
        "the request exceeds the maximum allowed context size for this model")

    case .contentFiltered, .guardrailIntervened, .malformedModelOutput, .malformedToolUse:
      // A hard stop with usable content still in the message (rare) is left to
      // the caller; a hard stop with nothing usable is an error.
      let hasUsableContent = message.content.contains { block in
        switch block {
        case .text(let text): !text.isEmpty
        case .toolUse, .reasoningContent: true
        case .toolResult, .other: false
        }
      }
      if !hasUsableContent {
        throw BedrockError.invalidResponse(
          "generation stopped: \(response.stopReason?.rawValue ?? "unknown")")
      }

    case .endTurn, .toolUse, .stopSequence, .maxTokens, .unknown, nil:
      break
    }
  }
}
