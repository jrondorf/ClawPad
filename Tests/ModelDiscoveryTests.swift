// ModelDiscoveryTests.swift
// AgentAppTests
//
// Tests for ModelDiscoveryProvider protocol, OpenAIModelDiscoveryProvider,
// ClaudeModelDiscoveryProvider, and ModelRegistry dynamic refresh.

import XCTest
@testable import AgentApp

// MARK: - Mock Discovery Provider

/// A configurable mock for testing ModelRegistry refresh logic.
private struct MockDiscoveryProvider: ModelDiscoveryProvider {
    let providerType: LLMProviderType
    let result: Result<[LLMModel], Error>

    func fetchModels() async throws -> [LLMModel] {
        switch result {
        case .success(let models):
            return models
        case .failure(let error):
            throw error
        }
    }
}

// MARK: - Claude Discovery Tests

final class ClaudeModelDiscoveryTests: XCTestCase {

    func testClaudeDiscoveryReturnsModels() async throws {
        let provider = ClaudeModelDiscoveryProvider()
        let models = try await provider.fetchModels()
        XCTAssertGreaterThan(models.count, 0)
    }

    func testClaudeDiscoveryProviderType() {
        let provider = ClaudeModelDiscoveryProvider()
        XCTAssertEqual(provider.providerType, .anthropic)
    }

    func testClaudeDiscoveryAllModelsAreAnthropic() async throws {
        let provider = ClaudeModelDiscoveryProvider()
        let models = try await provider.fetchModels()
        for model in models {
            XCTAssertEqual(model.provider, .anthropic)
        }
    }

    func testClaudeDiscoveryContainsExpectedModels() async throws {
        let provider = ClaudeModelDiscoveryProvider()
        let models = try await provider.fetchModels()
        let ids = models.map { $0.id }
        XCTAssertTrue(ids.contains("claude-3.5-sonnet"))
        XCTAssertTrue(ids.contains("claude-3.7-sonnet"))
        XCTAssertTrue(ids.contains("claude-opus-4"))
        XCTAssertTrue(ids.contains("claude-opus-4.6"))
    }
}

// MARK: - OpenAI Discovery Tests

final class OpenAIModelDiscoveryTests: XCTestCase {

    func testOpenAIDiscoveryProviderType() {
        let provider = OpenAIModelDiscoveryProvider(apiKeyProvider: { "test-key" })
        XCTAssertEqual(provider.providerType, .openAI)
    }

    func testOpenAIDiscoveryThrowsWithNoKey() async {
        let provider = OpenAIModelDiscoveryProvider(apiKeyProvider: { nil })
        do {
            _ = try await provider.fetchModels()
            XCTFail("Expected error when no API key is available")
        } catch let error as ModelDiscoveryError {
            if case .noAPIKey = error {
                // Expected
            } else {
                XCTFail("Expected noAPIKey error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testOpenAIDiscoveryThrowsWithEmptyKey() async {
        let provider = OpenAIModelDiscoveryProvider(apiKeyProvider: { "" })
        do {
            _ = try await provider.fetchModels()
            XCTFail("Expected error when API key is empty")
        } catch let error as ModelDiscoveryError {
            if case .noAPIKey = error {
                // Expected
            } else {
                XCTFail("Expected noAPIKey error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFormatDisplayName() {
        XCTAssertEqual(OpenAIModelDiscoveryProvider.formatDisplayName("gpt-4o"), "GPT-4o")
        XCTAssertEqual(OpenAIModelDiscoveryProvider.formatDisplayName("gpt-4o-mini"), "GPT-4o-Mini")
        XCTAssertEqual(OpenAIModelDiscoveryProvider.formatDisplayName("gpt-4-turbo"), "GPT-4-Turbo")
    }

    func testEstimateContextWindow() {
        XCTAssertEqual(OpenAIModelDiscoveryProvider.estimateContextWindow("gpt-4.1"), 1_000_000)
        XCTAssertEqual(OpenAIModelDiscoveryProvider.estimateContextWindow("gpt-4o"), 128_000)
        XCTAssertEqual(OpenAIModelDiscoveryProvider.estimateContextWindow("gpt-4o-mini"), 128_000)
        XCTAssertEqual(OpenAIModelDiscoveryProvider.estimateContextWindow("gpt-4-turbo"), 128_000)
        XCTAssertEqual(OpenAIModelDiscoveryProvider.estimateContextWindow("gpt-3.5-turbo"), 16_385)
    }

    // MARK: - Chat Capability Filtering Tests

    func testIsChatCapableAllowsModernModels() {
        XCTAssertTrue(OpenAIModelDiscoveryProvider.isChatCapableModel("gpt-4o"))
        XCTAssertTrue(OpenAIModelDiscoveryProvider.isChatCapableModel("gpt-4o-mini"))
        XCTAssertTrue(OpenAIModelDiscoveryProvider.isChatCapableModel("gpt-4.1"))
        XCTAssertTrue(OpenAIModelDiscoveryProvider.isChatCapableModel("gpt-4.1-mini"))
        XCTAssertTrue(OpenAIModelDiscoveryProvider.isChatCapableModel("gpt-4.1-turbo"))
        XCTAssertTrue(OpenAIModelDiscoveryProvider.isChatCapableModel("gpt-5"))
        XCTAssertTrue(OpenAIModelDiscoveryProvider.isChatCapableModel("gpt-5-turbo"))
    }

    func testIsChatCapableExcludesLegacyModels() {
        XCTAssertFalse(OpenAIModelDiscoveryProvider.isChatCapableModel("gpt-4"))
        XCTAssertFalse(OpenAIModelDiscoveryProvider.isChatCapableModel("gpt-4-turbo"))
        XCTAssertFalse(OpenAIModelDiscoveryProvider.isChatCapableModel("gpt-4-0613"))
        XCTAssertFalse(OpenAIModelDiscoveryProvider.isChatCapableModel("gpt-3.5-turbo"))
        XCTAssertFalse(OpenAIModelDiscoveryProvider.isChatCapableModel("gpt-3.5-turbo-16k"))
    }

    func testIsChatCapableExcludesNonChatModels() {
        XCTAssertFalse(OpenAIModelDiscoveryProvider.isChatCapableModel("text-embedding-ada-002"))
        XCTAssertFalse(OpenAIModelDiscoveryProvider.isChatCapableModel("tts-1"))
        XCTAssertFalse(OpenAIModelDiscoveryProvider.isChatCapableModel("whisper-1"))
        XCTAssertFalse(OpenAIModelDiscoveryProvider.isChatCapableModel("dall-e-3"))
        XCTAssertFalse(OpenAIModelDiscoveryProvider.isChatCapableModel("davinci-002"))
    }

    func testIsChatCapableExcludesExcludedSubstrings() {
        XCTAssertFalse(OpenAIModelDiscoveryProvider.isChatCapableModel("gpt-4o-realtime-preview"))
        XCTAssertFalse(OpenAIModelDiscoveryProvider.isChatCapableModel("gpt-4o-audio-preview"))
        XCTAssertFalse(OpenAIModelDiscoveryProvider.isChatCapableModel("gpt-4o-transcribe"))
        XCTAssertFalse(OpenAIModelDiscoveryProvider.isChatCapableModel("gpt-4-vision-preview"))
    }

    // MARK: - Endpoint Mapping Tests

    func testDetermineEndpointForResponsesAPI() {
        XCTAssertEqual(OpenAIModelDiscoveryProvider.determineEndpoint("gpt-4.1"), .responses)
        XCTAssertEqual(OpenAIModelDiscoveryProvider.determineEndpoint("gpt-4.1-mini"), .responses)
        XCTAssertEqual(OpenAIModelDiscoveryProvider.determineEndpoint("gpt-4.1-turbo"), .responses)
        XCTAssertEqual(OpenAIModelDiscoveryProvider.determineEndpoint("gpt-5"), .responses)
        XCTAssertEqual(OpenAIModelDiscoveryProvider.determineEndpoint("gpt-5-turbo"), .responses)
    }

    func testDetermineEndpointForChatCompletions() {
        XCTAssertEqual(OpenAIModelDiscoveryProvider.determineEndpoint("gpt-4o"), .chatCompletions)
        XCTAssertEqual(OpenAIModelDiscoveryProvider.determineEndpoint("gpt-4o-mini"), .chatCompletions)
    }

    // MARK: - Sort Order Tests

    func testModelSortOrderNewerFirst() {
        let gpt5 = OpenAIModelDiscoveryProvider.modelSortOrder("gpt-5")
        let gpt41 = OpenAIModelDiscoveryProvider.modelSortOrder("gpt-4.1")
        let gpt4o = OpenAIModelDiscoveryProvider.modelSortOrder("gpt-4o")

        XCTAssertLessThan(gpt5, gpt41)
        XCTAssertLessThan(gpt41, gpt4o)
    }
}

// MARK: - ModelRegistry Refresh Tests

final class ModelRegistryRefreshTests: XCTestCase {

    func testRegistryWithDiscoveryProviders() {
        let mockProvider = MockDiscoveryProvider(
            providerType: .openAI,
            result: .success([
                LLMModel(id: "gpt-new", displayName: "GPT New", provider: .openAI,
                         supportsTools: true, supportsVision: true, maxContextTokens: 128_000)
            ])
        )
        let registry = ModelRegistry(discoveryProviders: [mockProvider])
        // Should still have defaults initially
        XCTAssertGreaterThan(registry.models.count, 0)
    }

    func testRefreshReplacesModelsForProvider() async throws {
        let newModels = [
            LLMModel(id: "gpt-test-1", displayName: "Test 1", provider: .openAI,
                     supportsTools: true, supportsVision: false, maxContextTokens: 8_000),
            LLMModel(id: "gpt-test-2", displayName: "Test 2", provider: .openAI,
                     supportsTools: false, supportsVision: true, maxContextTokens: 16_000),
        ]
        let mockProvider = MockDiscoveryProvider(providerType: .openAI, result: .success(newModels))
        let registry = ModelRegistry(discoveryProviders: [mockProvider])

        try await registry.refreshModels(for: .openAI, force: true)

        let openAIModels = registry.models(for: .openAI)
        XCTAssertEqual(openAIModels.count, 2)
        XCTAssertEqual(openAIModels.map { $0.id }, ["gpt-test-1", "gpt-test-2"])
    }

    func testRefreshDoesNotAffectOtherProvider() async throws {
        let newModels = [
            LLMModel(id: "gpt-test-1", displayName: "Test 1", provider: .openAI,
                     supportsTools: true, supportsVision: false, maxContextTokens: 8_000),
        ]
        let mockProvider = MockDiscoveryProvider(providerType: .openAI, result: .success(newModels))
        let registry = ModelRegistry(discoveryProviders: [mockProvider])

        let anthropicBefore = registry.models(for: .anthropic)
        try await registry.refreshModels(for: .openAI, force: true)
        let anthropicAfter = registry.models(for: .anthropic)

        XCTAssertEqual(anthropicBefore.map { $0.id }, anthropicAfter.map { $0.id })
    }

    func testRefreshErrorPropagates() async {
        let mockProvider = MockDiscoveryProvider(
            providerType: .openAI,
            result: .failure(ModelDiscoveryError.noAPIKey)
        )
        let registry = ModelRegistry(discoveryProviders: [mockProvider])

        do {
            try await registry.refreshModels(for: .openAI, force: true)
            XCTFail("Expected error to propagate")
        } catch {
            XCTAssertTrue(error is ModelDiscoveryError)
        }
    }

    func testRefreshSkipsWhenCacheFresh() async throws {
        let counter = CallCounter()
        let mockProvider = CountingDiscoveryProvider(
            providerType: .openAI,
            counter: counter,
            models: [
                LLMModel(id: "gpt-counted", displayName: "Counted", provider: .openAI,
                         supportsTools: true, supportsVision: true, maxContextTokens: 128_000)
            ]
        )
        let registry = ModelRegistry(discoveryProviders: [mockProvider], cacheTTL: 300)

        // First call should fetch
        try await registry.refreshModels(for: .openAI, force: true)
        let count1 = await counter.count
        XCTAssertEqual(count1, 1)

        // Second call without force should skip (cache is fresh)
        try await registry.refreshModels(for: .openAI, force: false)
        let count2 = await counter.count
        XCTAssertEqual(count2, 1)
    }

    func testRefreshWithNoProviderIsNoOp() async throws {
        let registry = ModelRegistry()
        // Should not throw when no provider registered for the type
        try await registry.refreshModels(for: .openAI, force: true)

        // Models should remain as defaults
        let openAI = registry.models(for: .openAI)
        XCTAssertGreaterThan(openAI.count, 0)
    }

    func testRefreshPreservesModelsOnEmptyResult() async throws {
        let mockProvider = MockDiscoveryProvider(providerType: .openAI, result: .success([]))
        let registry = ModelRegistry(discoveryProviders: [mockProvider])

        let before = registry.models(for: .openAI)
        try await registry.refreshModels(for: .openAI, force: true)
        let after = registry.models(for: .openAI)

        // Empty result should not replace existing models
        XCTAssertEqual(before.map { $0.id }, after.map { $0.id })
    }
}

// MARK: - ModelDiscoveryError Tests

final class ModelDiscoveryErrorTests: XCTestCase {

    func testNoAPIKeyDescription() {
        let error = ModelDiscoveryError.noAPIKey
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("API key"))
    }

    func testNetworkErrorDescription() {
        let error = ModelDiscoveryError.networkError("timeout")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("timeout"))
    }

    func testDecodingErrorDescription() {
        let error = ModelDiscoveryError.decodingError("bad json")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("bad json"))
    }
}

// MARK: - Helper: Call Counter (actor for thread-safe counting)

private actor CallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

/// A discovery provider that counts how many times fetchModels is called.
private struct CountingDiscoveryProvider: ModelDiscoveryProvider {
    let providerType: LLMProviderType
    let counter: CallCounter
    let models: [LLMModel]

    func fetchModels() async throws -> [LLMModel] {
        await counter.increment()
        return models
    }
}
