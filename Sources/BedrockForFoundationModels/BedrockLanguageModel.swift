import CommonCrypto
import Foundation
import FoundationModels

/// Credentials used to access the Amazon Bedrock Runtime API.
public enum BedrockAuth: Hashable, Sendable {
  /// A Bedrock API key sent as a bearer token.
  case apiKey(String)

  /// AWS SigV4 credentials, including an optional temporary session token.
  case sigV4(accessKeyId: String, secretKey: String, sessionToken: String?)
}

// MARK: - BedrockLanguageModel

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
    LanguageModelCapabilities([.toolCalling])
  }

  public var executorConfiguration: BedrockExecutor.Configuration {
    .init(modelId: modelId, region: region, auth: auth)
  }
}

// MARK: - BedrockExecutor

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

  public init(configuration: Configuration) throws {
    self.configuration = configuration
  }

  public func respond(
    to request: LanguageModelExecutorGenerationRequest,
    model: BedrockLanguageModel,
    streamingInto channel: LanguageModelExecutorGenerationChannel
  ) async throws {
    let body = try BedrockRequestBuilder.build(from: request)
    let responseBody = try await callConverse(body: body)

    guard let output = responseBody["output"] as? [String: Any],
      let message = output["message"] as? [String: Any],
      let contentArray = message["content"] as? [[String: Any]]
    else {
      throw BedrockError.invalidResponse("output.message.content missing")
    }

    let responseEntryID = UUID().uuidString
    let toolCallsEntryID = UUID().uuidString

    for block in contentArray {
      if let text = block["text"] as? String, !text.isEmpty {
        await channel.send(
          .response(
            entryID: responseEntryID,
            action: .appendText(text, tokenCount: 1)
          ))
      } else if let toolUse = block["toolUse"] as? [String: Any],
        let toolUseId = toolUse["toolUseId"] as? String,
        let name = toolUse["name"] as? String,
        let input = toolUse["input"] as? [String: Any]
      {
        // Open the tool call with an empty argument chunk, then append the full JSON.
        await channel.send(
          .toolCalls(
            entryID: toolCallsEntryID,
            action: .toolCall(id: toolUseId, name: name, action: .appendArguments("", tokenCount: 0))
          ))
        let inputJson =
          (try? JSONSerialization.data(withJSONObject: input))
          .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        await channel.send(
          .toolCalls(
            entryID: toolCallsEntryID,
            action: .toolCall(id: toolUseId, name: name, action: .appendArguments(inputJson, tokenCount: 1))
          ))
      } else if let reasoning = block["reasoningContent"] as? [String: Any] {
        let reasoningEntryID = UUID().uuidString
        if let rt = reasoning["reasoningText"] as? [String: Any] {
          let text = rt["text"] as? String ?? ""
          let sigStr = rt["signature"] as? String ?? ""
          if !text.isEmpty {
            await channel.send(
              .reasoning(
                entryID: reasoningEntryID,
                action: .appendText(text, tokenCount: 1)
              ))
          }
          if !sigStr.isEmpty, let sigData = Data(base64Encoded: sigStr) {
            await channel.send(
              .reasoning(
                entryID: reasoningEntryID,
                action: .updateSignature(sigData, tokenCount: 0)
              ))
          }
        }
      }
    }

    if let usage = responseBody["usage"] as? [String: Any] {
      let inputTokens = (usage["inputTokens"] as? Int) ?? 0
      let outputTokens = (usage["outputTokens"] as? Int) ?? 0
      await channel.send(
        .response(
          entryID: responseEntryID,
          action: .updateUsage(
            input: .init(totalTokenCount: inputTokens, cachedTokenCount: 0),
            output: .init(totalTokenCount: outputTokens, reasoningTokenCount: 0)
          )
        ))
    }
  }

  public func prewarm(model: BedrockLanguageModel, transcript: Transcript) {}

  // MARK: - HTTP

  private func callConverse(body: [String: Any]) async throws -> [String: Any] {
    let modelId = configuration.modelId
    let region = configuration.region

    let host = "bedrock-runtime.\(region).amazonaws.com"
    let encodedModelId =
      modelId
      .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelId
    let path = "/model/\(encodedModelId)/converse"
    guard let url = URL(string: "https://\(host)\(path)") else {
      throw BedrockError.invalidURL("https://\(host)\(path)")
    }

    let bodyData = try JSONSerialization.data(withJSONObject: body)

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = bodyData
    request.setValue("application/json", forHTTPHeaderField: "content-type")

    switch configuration.auth {
    case .apiKey(let apiKey):
      guard !apiKey.isEmpty else { throw BedrockError.missingCredentials }
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    case .sigV4(let accessKeyId, let secretKey, let sessionToken):
      guard !accessKeyId.isEmpty, !secretKey.isEmpty else {
        throw BedrockError.missingCredentials
      }
      let now = Date()
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
      formatter.timeZone = TimeZone(identifier: "UTC")
      let amzDate = formatter.string(from: now)
        .replacingOccurrences(of: ":", with: "")
        .replacingOccurrences(of: "-", with: "")
      let dateStamp = String(amzDate.prefix(8))

      request.setValue(host, forHTTPHeaderField: "host")
      request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
      if let sessionToken {
        request.setValue(sessionToken, forHTTPHeaderField: "x-amz-security-token")
      }
      let authHeader = try sigV4Authorization(
        method: "POST", path: path, host: host,
        amzDate: amzDate, dateStamp: dateStamp, body: bodyData,
        service: "bedrock", region: region,
        accessKeyId: accessKeyId, secretKey: secretKey, sessionToken: sessionToken)
      request.setValue(authHeader, forHTTPHeaderField: "Authorization")
    }

    // Bedrock returns 503 frequently under transient congestion, so retry with exponential backoff.
    var lastError: Error = BedrockError.invalidResponse("no attempts made")
    for attempt in 0..<4 {
      if attempt > 0 {
        let delay = UInt64(500_000_000) * UInt64(1 << (attempt - 1))  // 0.5s, 1s, 2s
        try await Task.sleep(nanoseconds: delay)
      }
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw BedrockError.invalidResponse("non-HTTP response")
      }
      if httpResponse.statusCode == 200 {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
          throw BedrockError.invalidResponse("response is not a JSON object")
        }
        return json
      }
      let bodyStr = String(data: data, encoding: .utf8) ?? "<binary>"
      lastError = BedrockError.httpError(httpResponse.statusCode, bodyStr)
      if httpResponse.statusCode != 503 { break }
    }
    throw lastError
  }

  // MARK: - AWS SigV4

  private func sigV4Authorization(
    method: String, path: String, host: String,
    amzDate: String, dateStamp: String, body: Data,
    service: String, region: String,
    accessKeyId: String, secretKey: String, sessionToken: String?
  ) throws -> String {
    var signedHeadersList = ["content-type", "host", "x-amz-date"]
    if sessionToken != nil { signedHeadersList.append("x-amz-security-token") }
    signedHeadersList.sort()
    let signedHeaders = signedHeadersList.joined(separator: ";")

    var canonicalHeaders = "content-type:application/json\nhost:\(host)\nx-amz-date:\(amzDate)\n"
    if let token = sessionToken { canonicalHeaders += "x-amz-security-token:\(token)\n" }

    let payloadHash = sha256Hex(body)
    let canonicalRequest = [method, path, "", canonicalHeaders, signedHeaders, payloadHash]
      .joined(separator: "\n")

    let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
    let stringToSign = [
      "AWS4-HMAC-SHA256", amzDate, credentialScope,
      sha256Hex(Data(canonicalRequest.utf8)),
    ].joined(separator: "\n")

    let signingKey = deriveSigningKey(
      secretKey: secretKey, dateStamp: dateStamp, region: region, service: service)
    let signature = hmacSHA256Hex(key: signingKey, data: Data(stringToSign.utf8))

    return "AWS4-HMAC-SHA256 Credential=\(accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
  }

  private func deriveSigningKey(
    secretKey: String, dateStamp: String, region: String, service: String
  ) -> Data {
    let kDate = hmacSHA256(key: Data("AWS4\(secretKey)".utf8), data: Data(dateStamp.utf8))
    let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
    let kService = hmacSHA256(key: kRegion, data: Data(service.utf8))
    return hmacSHA256(key: kService, data: Data("aws4_request".utf8))
  }

  private func hmacSHA256(key: Data, data: Data) -> Data {
    var result = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
    key.withUnsafeBytes { keyBytes in
      data.withUnsafeBytes { dataBytes in
        result.withUnsafeMutableBytes { resultBytes in
          CCHmac(
            CCHmacAlgorithm(kCCHmacAlgSHA256),
            keyBytes.baseAddress, key.count,
            dataBytes.baseAddress, data.count,
            resultBytes.baseAddress)
        }
      }
    }
    return result
  }

  private func hmacSHA256Hex(key: Data, data: Data) -> String {
    hmacSHA256(key: key, data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func sha256Hex(_ data: Data) -> String {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
    return hash.map { String(format: "%02x", $0) }.joined()
  }
}

// MARK: - BedrockRequestBuilder

@available(anyAppleOS 27, *)
enum BedrockRequestBuilder {
  static func build(from request: LanguageModelExecutorGenerationRequest) throws -> [String: Any] {
    var systemParts: [String] = []
    var messages: [[String: Any]] = []

    for entry in request.transcript {
      switch entry {
      case .instructions(let i):
        let text = textOf(i.segments)
        if !text.isEmpty { systemParts.append(text) }

      case .prompt(let p):
        let content = contentBlocks(from: p.segments)
        if !content.isEmpty {
          messages.append(["role": "user", "content": content])
        }

      case .response(let r):
        let content = contentBlocks(from: r.segments)
        if !content.isEmpty {
          messages.append(["role": "assistant", "content": content])
        }

      case .toolCalls(let calls):
        var content: [[String: Any]] = []
        for call in calls {
          let inputDict =
            (try? JSONSerialization.jsonObject(with: Data(call.arguments.jsonString.utf8)))
            as? [String: Any] ?? [:]
          content.append([
            "toolUse": [
              "toolUseId": call.id,
              "name": call.toolName,
              "input": inputDict,
            ]
          ])
        }
        if !content.isEmpty {
          messages.append(["role": "assistant", "content": content])
        }

      case .toolOutput(let out):
        let text = textOf(out.segments)
        messages.append([
          "role": "user",
          "content": [
            [
              "toolResult": [
                "toolUseId": out.id,
                "content": [["text": text.isEmpty ? "(no output)" : text]],
              ]
            ]
          ],
        ])

      case .reasoning(let r):
        // Send the thinking block back on the next turn; its signature has to be replayed with it.
        let thinkingText = textOf(r.segments)
        var reasoningText: [String: Any] = ["text": thinkingText]
        if let sig = r.signature {
          reasoningText["signature"] = sig.base64EncodedString()
        }
        messages.append([
          "role": "assistant",
          "content": [["reasoningContent": ["reasoningText": reasoningText]]],
        ])

      @unknown default:
        break
      }
    }

    messages = BedrockPayload.mergeConsecutiveSameRole(messages)

    var body: [String: Any] = ["messages": messages]

    // Only send inferenceConfig when the framework asked for a limit; otherwise let Bedrock apply
    // its own default, since overshooting maxTokens makes it answer 503.
    if let maxTokens = request.generationOptions.maximumResponseTokens {
      body["inferenceConfig"] = ["maxTokens": maxTokens]
    }

    if !systemParts.isEmpty {
      body["system"] = [["text": systemParts.joined(separator: "\n\n")]]
    }

    let tools = request.enabledToolDefinitions.compactMap { toolSpec(from: $0) }
    if !tools.isEmpty {
      body["toolConfig"] = ["tools": tools]
    }

    return body
  }

  // MARK: - Private helpers

  private static func textOf(_ segments: [Transcript.Segment]) -> String {
    segments.compactMap { segment -> String? in
      switch segment {
      case .text(let t): return t.content.isEmpty ? nil : t.content
      case .structure(let s): return s.content.jsonString
      case .attachment: return nil
      @unknown default: return nil
      }
    }.joined(separator: "\n")
  }

  private static func contentBlocks(from segments: [Transcript.Segment]) -> [[String: Any]] {
    segments.compactMap { segment -> [String: Any]? in
      switch segment {
      case .text(let t) where !t.content.isEmpty: return ["text": t.content]
      case .structure(let s): return ["text": s.content.jsonString]
      default: return nil
      }
    }
  }

  private static func toolSpec(from def: Transcript.ToolDefinition) -> [String: Any]? {
    guard let schemaData = try? JSONEncoder().encode(def.parameters),
      let schemaRaw = (try? JSONSerialization.jsonObject(with: schemaData)) as? [String: Any]
    else { return nil }

    return [
      "toolSpec": [
        "name": def.name,
        "description": def.description,
        "inputSchema": ["json": BedrockPayload.sanitizeSchema(schemaRaw)],
      ]
    ]
  }
}

// MARK: - BedrockPayload

/// Pure transformations on the Converse request payload. Kept outside
/// `BedrockRequestBuilder` so they carry no availability constraint and can be
/// exercised without FoundationModels.
enum BedrockPayload {
  /// Strips the JSON Schema keys Bedrock rejects (`x-order`, `title`, and the like).
  static func sanitizeSchema(_ value: Any) -> Any {
    // additionalProperties is left out: the Converse API does not accept it.
    let allowed: Set<String> = [
      "type", "properties", "required", "items", "enum", "const",
      "anyOf", "allOf", "oneOf", "$ref", "$defs", "definitions",
      "description", "format",
    ]
    let mapValuedKeys: Set<String> = ["properties", "$defs", "definitions"]

    if let dict = value as? [String: Any] {
      var out: [String: Any] = [:]
      for (key, val) in dict where allowed.contains(key) {
        if mapValuedKeys.contains(key), let nested = val as? [String: Any] {
          out[key] = nested.mapValues { sanitizeSchema($0) }
        } else {
          out[key] = sanitizeSchema(val)
        }
      }
      return out
    } else if let arr = value as? [Any] {
      return arr.map { sanitizeSchema($0) }
    } else {
      return value
    }
  }

  static func mergeConsecutiveSameRole(
    _ messages: [[String: Any]]
  ) -> [[String: Any]] {
    var out: [[String: Any]] = []
    for message in messages {
      guard let role = message["role"] as? String,
        let content = message["content"] as? [[String: Any]]
      else {
        out.append(message)
        continue
      }
      if var last = out.last,
        (last["role"] as? String) == role,
        var lastContent = last["content"] as? [[String: Any]]
      {
        lastContent.append(contentsOf: content)
        last["content"] = lastContent
        out[out.count - 1] = last
      } else {
        out.append(message)
      }
    }
    return out
  }
}

// MARK: - Errors

enum BedrockError: Error, LocalizedError {
  case missingCredentials
  case invalidURL(String)
  case httpError(Int, String)
  case invalidResponse(String)

  var errorDescription: String? {
    switch self {
    case .missingCredentials:
      return
        "Missing AWS credentials. Provide either a Bedrock API key or an access key ID and secret access key."
    case .invalidURL(let url): return "Invalid Bedrock URL: \(url)"
    case .httpError(let code, let body): return "Bedrock HTTP error \(code): \(body)"
    case .invalidResponse(let msg): return "Bedrock invalid response: \(msg)"
    }
  }
}
