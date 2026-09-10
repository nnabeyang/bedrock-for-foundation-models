import Foundation
import FoundationModels

/// Amazon Bedrock as a Foundation Models server-side language model.
///
/// ```swift
/// let model = BedrockLanguageModel(
///   modelId: "us.anthropic.claude-sonnet-5-20250929-v1:0",
///   region: "us-east-1",
///   auth: .apiKey(apiKey)
/// )
/// let session = LanguageModelSession(model: model)
/// ```
@available(anyAppleOS 27, *)
public struct BedrockLanguageModel: LanguageModel, Sendable {
  public typealias Executor = BedrockExecutor

  public let modelId: String
  public let region: String
  public let auth: BedrockAuth

  public init(modelId: String, region: String, auth: BedrockAuth) {
    self.modelId = modelId
    self.region = region
    self.auth = auth
  }

  public var capabilities: LanguageModelCapabilities {
    LanguageModelCapabilities([.toolCalling, .guidedGeneration])
  }

  public var executorConfiguration: BedrockExecutor.Configuration {
    .init(modelId: modelId, region: region, auth: auth)
  }
}
