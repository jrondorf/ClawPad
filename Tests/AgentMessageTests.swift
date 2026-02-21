// AgentMessageTests.swift
// AgentAppTests
//
// Tests for the core message types and token management.

import XCTest
@testable import AgentApp

final class AgentMessageTests: XCTestCase {

    // MARK: - AgentMessage Tests

    func testMessageCreation() {
        let sessionID = UUID()
        let message = AgentMessage(
            sessionID: sessionID,
            role: .user,
            content: "Hello"
        )

        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.content, "Hello")
        XCTAssertEqual(message.sessionID, sessionID)
        XCTAssertNil(message.toolCalls)
        XCTAssertNil(message.toolResult)
    }

    func testToolCallDecoding() throws {
        let call = ToolCall(
            id: "call_1",
            name: "calculator",
            arguments: "{\"operation\":\"add\",\"a\":1,\"b\":2}"
        )

        let args = try call.decodedArguments()
        XCTAssertEqual(args["operation"] as? String, "add")
        XCTAssertEqual(args["a"] as? Int, 1)
        XCTAssertEqual(args["b"] as? Int, 2)
    }

    func testToolCallInvalidJSON() {
        let call = ToolCall(
            id: "call_1",
            name: "test",
            arguments: "not json"
        )

        XCTAssertThrowsError(try call.decodedArguments())
    }

    func testToolResultCreation() {
        let result = ToolResult(toolCallID: "call_1", content: "42")
        XCTAssertEqual(result.toolCallID, "call_1")
        XCTAssertEqual(result.content, "42")
        XCTAssertFalse(result.isError)

        let errorResult = ToolResult(toolCallID: "call_2", content: "Error", isError: true)
        XCTAssertTrue(errorResult.isError)
    }

    func testConversationSession() {
        let session = ConversationSession(title: "Test Session")
        XCTAssertEqual(session.title, "Test Session")
        XCTAssertNil(session.agentConfigID)
    }

    // MARK: - TokenManager Tests

    func testTokenEstimation() {
        let manager = TokenManager()

        // ~4 chars per token heuristic
        let tokens = manager.estimateTokens(for: "Hello, world!")
        XCTAssertGreaterThan(tokens, 0)
        XCTAssertEqual(tokens, 4) // 13 chars / 4 ≈ 4 tokens
    }

    func testTokenTruncation() {
        let manager = TokenManager(
            maxContextTokens: 100,
            systemPromptReserve: 10,
            responseReserve: 10
        )
        let sessionID = UUID()

        // Create many messages that exceed the budget
        var messages: [AgentMessage] = []
        for i in 0..<50 {
            messages.append(AgentMessage(
                sessionID: sessionID,
                role: i % 2 == 0 ? .user : .assistant,
                content: "Message number \(i) with some additional text to increase token count."
            ))
        }

        let truncated = manager.truncateToFit(messages: messages)
        XCTAssertLessThan(truncated.count, messages.count)
        // Last message should be preserved
        XCTAssertEqual(truncated.last?.content, messages.last?.content)
    }

    func testSystemMessagesPreserved() {
        let manager = TokenManager(
            maxContextTokens: 200,
            systemPromptReserve: 50,
            responseReserve: 50
        )
        let sessionID = UUID()

        let messages = [
            AgentMessage(sessionID: sessionID, role: .system, content: "You are helpful."),
            AgentMessage(sessionID: sessionID, role: .user, content: "Hello"),
            AgentMessage(sessionID: sessionID, role: .assistant, content: "Hi there!")
        ]

        let result = manager.truncateToFit(messages: messages)
        let systemMessages = result.filter { $0.role == .system }
        XCTAssertEqual(systemMessages.count, 1)
    }

    // MARK: - ContextAssembler Tests

    func testContextAssembly() {
        let assembler = ContextAssembler()
        let config = AgentConfiguration(systemPrompt: "Be helpful")
        let sessionID = UUID()

        let history = [
            AgentMessage(sessionID: sessionID, role: .user, content: "Hello"),
            AgentMessage(sessionID: sessionID, role: .assistant, content: "Hi!")
        ]

        let result = assembler.assemble(configuration: config, history: history)

        // Should have system + user + assistant = 3 messages
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.first?.role, .system)
        XCTAssertEqual(result.first?.content, "Be helpful")
    }

    // MARK: - Extension Tests

    func testStringTrimmed() {
        XCTAssertEqual("  hello  ".trimmed, "hello")
        XCTAssertEqual("".trimmed, "")
    }

    func testStringIsBlank() {
        XCTAssertTrue("".isBlank)
        XCTAssertTrue("   ".isBlank)
        XCTAssertFalse("hello".isBlank)
    }

    func testStringTruncated() {
        XCTAssertEqual("Hello, World!".truncated(to: 5), "Hello…")
        XCTAssertEqual("Hi".truncated(to: 5), "Hi")
    }

    func testStringSanitized() {
        let input = "Hello\0World"
        let sanitized = input.sanitized
        XCTAssertFalse(sanitized.contains("\0"))
    }

    func testSafeSubscript() {
        let array = [1, 2, 3]
        XCTAssertEqual(array[safe: 0], 1)
        XCTAssertNil(array[safe: 5])
    }
}
