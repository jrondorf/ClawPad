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
}
