import Foundation

/// A single block within a message's `content` array.
///
/// Converse unions carry no `type` discriminator: the block is an object with
/// exactly one member key naming the variant (`{"text": …}`,
/// `{"toolUse": {…}}`). Decoding therefore probes the known keys in turn and
/// keeps anything else as ``other``, so a block type this package doesn't model
/// — `document`, `cachePoint`, `citationsContent` and whatever Bedrock adds
/// next — round-trips untouched instead of failing the response or losing its
/// payload on the way back.
public enum ConverseContentBlock: Sendable, Hashable, Codable {
  case text(String)
  case image(ImageBlock)
  case toolUse(ToolUseBlock)
  case toolResult(ToolResultBlock)
  case reasoningContent(ReasoningContentBlock)
  case other(JSONValue)

  private enum CodingKeys: String, CodingKey {
    case text, image, toolUse, toolResult, reasoningContent
  }

  public init(from decoder: Decoder) throws {
    guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
      self = .other(try JSONValue(from: decoder))
      return
    }
    if let text = try c.decodeIfPresent(String.self, forKey: .text) {
      self = .text(text)
    } else if let block = try c.decodeIfPresent(ImageBlock.self, forKey: .image) {
      self = .image(block)
    } else if let block = try c.decodeIfPresent(ToolUseBlock.self, forKey: .toolUse) {
      self = .toolUse(block)
    } else if let block = try c.decodeIfPresent(ToolResultBlock.self, forKey: .toolResult) {
      self = .toolResult(block)
    } else if let block = try c.decodeIfPresent(
      ReasoningContentBlock.self, forKey: .reasoningContent)
    {
      self = .reasoningContent(block)
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
    case .text(let text): try c.encode(text, forKey: .text)
    case .image(let block): try c.encode(block, forKey: .image)
    case .toolUse(let block): try c.encode(block, forKey: .toolUse)
    case .toolResult(let block): try c.encode(block, forKey: .toolResult)
    case .reasoningContent(let block): try c.encode(block, forKey: .reasoningContent)
    case .other: break  // written above, without the keyed container
    }
  }
}

// MARK: - Image

/// An image the model looks at. The bytes travel inline, base64 on the wire,
/// which is how `JSONEncoder` writes `Data` by default.
///
/// Converse takes at most 3.75 MB per image, 8000 pixels a side and 20 images
/// a request; the service answers 400 past those, so a caller that builds
/// blocks by hand has to size the image first. The FoundationModels bridge
/// does that in `ImageAttachmentEncoder`.
public struct ImageBlock: Sendable, Hashable, Codable {
  public enum Format: String, Sendable, Hashable, Codable {
    case png, jpeg, gif, webp
  }

  public struct Source: Sendable, Hashable, Codable {
    public var bytes: Data

    public init(bytes: Data) {
      self.bytes = bytes
    }
  }

  public var format: Format
  public var source: Source

  public init(format: Format, bytes: Data) {
    self.format = format
    self.source = Source(bytes: bytes)
  }
}

// MARK: - Tool use

/// A tool call the model wants run. `input` is shaped by the tool's own JSON
/// Schema, so it stays loosely typed.
public struct ToolUseBlock: Sendable, Hashable, Codable {
  public var toolUseId: String
  public var name: String
  public var input: JSONValue

  public init(toolUseId: String, name: String, input: JSONValue) {
    self.toolUseId = toolUseId
    self.name = name
    self.input = input
  }
}

/// The result of a tool call, sent back on the following turn.
public struct ToolResultBlock: Sendable, Hashable, Codable {
  public enum Status: String, Sendable, Hashable, Codable {
    case success
    case error
  }

  public var toolUseId: String
  public var content: [ToolResultContentBlock]
  public var status: Status?

  public init(toolUseId: String, content: [ToolResultContentBlock], status: Status? = nil) {
    self.toolUseId = toolUseId
    self.content = content
    self.status = status
  }
}

/// One block of a tool result. Bedrock also accepts `document`, `video` and
/// `searchResult` here; those decode as ``other``.
public enum ToolResultContentBlock: Sendable, Hashable, Codable {
  case text(String)
  case json(JSONValue)
  case image(ImageBlock)
  case other(JSONValue)

  private enum CodingKeys: String, CodingKey {
    case text, json, image
  }

  public init(from decoder: Decoder) throws {
    guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
      self = .other(try JSONValue(from: decoder))
      return
    }
    if let text = try c.decodeIfPresent(String.self, forKey: .text) {
      self = .text(text)
    } else if let json = try c.decodeIfPresent(JSONValue.self, forKey: .json) {
      self = .json(json)
    } else if let block = try c.decodeIfPresent(ImageBlock.self, forKey: .image) {
      self = .image(block)
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
    case .text(let text): try c.encode(text, forKey: .text)
    case .json(let json): try c.encode(json, forKey: .json)
    case .image(let block): try c.encode(block, forKey: .image)
    case .other: break
    }
  }
}

// MARK: - Reasoning

/// The chain of thought a reasoning model produces alongside its answer.
public enum ReasoningContentBlock: Sendable, Hashable, Codable {
  case reasoningText(ReasoningTextBlock)
  /// Reasoning the service withheld. Opaque bytes; replay it verbatim.
  case redactedContent(Data)
  case other(JSONValue)

  private enum CodingKeys: String, CodingKey {
    case reasoningText, redactedContent
  }

  public init(from decoder: Decoder) throws {
    guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
      self = .other(try JSONValue(from: decoder))
      return
    }
    if let block = try c.decodeIfPresent(ReasoningTextBlock.self, forKey: .reasoningText) {
      self = .reasoningText(block)
    } else if let data = try c.decodeIfPresent(Data.self, forKey: .redactedContent) {
      self = .redactedContent(data)
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
    case .reasoningText(let block): try c.encode(block, forKey: .reasoningText)
    case .redactedContent(let data): try c.encode(data, forKey: .redactedContent)
    case .other: break
    }
  }
}

/// A thought and the signature that authenticates it. The signature has to be
/// replayed with the thought on the next turn, or the API rejects the request.
public struct ReasoningTextBlock: Sendable, Hashable, Codable {
  public var text: String
  /// Opaque on the wire — a string, not the framework's signature bytes.
  public var signature: String?

  public init(text: String, signature: String? = nil) {
    self.text = text
    self.signature = signature
  }
}
