import BedrockRuntimeAPI
import Foundation
import FoundationModels

/// Executes generation requests against the Bedrock Converse API.
@available(anyAppleOS 27, *)
public struct BedrockExecutor: LanguageModelExecutor {
  public typealias Model = BedrockLanguageModel

  public struct Configuration: Hashable, Sendable {
    public let modelId: String
    public let region: String
    public let auth: BedrockAuth

    public init(modelId: String, region: String, auth: BedrockAuth) {
      self.modelId = modelId
      self.region = region
      self.auth = auth
    }
  }

  public let configuration: Configuration
  private let client: BedrockRuntimeClient

  public init(configuration: Configuration) throws {
    self.init(
      configuration: configuration,
      client: BedrockRuntimeClient(
        configuration: .init(
          region: configuration.region,
          credentials: configuration.auth.credentials
        )
      )
    )
  }

  /// Injects the client so the executor can be exercised without a network.
  init(configuration: Configuration, client: BedrockRuntimeClient) {
    self.configuration = configuration
    self.client = client
  }

  public func respond(
    to request: LanguageModelExecutorGenerationRequest,
    model: BedrockLanguageModel,
    streamingInto channel: LanguageModelExecutorGenerationChannel
  ) async throws {
    let built = try ConverseRequestBuilder.build(from: request)
    do {
      let response = try await client.converse(
        modelId: configuration.modelId, request: built.request)
      try await ConverseResponseTranslator.send(
        response, structuredOutputToolName: built.structuredOutputToolName, into: channel)
    } catch let error as BedrockRuntimeError {
      throw BedrockError(error)
    }
  }

  public func prewarm(model: BedrockLanguageModel, transcript: Transcript) {}
}
