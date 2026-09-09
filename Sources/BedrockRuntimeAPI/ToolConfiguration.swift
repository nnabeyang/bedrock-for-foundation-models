import Foundation

/// The tools the model may call, and how freely it may call them.
public struct ToolConfiguration: Sendable, Hashable, Codable {
  public var tools: [ConverseTool]
  public var toolChoice: ToolChoice?

  public init(tools: [ConverseTool], toolChoice: ToolChoice? = nil) {
    self.tools = tools
    self.toolChoice = toolChoice
  }
}

/// One entry of `toolConfig.tools`. Bedrock also accepts `systemTool` and
/// `cachePoint` here; those decode as ``other``.
public enum ConverseTool: Sendable, Hashable, Codable {
  case toolSpec(ToolSpecification)
  case other(JSONValue)

  private enum CodingKeys: String, CodingKey {
    case toolSpec
  }

  public init(from decoder: Decoder) throws {
    guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
      self = .other(try JSONValue(from: decoder))
      return
    }
    if let spec = try c.decodeIfPresent(ToolSpecification.self, forKey: .toolSpec) {
      self = .toolSpec(spec)
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
    case .toolSpec(let spec): try c.encode(spec, forKey: .toolSpec)
    case .other: break
    }
  }
}

/// A tool the caller runs: its name, what it does, and the schema of its input.
public struct ToolSpecification: Sendable, Hashable, Codable {
  public var name: String
  public var description: String?
  public var inputSchema: ToolInputSchema

  public init(name: String, description: String? = nil, inputSchema: ToolInputSchema) {
    self.name = name
    self.description = description
    self.inputSchema = inputSchema
  }
}

/// The tool's input schema. Only the `json` form exists today.
public enum ToolInputSchema: Sendable, Hashable, Codable {
  case json(JSONValue)
  case other(JSONValue)

  private enum CodingKeys: String, CodingKey {
    case json
  }

  public init(from decoder: Decoder) throws {
    guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
      self = .other(try JSONValue(from: decoder))
      return
    }
    if let schema = try c.decodeIfPresent(JSONValue.self, forKey: .json) {
      self = .json(schema)
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
    case .json(let schema): try c.encode(schema, forKey: .json)
    case .other: break
    }
  }
}

/// How the model picks a tool. `auto` and `any` carry no fields, but the API
/// still expects an object — `{"auto": {}}`, never `{"auto": null}`.
public enum ToolChoice: Sendable, Hashable, Codable {
  /// The model decides whether to call a tool.
  case auto
  /// The model must call some tool.
  case any
  /// The model must call this tool.
  case tool(name: String)

  private enum CodingKeys: String, CodingKey {
    case auto, any, tool
  }

  private struct Empty: Sendable, Hashable, Codable {}

  private struct SpecificToolChoice: Sendable, Hashable, Codable {
    var name: String
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if c.contains(.auto) {
      self = .auto
    } else if c.contains(.any) {
      self = .any
    } else if let tool = try c.decodeIfPresent(SpecificToolChoice.self, forKey: .tool) {
      self = .tool(name: tool.name)
    } else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: c.codingPath, debugDescription: "Unknown toolChoice")
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .auto: try c.encode(Empty(), forKey: .auto)
    case .any: try c.encode(Empty(), forKey: .any)
    case .tool(let name): try c.encode(SpecificToolChoice(name: name), forKey: .tool)
    }
  }
}
