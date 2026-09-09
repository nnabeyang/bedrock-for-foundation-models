import Foundation
import Testing

@testable import BedrockRuntimeAPI

@Suite("mergingConsecutiveSameRole")
struct MergingConsecutiveSameRoleTests {
  @Test("merges the content of adjacent messages sharing a role")
  func mergesAdjacentSameRole() {
    let merged: [ConverseMessage] = [
      .init(role: .user, content: [.text("a")]),
      .init(role: .user, content: [.text("b")]),
      .init(role: .assistant, content: [.text("c")]),
    ].mergingConsecutiveSameRole()

    #expect(
      merged == [
        .init(role: .user, content: [.text("a"), .text("b")]),
        .init(role: .assistant, content: [.text("c")]),
      ])
  }

  @Test("keeps messages separate when the roles alternate")
  func keepsAlternatingRolesSeparate() {
    let messages: [ConverseMessage] = [
      .init(role: .user, content: [.text("a")]),
      .init(role: .assistant, content: [.text("b")]),
      .init(role: .user, content: [.text("c")]),
    ]

    #expect(messages.mergingConsecutiveSameRole() == messages)
  }

  @Test("returns an empty array unchanged")
  func handlesEmptyInput() {
    #expect([ConverseMessage]().mergingConsecutiveSameRole().isEmpty)
  }
}
