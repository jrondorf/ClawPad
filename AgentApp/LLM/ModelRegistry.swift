// ModelRegistry.swift
// AgentApp
//
// Provides the catalogue of available LLM models grouped by provider.
// New models can be added here without changing UI or provider logic.
//
// Architecture Decision: The registry is a class (not a singleton)
// injected through DependencyContainer. It supports both static defaults
// and dynamic model discovery via ModelDiscoveryProvider. Discovered
// models are cached in memory with freshness tracking to avoid redundant
// network calls. The registry uses an actor-like locking strategy via
// NSLock to remain Sendable while supporting mutable cached state.

import Foundation

// MARK: - Model Registry

final class ModelRegistry: @unchecked Sendable {
    /// Discovery providers keyed by provider type, injected at init.
    private let discoveryProviders: [LLMProviderType: ModelDiscoveryProvider]

    /// Cache freshness interval in seconds (5 minutes).
    private let cacheTTL: TimeInterval

    /// Lock protecting mutable cached state.
    private let lock = NSLock()

    /// Cached models per provider, populated by discovery or defaults.
    private var cachedModels: [LLMProviderType: [LLMModel]]

    /// Timestamps of last successful fetch per provider.
    private var lastFetchTimes: [LLMProviderType: Date] = [:]

    /// The combined list of all models across providers.
    var models: [LLMModel] {
        lock.lock()
        defer { lock.unlock() }
        return LLMProviderType.allCases.flatMap { cachedModels[$0] ?? [] }
    }

    /// Creates a registry with optional discovery providers and initial models.
    /// Falls back to built-in defaults when no initial models are provided.
    init(
        models: [LLMModel]? = nil,
        discoveryProviders: [ModelDiscoveryProvider] = [],
        cacheTTL: TimeInterval = 300
    ) {
        let initial = models ?? Self.defaultModels()
        self.cachedModels = Dictionary(grouping: initial, by: { $0.provider })
        self.discoveryProviders = Dictionary(
            uniqueKeysWithValues: discoveryProviders.map { ($0.providerType, $0) }
        )
        self.cacheTTL = cacheTTL
    }

    /// Returns models for a specific provider, preserving insertion order.
    func models(for provider: LLMProviderType) -> [LLMModel] {
        lock.lock()
        defer { lock.unlock() }
        return cachedModels[provider] ?? []
    }

    /// Groups all models by provider.
    var modelsByProvider: [LLMProviderType: [LLMModel]] {
        lock.lock()
        defer { lock.unlock() }
        return cachedModels
    }

    // MARK: - Dynamic Refresh

    /// Refreshes models for a specific provider using its discovery provider.
    /// Skips refresh if the cache is still fresh (within cacheTTL).
    /// Does not block UI — designed to be called from an async context.
    func refreshModels(for provider: LLMProviderType, force: Bool = false) async throws {
        guard let discoveryProvider = discoveryProviders[provider] else {
            print("[ModelRegistry] No discovery provider registered for \(provider.rawValue)")
            return
        }

        // Check cache freshness (synchronous helper avoids lock-in-async warning)
        if !force && isCacheFresh(for: provider) {
            print("[ModelRegistry] Cache still fresh for \(provider.rawValue), skipping refresh")
            return
        }

        let fetchedModels = try await discoveryProvider.fetchModels()
        applyFetchedModels(fetchedModels, for: provider)

        print("[ModelRegistry] Updated \(provider.rawValue) with \(fetchedModels.count) models")
    }

    /// Returns true if cached models for the provider are still within TTL.
    private func isCacheFresh(for provider: LLMProviderType) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let lastFetch = lastFetchTimes[provider] else { return false }
        return Date().timeIntervalSince(lastFetch) < cacheTTL
    }

    /// Stores fetched models and updates the timestamp under the lock.
    private func applyFetchedModels(_ models: [LLMModel], for provider: LLMProviderType) {
        lock.lock()
        defer { lock.unlock() }
        if !models.isEmpty {
            cachedModels[provider] = models
        }
        lastFetchTimes[provider] = Date()
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
