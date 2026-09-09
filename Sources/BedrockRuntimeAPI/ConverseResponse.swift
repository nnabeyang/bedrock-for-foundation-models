import Foundation

/// Response body for `POST /model/{modelId}/converse`.
public struct ConverseResponse: Sendable, Hashable, Codable {
  public var output: ConverseOutput
  public var stopReason: StopReason?
  public var usage: TokenUsage?
  public var metrics: ConverseMetrics?
  public var additionalModelResponseFields: JSONValue?

  public init(
    output: ConverseOutput,
    stopReason: StopReason? = nil,
    usage: TokenUsage? = nil,
    metrics: ConverseMetrics? = nil,
    additionalModelResponseFields: JSONValue? = nil
  ) {
    self.output = output
    self.stopReason = stopReason
    self.usage = usage
    self.metrics = metrics
    self.additionalModelResponseFields = additionalModelResponseFields
  }
}

/// What the model produced. Only the `message` form exists today.
public enum ConverseOutput: Sendable, Hashable, Codable {
  case message(ConverseMessage)
  case other(JSONValue)

  /// The model's message, or `nil` when the service sent a form this package
  /// doesn't model.
  public var message: ConverseMessage? {
    if case .message(let message) = self { message } else { nil }
  }

  private enum CodingKeys: String, CodingKey {
    case message
  }

  public init(from decoder: Decoder) throws {
    guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
      self = .other(try JSONValue(from: decoder))
      return
    }
    if let message = try c.decodeIfPresent(ConverseMessage.self, forKey: .message) {
      self = .message(message)
    } else {
      self = .other(try JSONValue(from: decoder))
    }
  }

  public func encode(to encoder: Encoder) throws {
    if case .other(let value) = self {
      try value.encode(to: encoder)
      return
    }
    var c = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .message(let message): try c.encode(message, forKey: .message)
    case .other: break
    }
  }
}

/// Why generation stopped.
public enum StopReason: String, Sendable, Hashable, Codable {
  case endTurn = "end_turn"
  case toolUse = "tool_use"
  case maxTokens = "max_tokens"
  case stopSequence = "stop_sequence"
  case contentFiltered = "content_filtered"
  case guardrailIntervened = "guardrail_intervened"
  case malformedModelOutput = "malformed_model_output"
  case malformedToolUse = "malformed_tool_use"
  case modelContextWindowExceeded = "model_context_window_exceeded"
  /// Forward-compatibility: a stop reason added after this package shipped must
  /// not fail a response whose content is perfectly usable.
  case unknown

  public init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    self = StopReason(rawValue: raw) ?? .unknown
  }
}

/// Token counts for the request. `inputTokens` excludes tokens served from the
/// prompt cache — `cacheReadInputTokens` reports those separately.
public struct TokenUsage: Sendable, Hashable, Codable {
  public var inputTokens: Int
  public var outputTokens: Int
  public var totalTokens: Int?
  public var cacheReadInputTokens: Int?
  public var cacheWriteInputTokens: Int?

  public init(
    inputTokens: Int,
    outputTokens: Int,
    totalTokens: Int? = nil,
    cacheReadInputTokens: Int? = nil,
    cacheWriteInputTokens: Int? = nil
  ) {
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
    self.totalTokens = totalTokens
    self.cacheReadInputTokens = cacheReadInputTokens
    self.cacheWriteInputTokens = cacheWriteInputTokens
  }

  /// Counts are telemetry, not content: a response that omits one is still
  /// worth delivering, so a missing count reads as zero rather than failing.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
    outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
    totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens)
    cacheReadInputTokens = try c.decodeIfPresent(Int.self, forKey: .cacheReadInputTokens)
    cacheWriteInputTokens = try c.decodeIfPresent(Int.self, forKey: .cacheWriteInputTokens)
  }
}

/// Timing the service reports for the call.
public struct ConverseMetrics: Sendable, Hashable, Codable {
  public var latencyMs: Int?

  public init(latencyMs: Int? = nil) {
    self.latencyMs = latencyMs
  }
}
