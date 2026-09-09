import Foundation

/// The base inference parameters Converse accepts for every model. Anything
/// model-specific goes in `additionalModelRequestFields`.
public struct InferenceConfiguration: Sendable, Hashable, Codable {
  public var maxTokens: Int?
  public var temperature: Double?
  public var topP: Double?
  public var stopSequences: [String]?

  public init(
    maxTokens: Int? = nil,
    temperature: Double? = nil,
    topP: Double? = nil,
    stopSequences: [String]? = nil
  ) {
    self.maxTokens = maxTokens
    self.temperature = temperature
    self.topP = topP
    self.stopSequences = stopSequences
  }
}
