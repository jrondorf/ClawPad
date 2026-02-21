// TokenManager.swift
// AgentApp
//
// Manages token counting and context window truncation.
// Ensures the assembled context stays within the LLM's token limit
// by applying a sliding window strategy that preserves the system prompt
// and most recent messages.
//
// Architecture Decision: Token counting uses a character-based heuristic
// (≈4 chars per token for English text) since exact tokenization requires
// model-specific tokenizers. For production, integrate tiktoken or the
// provider's native tokenizer.

import Foundation

// MARK: - Token Manager

struct TokenManager: Sendable {
    /// Maximum tokens allowed in the context window.
    let maxContextTokens: Int

    /// Reserved tokens for the system prompt.
    let systemPromptReserve: Int

    /// Reserved tokens for the LLM's response.
    let responseReserve: Int

    /// Approximate characters per token (heuristic for English text).
    private let charsPerToken: Double = 4.0

    init(
        maxContextTokens: Int = 128_000,
        systemPromptReserve: Int = 2_000,
        responseReserve: Int = 4_096
    ) {
        self.maxContextTokens = maxContextTokens
        self.systemPromptReserve = systemPromptReserve
        self.responseReserve = responseReserve
    }

    /// Available tokens for conversation messages after reserves.
    var availableMessageTokens: Int {
        return maxContextTokens - systemPromptReserve - responseReserve
    }

    /// Estimates the token count for a string.
    func estimateTokens(for text: String) -> Int {
        return max(1, Int(ceil(Double(text.count) / charsPerToken)))
    }

    /// Estimates the token count for an agent message.
    func estimateTokens(for message: AgentMessage) -> Int {
        var tokens = 4 // Message overhead (role, separators)
        if let content = message.content {
            tokens += estimateTokens(for: content)
        }
        if let toolCalls = message.toolCalls {
            for call in toolCalls {
                tokens += estimateTokens(for: call.name)
                tokens += estimateTokens(for: call.arguments)
                tokens += 10 // Tool call structure overhead
            }
        }
        if let result = message.toolResult {
            tokens += estimateTokens(for: result.content)
            tokens += 10 // Tool result structure overhead
        }
        return tokens
    }

    /// Truncates a message array to fit within the available token budget.
    /// Preserves the most recent messages and any system messages.
    ///
    /// Strategy:
    /// 1. Always keep system messages (they are part of the system prompt reserve).
    /// 2. Keep the most recent messages that fit in the budget.
    /// 3. If a tool call and its result are split, keep both or neither.
    func truncateToFit(messages: [AgentMessage]) -> [AgentMessage] {
        let budget = availableMessageTokens

        // Separate system messages from conversation messages
        let systemMessages = messages.filter { $0.role == .system }
        let conversationMessages = messages.filter { $0.role != .system }

        var selected: [AgentMessage] = []
        var usedTokens = 0

        // Walk backwards from most recent, adding messages that fit
        for message in conversationMessages.reversed() {
            let cost = estimateTokens(for: message)
            if usedTokens + cost <= budget {
                selected.insert(message, at: 0)
                usedTokens += cost
            } else {
                break // Stop once we exceed budget
            }
        }

        // Ensure tool call / tool result pairs are intact
        selected = ensureToolCallPairIntegrity(selected)

        return systemMessages + selected
    }

    /// Ensures that tool calls and their results are not split.
    /// If a tool result exists without its tool call, remove the orphaned result.
    private func ensureToolCallPairIntegrity(_ messages: [AgentMessage]) -> [AgentMessage] {
        var toolCallIDs = Set<String>()

        // Collect all tool call IDs present in assistant messages
        for message in messages {
            if let calls = message.toolCalls {
                for call in calls {
                    toolCallIDs.insert(call.id)
                }
            }
        }

        // Filter out orphaned tool results
        return messages.filter { message in
            if let result = message.toolResult {
                return toolCallIDs.contains(result.toolCallID)
            }
            return true
        }
    }
}
