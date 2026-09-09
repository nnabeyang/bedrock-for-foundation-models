import Foundation

/// Who authored a message in the conversation.
public enum ConversationRole: String, Sendable, Hashable, Codable {
  case user
  case assistant
}

/// One turn of the conversation, as `messages[]` carries it.
public struct ConverseMessage: Sendable, Hashable, Codable {
  public var role: ConversationRole
  public var content: [ConverseContentBlock]

  public init(role: ConversationRole, content: [ConverseContentBlock]) {
    self.role = role
    self.content = content
  }

  public static func user(_ text: String) -> ConverseMessage {
    .init(role: .user, content: [.text(text)])
  }

  public static func assistant(_ text: String) -> ConverseMessage {
    .init(role: .assistant, content: [.text(text)])
  }
}

extension [ConverseMessage] {
  /// Folds consecutive same-role messages into one, with the content blocks
  /// concatenated in order. Converse requires the roles to alternate, and the
  /// framework's transcript readily produces two model entries in a row.
  public func mergingConsecutiveSameRole() -> [ConverseMessage] {
    var out: [ConverseMessage] = []
    for message in self {
      if out.last?.role == message.role {
        out[out.count - 1].content.append(contentsOf: message.content)
      } else {
        out.append(message)
      }
    }
    return out
  }
}
