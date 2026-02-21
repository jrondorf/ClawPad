// AgentMessage.swift
// AgentApp
//
// Defines the core message types used throughout the agent runtime.
// Messages are value types (structs) for thread safety and conform to
// Codable for persistence in the conversation store.

import Foundation

// MARK: - Message Role

/// Represents the role of a participant in a conversation.
/// Mirrors the role taxonomy used by frontier LLM APIs (OpenAI, Claude).
enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

// MARK: - Tool Call

/// Represents a tool invocation requested by the LLM.
/// The LLM returns a tool call with an ID, function name, and JSON arguments.
struct ToolCall: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let arguments: String // JSON-encoded arguments from the LLM

    /// Parses the JSON arguments string into a dictionary.
    func decodedArguments() throws -> [String: Any] {
        guard let data = arguments.data(using: .utf8) else {
            throw AgentError.invalidToolArguments("Arguments string is not valid UTF-8")
        }
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentError.invalidToolArguments("Arguments are not a JSON object")
        }
        return dict
    }
}

// MARK: - Tool Result

/// Represents the result of executing a tool, returned to the LLM.
struct ToolResult: Codable, Sendable {
    let toolCallID: String
    let content: String
    let isError: Bool

    init(toolCallID: String, content: String, isError: Bool = false) {
        self.toolCallID = toolCallID
        self.content = content
        self.isError = isError
    }
}

// MARK: - Agent Message

/// A single message in a conversation, supporting text, tool calls, and tool results.
/// This is the canonical message format used by the agent runtime, conversation store,
/// and context assembler.
struct AgentMessage: Codable, Sendable, Identifiable {
    let id: UUID
    let sessionID: UUID
    let role: MessageRole
    let content: String?
    let toolCalls: [ToolCall]?
    let toolResult: ToolResult?
    let timestamp: Date
    let tokenCount: Int?

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        role: MessageRole,
        content: String? = nil,
        toolCalls: [ToolCall]? = nil,
        toolResult: ToolResult? = nil,
        timestamp: Date = Date(),
        tokenCount: Int? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolResult = toolResult
        self.timestamp = timestamp
        self.tokenCount = tokenCount
    }
}

// MARK: - Streaming Event

/// Events emitted during streaming response generation.
/// The UI observes these to render tokens incrementally and display tool activity.
enum StreamEvent: Sendable {
    case token(String)
    case toolCallStart(ToolCall)
    case toolResult(ToolResult)
    case done(AgentMessage)
    case error(AgentError)
}

// MARK: - Agent Error

/// Errors that can occur during agent operation.
enum AgentError: Error, Sendable, LocalizedError {
    case llmRequestFailed(String)
    case toolNotFound(String)
    case toolExecutionFailed(String)
    case invalidToolArguments(String)
    case contextWindowExceeded(Int)
    case networkError(String)
    case authenticationFailed
    case cancelled
    case serializationFailed(String)

    var errorDescription: String? {
        switch self {
        case .llmRequestFailed(let detail):
            return "LLM request failed: \(detail)"
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        case .toolExecutionFailed(let detail):
            return "Tool execution failed: \(detail)"
        case .invalidToolArguments(let detail):
            return "Invalid tool arguments: \(detail)"
        case .contextWindowExceeded(let tokens):
            return "Context window exceeded: \(tokens) tokens"
        case .networkError(let detail):
            return "Network error: \(detail)"
        case .authenticationFailed:
            return "Authentication failed. Please check your API key."
        case .cancelled:
            return "Operation was cancelled."
        case .serializationFailed(let detail):
            return "Serialization failed: \(detail)"
        }
    }
}

// MARK: - Session

/// Represents a conversation session.
struct ConversationSession: Codable, Sendable, Identifiable {
    let id: UUID
    let title: String
    let createdAt: Date
    var updatedAt: Date
    let agentConfigID: String?

    init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        agentConfigID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.agentConfigID = agentConfigID
    }
}
