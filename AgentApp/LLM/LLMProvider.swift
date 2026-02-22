// LLMProvider.swift
// AgentApp
//
// Abstract protocol defining the interface for LLM backends.
// Concrete implementations (ClaudeProvider, OpenAIProvider) conform to this protocol.
// The protocol uses AsyncThrowingStream for streaming token delivery,
// enabling real-time UI updates and cancellation support.

import Foundation

// MARK: - LLM Configuration

/// Configuration for an LLM provider instance.
struct LLMConfiguration: Codable, Sendable {
    let model: String
    let maxTokens: Int
    let temperature: Double
    let topP: Double?
    let systemPrompt: String?
    let supportsTemperature: Bool

    init(
        model: String,
        maxTokens: Int = 4096,
        temperature: Double = 0.7,
        topP: Double? = nil,
        systemPrompt: String? = nil,
        supportsTemperature: Bool = true
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.systemPrompt = systemPrompt
        self.supportsTemperature = supportsTemperature
    }
}

// MARK: - Tool Definition

/// JSON-schema-based tool definition sent to the LLM.
/// Mirrors the function/tool calling format used by OpenAI and Claude APIs.
struct ToolDefinition: Codable, Sendable {
    let name: String
    let description: String
    let parameters: ToolParameters

    struct ToolParameters: Codable, Sendable {
        let type: String
        let properties: [String: ParameterProperty]
        let required: [String]?

        init(
            type: String = "object",
            properties: [String: ParameterProperty],
            required: [String]? = nil
        ) {
            self.type = type
            self.properties = properties
            self.required = required
        }
    }

    struct ParameterProperty: Codable, Sendable {
        let type: String
        let description: String?
        let enumValues: [String]?

        enum CodingKeys: String, CodingKey {
            case type
            case description
            case enumValues = "enum"
        }
    }
}

// MARK: - LLM Response

/// A complete (non-streaming) response from the LLM.
struct LLMResponse: Sendable {
    let content: String?
    let toolCalls: [ToolCall]
    let finishReason: FinishReason
    let usage: TokenUsage?

    enum FinishReason: String, Sendable {
        case stop
        case toolUse = "tool_use"
        case maxTokens = "max_tokens"
        case error
    }

    struct TokenUsage: Sendable {
        let promptTokens: Int
        let completionTokens: Int
        var totalTokens: Int { promptTokens + completionTokens }
    }
}

// MARK: - LLM Provider Protocol

/// Abstract interface for LLM providers.
/// Implementations must be Sendable for use across actor boundaries.
///
/// Architecture Decision: Using a protocol instead of a base class enables
/// easy testing via mock providers and supports future local LLM integration
/// without modifying existing code (Open/Closed Principle).
protocol LLMProvider: Sendable {
    /// A human-readable name for this provider (e.g., "Claude", "OpenAI").
    var providerName: String { get }

    /// The list of available model identifiers.
    var availableModels: [String] { get }

    /// Sends messages to the LLM and returns a streaming response.
    ///
    /// - Parameters:
    ///   - messages: The conversation history to send.
    ///   - tools: Tool definitions the LLM may invoke.
    ///   - configuration: Model and generation parameters.
    /// - Returns: An async throwing stream of `StreamEvent` values.
    func streamCompletion(
        messages: [AgentMessage],
        tools: [ToolDefinition],
        configuration: LLMConfiguration
    ) -> AsyncThrowingStream<StreamEvent, Error>

    /// Sends messages to the LLM and returns a complete response.
    /// Default implementation collects streamed events into a single response.
    ///
    /// - Parameters:
    ///   - messages: The conversation history to send.
    ///   - tools: Tool definitions the LLM may invoke.
    ///   - configuration: Model and generation parameters.
    /// - Returns: A complete `LLMResponse`.
    func completion(
        messages: [AgentMessage],
        tools: [ToolDefinition],
        configuration: LLMConfiguration
    ) async throws -> LLMResponse
}

// MARK: - Default Implementation

extension LLMProvider {
    /// Default non-streaming completion that collects stream events.
    func completion(
        messages: [AgentMessage],
        tools: [ToolDefinition],
        configuration: LLMConfiguration
    ) async throws -> LLMResponse {
        var contentParts: [String] = []
        var toolCalls: [ToolCall] = []

        for try await event in streamCompletion(messages: messages, tools: tools, configuration: configuration) {
            switch event {
            case .token(let text):
                contentParts.append(text)
            case .toolCallStart(let call):
                toolCalls.append(call)
            case .error(let error):
                throw error
            case .done, .toolResult:
                break
            }
        }

        let content = contentParts.isEmpty ? nil : contentParts.joined()
        let finishReason: LLMResponse.FinishReason = toolCalls.isEmpty ? .stop : .toolUse
        return LLMResponse(content: content, toolCalls: toolCalls, finishReason: finishReason, usage: nil)
    }
}
