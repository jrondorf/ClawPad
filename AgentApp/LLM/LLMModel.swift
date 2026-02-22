// LLMModel.swift
// AgentApp
//
// Defines the model descriptor and provider type used throughout the app.
// Models are identified by string IDs rather than SDK enums, enabling
// future-proof model additions without code changes.
//
// Architecture Decision: Using a struct with string-based IDs instead of
// an enum allows new models to be added via ModelRegistry (or eventually
// remote discovery) without modifying UI or provider logic.

import Foundation

// MARK: - LLM Provider Type

/// Identifies the LLM provider backend. Used to group models in the UI
/// and route requests to the correct provider implementation.
enum LLMProviderType: String, Codable, Sendable, CaseIterable {
    case openAI = "OpenAI"
    case anthropic = "Claude"
}

// MARK: - OpenAI Endpoint Type

/// Identifies which OpenAI API endpoint a model supports.
/// Newer models (gpt-4.1+, gpt-5+) use the Responses API;
/// older chat models use Chat Completions.
enum OpenAIEndpointType: String, Codable, Sendable {
    case chatCompletions = "Chat API"
    case responses = "Responses API"
}

// MARK: - LLM Model

/// Describes an available LLM model with its capabilities.
/// Treated as a value type for safe use across concurrency boundaries.
struct LLMModel: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let provider: LLMProviderType
    let supportsTools: Bool
    let supportsVision: Bool
    let maxContextTokens: Int
    /// The OpenAI API endpoint this model requires. Defaults to `.chatCompletions` for non-OpenAI providers.
    let supportedEndpoint: OpenAIEndpointType
    /// Whether this model uses `max_completion_tokens` instead of `max_tokens`.
    let usesMaxCompletionTokens: Bool

    init(
        id: String,
        displayName: String,
        provider: LLMProviderType,
        supportsTools: Bool,
        supportsVision: Bool,
        maxContextTokens: Int,
        supportedEndpoint: OpenAIEndpointType = .chatCompletions,
        usesMaxCompletionTokens: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.provider = provider
        self.supportsTools = supportsTools
        self.supportsVision = supportsVision
        self.maxContextTokens = maxContextTokens
        self.supportedEndpoint = supportedEndpoint
        self.usesMaxCompletionTokens = usesMaxCompletionTokens
    }
}
