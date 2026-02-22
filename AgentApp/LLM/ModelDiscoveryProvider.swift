// ModelDiscoveryProvider.swift
// AgentApp
//
// Defines the protocol and concrete implementations for dynamic LLM model
// discovery. Providers fetch available models from their respective APIs
// (or return curated lists) and map them into [LLMModel].
//
// Architecture Decision: Each provider encapsulates its own discovery logic
// (network call for OpenAI, static list for Claude) behind a uniform protocol.
// This enables the ModelRegistry to refresh models per-provider without
// coupling to any specific API shape. Providers are injected via
// DependencyContainer, preserving testability and separation of concerns.
//
// Security: API keys are read from KeychainService at call time and never
// logged. Errors are typed without including sensitive data.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Discovery Error

/// Errors specific to model discovery operations.
enum ModelDiscoveryError: Error, Sendable, LocalizedError {
    case noAPIKey
    case networkError(String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured for this provider."
        case .networkError(let detail):
            return "Network error during model discovery: \(detail)"
        case .decodingError(let detail):
            return "Failed to decode model list: \(detail)"
        }
    }
}

// MARK: - Discovery Protocol

/// Abstraction for fetching the list of available models from an LLM provider.
/// Implementations may call a remote API or return a static curated list.
protocol ModelDiscoveryProvider: Sendable {
    /// The provider type this discovery provider serves.
    var providerType: LLMProviderType { get }

    /// Fetches the current list of models from this provider.
    func fetchModels() async throws -> [LLMModel]
}

// MARK: - OpenAI Model Discovery

/// Discovers available models from the OpenAI API by calling GET /v1/models.
/// Filters results to include only chat-capable models (id starts with "gpt-")
/// and excludes embeddings, audio-only, moderation, and system models.
///
/// Architecture Decision: Uses @Sendable closure for API key retrieval,
/// consistent with the existing provider pattern (OpenAIProvider).
/// URLSession with async/await is used for the network call.
struct OpenAIModelDiscoveryProvider: ModelDiscoveryProvider {
    let providerType: LLMProviderType = .openAI

    private let apiKeyProvider: @Sendable () -> String?
    private let baseURL: URL

    #if !os(Linux)
    private let session: URLSession

    init(
        apiKeyProvider: @escaping @Sendable () -> String?,
        baseURL: URL = URL(string: "https://api.openai.com")!,
        session: URLSession = .shared
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.baseURL = baseURL
        self.session = session
    }
    #else
    init(
        apiKeyProvider: @escaping @Sendable () -> String?,
        baseURL: URL = URL(string: "https://api.openai.com")!
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.baseURL = baseURL
    }
    #endif

    func fetchModels() async throws -> [LLMModel] {
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            print("[ModelDiscovery] No OpenAI API key available")
            throw ModelDiscoveryError.noAPIKey
        }

        #if os(Linux)
        print("[ModelDiscovery] Network discovery not supported on Linux")
        throw ModelDiscoveryError.networkError("Not supported on this platform")
        #else
        let url = baseURL.appendingPathComponent("/v1/models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            print("[ModelDiscovery] OpenAI network request failed: \(error.localizedDescription)")
            throw ModelDiscoveryError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelDiscoveryError.networkError("Invalid response type")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data.prefix(500), encoding: .utf8) ?? "unknown"
            print("[ModelDiscovery] OpenAI API returned HTTP \(httpResponse.statusCode)")
            throw ModelDiscoveryError.networkError("HTTP \(httpResponse.statusCode): \(body)")
        }

        // Decode the response safely
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelList = json["data"] as? [[String: Any]] else {
            throw ModelDiscoveryError.decodingError("Unexpected response structure")
        }

        let models: [LLMModel] = modelList.compactMap { modelObj in
            guard let id = modelObj["id"] as? String else { return nil }

            // Only include models that pass the Responses API-capable filter
            guard Self.isChatCapableModel(id) else { return nil }

            let endpoint = Self.determineEndpoint(id)
            let displayName = Self.formatDisplayName(id)
            return LLMModel(
                id: id,
                displayName: displayName,
                provider: .openAI,
                supportsTools: true,
                supportsVision: id.contains("4o") || id.contains("4.1") || id.contains("4-turbo")
                    || id.contains("gpt-5"),
                maxContextTokens: Self.estimateContextWindow(id),
                supportedEndpoint: endpoint,
                usesMaxCompletionTokens: endpoint == .responses
            )
        }
        .sorted { Self.modelSortOrder($0.id) < Self.modelSortOrder($1.id) }

        print("[ModelDiscovery] OpenAI: discovered \(models.count) chat models")
        return models
        #endif
    }

    // MARK: - Filtering

    /// Returns true if the model ID represents a Responses API-capable model.
    /// Excludes legacy (gpt-4* and lower), non-chat, and deprecated models.
    /// Excludes gpt-4o* (Chat Completions only). Includes o-series models.
    static func isChatCapableModel(_ id: String) -> Bool {
        let lowered = id.lowercased()

        // Allow o-series models (o3, o4-mini, etc.) — they support the Responses API
        if lowered.hasPrefix("o3") || lowered.hasPrefix("o4-") { return true }

        // Must start with "gpt-" for remaining checks
        guard lowered.hasPrefix("gpt-") else { return false }

        // Exclude legacy models: gpt-3.5*, gpt-4-*, gpt-4 exact, gpt-4o*
        if lowered.hasPrefix("gpt-3") { return false }
        // gpt-4 exact or gpt-4-<variant> (not gpt-4.1)
        if lowered.hasPrefix("gpt-4-") || lowered == "gpt-4" { return false }
        // gpt-4o* — Chat Completions only
        if lowered.hasPrefix("gpt-4o") { return false }

        // Exclude non-chat model types by substring
        let excludedSubstrings = [
            "embedding", "audio", "tts", "whisper", "moderation",
            "instruct", "vision-preview", "realtime", "transcribe", "search"
        ]
        for excluded in excludedSubstrings {
            if lowered.contains(excluded) { return false }
        }

        return true
    }

    // MARK: - Endpoint Mapping

    /// Determines the correct OpenAI API endpoint for a model based on its ID.
    /// All exposed models use the Responses API.
    static func determineEndpoint(_ id: String) -> OpenAIEndpointType {
        return .responses
    }

    // MARK: - Sorting

    /// Returns a numeric sort key so newer/higher models sort first.
    static func modelSortOrder(_ id: String) -> Int {
        let lowered = id.lowercased()
        if lowered.hasPrefix("o4-") { return 0 }
        if lowered.hasPrefix("o3") { return 1 }
        if lowered.hasPrefix("gpt-5") { return 2 }
        if lowered.hasPrefix("gpt-4.1") { return 3 }
        if lowered.hasPrefix("gpt-4o") { return 4 }
        return 5
    }

    // MARK: - Helpers

    /// Formats a model ID into a human-readable display name.
    static func formatDisplayName(_ id: String) -> String {
        id.split(separator: "-")
            .map { segment in
                let s = String(segment)
                // Capitalize known abbreviations
                if s.lowercased() == "gpt" { return "GPT" }
                if s.lowercased() == "mini" { return "Mini" }
                if s.lowercased() == "turbo" { return "Turbo" }
                return s.prefix(1).uppercased() + s.dropFirst()
            }
            .joined(separator: "-")
    }

    /// Estimates context window based on known model ID patterns.
    static func estimateContextWindow(_ id: String) -> Int {
        let lowered = id.lowercased()
        if lowered.contains("gpt-5") { return 1_000_000 }
        if lowered.contains("4.1") { return 1_000_000 }
        if lowered.hasPrefix("o3") || lowered.hasPrefix("o4-") { return 200_000 }
        if lowered.contains("4o") { return 128_000 }
        if lowered.contains("4-turbo") { return 128_000 }
        if lowered.contains("gpt-4") { return 128_000 }
        if lowered.contains("gpt-3.5") { return 16_385 }
        return 128_000
    }
}

// MARK: - Claude Model Discovery

/// Returns a curated list of modern Claude models without network calls.
/// Anthropic does not currently offer a public model listing API, so this
/// provider returns a maintained static list.
///
/// Architecture Decision: Easily replaceable with a real network discovery
/// implementation if Anthropic adds a models endpoint in the future.
struct ClaudeModelDiscoveryProvider: ModelDiscoveryProvider {
    let providerType: LLMProviderType = .anthropic

    func fetchModels() async throws -> [LLMModel] {
        let models = [
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
        print("[ModelDiscovery] Claude: returning \(models.count) curated models")
        return models
    }
}
