import Foundation
import Testing

@testable import BedrockForFoundationModels
@testable import BedrockRuntimeAPI

// `LanguageModelExecutorGenerationChannel` can't be constructed outside the
// framework, so `ConverseResponseTranslator.send` isn't unit-testable; its
// stop-reason gate is factored out so it can be.

@available(anyAppleOS 27, *)
private func response(
  _ stopReason: StopReason?,
  content: [ConverseContentBlock]
) -> ConverseResponse {
  ConverseResponse(
    output: .message(ConverseMessage(role: .assistant, content: content)),
    stopReason: stopReason
  )
}

@Suite("ConverseResponseTranslator stop-reason gate")
struct ConverseResponseTranslatorStopReasonTests {
  @available(anyAppleOS 27, *)
  @Test("lets a normal end_turn through")
  func passesEndTurn() throws {
    let r = response(.endTurn, content: [.text("done")])
    try ConverseResponseTranslator.throwIfStopReasonUnusable(r, message: r.output.message!)
  }

  @available(anyAppleOS 27, *)
  @Test("lets a tool_use turn through")
  func passesToolUse() throws {
    let block = ConverseContentBlock.toolUse(
      .init(toolUseId: "t", name: "x", input: .object([:])))
    let r = response(.toolUse, content: [block])
    try ConverseResponseTranslator.throwIfStopReasonUnusable(r, message: r.output.message!)
  }

  @available(anyAppleOS 27, *)
  @Test("throws on a content-filtered turn with nothing usable")
  func throwsOnEmptyContentFiltered() {
    let r = response(.contentFiltered, content: [])
    #expect(throws: BedrockError.self) {
      try ConverseResponseTranslator.throwIfStopReasonUnusable(r, message: r.output.message!)
    }
  }

  @available(anyAppleOS 27, *)
  @Test("leaves a hard stop alone when the message still carries text")
  func keepsHardStopWithContent() throws {
    let r = response(.guardrailIntervened, content: [.text("partial but usable")])
    try ConverseResponseTranslator.throwIfStopReasonUnusable(r, message: r.output.message!)
  }

  @available(anyAppleOS 27, *)
  @Test("maps model_context_window_exceeded to the phrase eich resets on")
  func mapsContextWindowExceeded() {
    let r = response(.modelContextWindowExceeded, content: [.text("truncated")])
    do {
      try ConverseResponseTranslator.throwIfStopReasonUnusable(r, message: r.output.message!)
      Issue.record("expected a throw")
    } catch {
      // eich's BedrockAgentBackend matches on `(error as NSError).localizedDescription`
      // to trigger its session reset — assert that exact accessor, not just
      // `errorDescription`.
      #expect(
        (error as NSError).localizedDescription
          .contains("exceeds the maximum allowed context size"))
    }
  }
}
