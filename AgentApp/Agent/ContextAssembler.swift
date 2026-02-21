// ContextAssembler.swift
// AgentApp
//
// Assembles the message context sent to the LLM by combining
// the system prompt, conversation history, and token management.
//
// Architecture Decision: The ContextAssembler is a pure function object
// (no mutable state) that takes messages in and returns truncated messages out.
// This makes it easily testable and composable.

import Foundation

// MARK: - Agent Configuration

/// Configuration for an agent profile, supporting multi-agent extensibility.
struct AgentConfiguration: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let systemPrompt: String
    let model: String
    let maxTokens: Int
    let temperature: Double
    let enabledTools: [String]?

    init(
        id: String = "default",
        name: String = "Assistant",
        systemPrompt: String = "You are a helpful AI assistant running on an iPad. You can use tools when needed to help answer questions. Be concise and helpful.",
        model: String = "claude-sonnet-4-20250514",
        maxTokens: Int = 4096,
        temperature: Double = 0.7,
        enabledTools: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.model = model
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.enabledTools = enabledTools
    }

    /// Converts to LLMConfiguration for the provider.
    var llmConfiguration: LLMConfiguration {
        LLMConfiguration(
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            systemPrompt: systemPrompt
        )
    }
}

// MARK: - Context Assembler

struct ContextAssembler: Sendable {
    let tokenManager: TokenManager

    init(tokenManager: TokenManager = TokenManager()) {
        self.tokenManager = tokenManager
    }

    /// Assembles the full message context for an LLM request.
    ///
    /// - Parameters:
    ///   - configuration: The agent configuration with system prompt.
    ///   - history: The conversation history for the session.
    ///   - pendingToolResults: Any tool results to append.
    /// - Returns: An array of messages ready to send to the LLM.
    func assemble(
        configuration: AgentConfiguration,
        history: [AgentMessage],
        pendingToolResults: [AgentMessage] = []
    ) -> [AgentMessage] {
        // Build the system message
        let systemMessage = AgentMessage(
            sessionID: history.first?.sessionID ?? UUID(),
            role: .system,
            content: configuration.systemPrompt
        )

        // Combine history with any pending tool results
        var allMessages = history + pendingToolResults

        // Prepend system message
        allMessages.insert(systemMessage, at: 0)

        // Apply token truncation
        return tokenManager.truncateToFit(messages: allMessages)
    }
}
