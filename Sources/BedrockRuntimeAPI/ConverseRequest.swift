import Foundation

/// Request body for `POST /model/{modelId}/converse`.
///
/// `modelId` is not part of the body — it goes in the URL path, so
/// ``BedrockRuntimeClient/converse(modelId:request:)`` takes it separately.
public struct ConverseRequest: Sendable, Hashable, Codable {
  public var messages: [ConverseMessage]
  public var system: [SystemContentBlock]?
  public var inferenceConfig: InferenceConfiguration?
  public var toolConfig: ToolConfiguration?
  /// Inference parameters beyond the base set, passed through to the model.
  public var additionalModelRequestFields: JSONValue?

  public init(
    messages: [ConverseMessage],
    system: [SystemContentBlock]? = nil,
    inferenceConfig: InferenceConfiguration? = nil,
    toolConfig: ToolConfiguration? = nil,
    additionalModelRequestFields: JSONValue? = nil
  ) {
    self.messages = messages
    self.system = system
    self.inferenceConfig = inferenceConfig
    self.toolConfig = toolConfig
    self.additionalModelRequestFields = additionalModelRequestFields
  }
}
