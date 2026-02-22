// ModelRegistry.swift
// AgentApp
//
// Provides the catalogue of available LLM models grouped by provider.
// New models can be added here without changing UI or provider logic.
//
// Architecture Decision: The registry is a simple class (not a singleton)
// injected through DependencyContainer. It can later be replaced with
// remote model discovery by conforming to the same interface.

import Foundation

// MARK: - Model Registry

final class ModelRegistry: Sendable {
    let models: [LLMModel]

    init(models: [LLMModel]? = nil) {
        self.models = models ?? Self.defaultModels()
    }

    /// Returns models for a specific provider, preserving insertion order.
    func models(for provider: LLMProviderType) -> [LLMModel] {
        models.filter { $0.provider == provider }
    }

    /// Groups all models by provider.
    var modelsByProvider: [LLMProviderType: [LLMModel]] {
        Dictionary(grouping: models, by: { $0.provider })
    }

    // MARK: - Default Model Catalogue

    /// The built-in set of models. Update this list when new models are released.
    static func defaultModels() -> [LLMModel] {
        [
            // OpenAI models
            LLMModel(
                id: "gpt-4.1",
                displayName: "GPT-4.1",
                provider: .openAI,
                supportsTools: true,
                supportsVision: true,
                maxContextTokens: 1_000_000
            ),
            LLMModel(
                id: "gpt-4.1-mini",
                displayName: "GPT-4.1 Mini",
                provider: .openAI,
                supportsTools: true,
                supportsVision: true,
                maxContextTokens: 1_000_000
            ),
            LLMModel(
                id: "gpt-4.1-turbo",
                displayName: "GPT-4.1 Turbo",
                provider: .openAI,
                supportsTools: true,
                supportsVision: true,
                maxContextTokens: 1_000_000
            ),
            LLMModel(
                id: "gpt-4o",
                displayName: "GPT-4o",
                provider: .openAI,
                supportsTools: true,
                supportsVision: true,
                maxContextTokens: 128_000
            ),
            LLMModel(
                id: "gpt-4o-mini",
                displayName: "GPT-4o Mini",
                provider: .openAI,
                supportsTools: true,
                supportsVision: true,
                maxContextTokens: 128_000
            ),

            // Anthropic models
            LLMModel(
                id: "claude-3.5-sonnet",
                displayName: "Claude 3.5 Sonnet",
                provider: .anthropic,
                supportsTools: true,
                supportsVision: true,
                maxContextTokens: 200_000
            ),
            LLMModel(
                id: "claude-3.7-sonnet",
                displayName: "Claude 3.7 Sonnet",
                provider: .anthropic,
                supportsTools: true,
                supportsVision: true,
                maxContextTokens: 200_000
            ),
            LLMModel(
                id: "claude-opus-4",
                displayName: "Claude Opus 4",
                provider: .anthropic,
                supportsTools: true,
                supportsVision: true,
                maxContextTokens: 200_000
            ),
            LLMModel(
                id: "claude-opus-4.6",
                displayName: "Claude Opus 4.6",
                provider: .anthropic,
                supportsTools: true,
                supportsVision: true,
                maxContextTokens: 200_000
            ),
        ]
    }
}
