// ModelRegistryTests.swift
// AgentAppTests
//
// Tests for LLMModel, LLMProviderType, and ModelRegistry.

import XCTest
@testable import AgentApp

final class ModelRegistryTests: XCTestCase {

    // MARK: - LLMModel Tests

    func testModelIdentifiable() {
        let model = LLMModel(
            id: "gpt-4o",
            displayName: "GPT-4o",
            provider: .openAI,
            supportsTools: true,
            supportsVision: true,
            maxContextTokens: 128_000
        )
        XCTAssertEqual(model.id, "gpt-4o")
        XCTAssertEqual(model.displayName, "GPT-4o")
        XCTAssertEqual(model.provider, .openAI)
        XCTAssertTrue(model.supportsTools)
        XCTAssertTrue(model.supportsVision)
        XCTAssertEqual(model.maxContextTokens, 128_000)
    }

    func testModelHashable() {
        let model1 = LLMModel(
            id: "gpt-4o",
            displayName: "GPT-4o",
            provider: .openAI,
            supportsTools: true,
            supportsVision: true,
            maxContextTokens: 128_000
        )
        let model2 = LLMModel(
            id: "gpt-4o",
            displayName: "GPT-4o",
            provider: .openAI,
            supportsTools: true,
            supportsVision: true,
            maxContextTokens: 128_000
        )
        XCTAssertEqual(model1, model2)

        var set = Set<LLMModel>()
        set.insert(model1)
        set.insert(model2)
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - LLMProviderType Tests

    func testProviderTypeRawValues() {
        XCTAssertEqual(LLMProviderType.openAI.rawValue, "OpenAI")
        XCTAssertEqual(LLMProviderType.anthropic.rawValue, "Claude")
    }

    func testProviderTypeCaseIterable() {
        let allCases = LLMProviderType.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.openAI))
        XCTAssertTrue(allCases.contains(.anthropic))
    }

    // MARK: - ModelRegistry Tests

    func testDefaultModelsExist() {
        let registry = ModelRegistry()
        XCTAssertGreaterThan(registry.models.count, 0)
    }

    func testDefaultModelsContainOpenAI() {
        let registry = ModelRegistry()
        let openAIModels = registry.models(for: .openAI)
        XCTAssertGreaterThan(openAIModels.count, 0)

        let ids = openAIModels.map { $0.id }
        XCTAssertTrue(ids.contains("gpt-4.1"))
        XCTAssertTrue(ids.contains("gpt-4.1-mini"))
        XCTAssertTrue(ids.contains("gpt-4.1-turbo"))
        XCTAssertTrue(ids.contains("gpt-4o"))
        XCTAssertTrue(ids.contains("gpt-4o-mini"))
    }

    func testDefaultModelsContainAnthropic() {
        let registry = ModelRegistry()
        let anthropicModels = registry.models(for: .anthropic)
        XCTAssertGreaterThan(anthropicModels.count, 0)

        let ids = anthropicModels.map { $0.id }
        XCTAssertTrue(ids.contains("claude-3.5-sonnet"))
        XCTAssertTrue(ids.contains("claude-3.7-sonnet"))
        XCTAssertTrue(ids.contains("claude-opus-4"))
        XCTAssertTrue(ids.contains("claude-opus-4.6"))
    }

    func testModelsGroupedByProvider() {
        let registry = ModelRegistry()
        let grouped = registry.modelsByProvider

        XCTAssertNotNil(grouped[.openAI])
        XCTAssertNotNil(grouped[.anthropic])

        // All models in each group should belong to the correct provider
        for model in grouped[.openAI] ?? [] {
            XCTAssertEqual(model.provider, .openAI)
        }
        for model in grouped[.anthropic] ?? [] {
            XCTAssertEqual(model.provider, .anthropic)
        }
    }

    func testCustomModelRegistry() {
        let customModels = [
            LLMModel(
                id: "custom-model",
                displayName: "Custom",
                provider: .openAI,
                supportsTools: false,
                supportsVision: false,
                maxContextTokens: 4_096
            )
        ]
        let registry = ModelRegistry(models: customModels)
        XCTAssertEqual(registry.models.count, 1)
        XCTAssertEqual(registry.models.first?.id, "custom-model")
    }

    func testFilterByProviderReturnsEmpty() {
        let customModels = [
            LLMModel(
                id: "gpt-4o",
                displayName: "GPT-4o",
                provider: .openAI,
                supportsTools: true,
                supportsVision: true,
                maxContextTokens: 128_000
            )
        ]
        let registry = ModelRegistry(models: customModels)
        let anthropicModels = registry.models(for: .anthropic)
        XCTAssertTrue(anthropicModels.isEmpty)
    }

    func testAllModelsAreStrings() {
        let registry = ModelRegistry()
        // Verify all model IDs are non-empty strings (not enum cases)
        for model in registry.models {
            XCTAssertFalse(model.id.isEmpty)
            XCTAssertFalse(model.displayName.isEmpty)
        }
    }

    // MARK: - Endpoint Metadata Tests

    func testOpenAIEndpointTypeRawValues() {
        XCTAssertEqual(OpenAIEndpointType.chatCompletions.rawValue, "Chat API")
        XCTAssertEqual(OpenAIEndpointType.responses.rawValue, "Responses API")
    }

    func testDefaultModelsHaveCorrectEndpoints() {
        let registry = ModelRegistry()
        let openAIModels = registry.models(for: .openAI)

        for model in openAIModels {
            if model.id.hasPrefix("gpt-4.1") {
                XCTAssertEqual(model.supportedEndpoint, .responses,
                               "\(model.id) should use Responses API")
                XCTAssertTrue(model.usesMaxCompletionTokens,
                              "\(model.id) should use max_completion_tokens")
            } else if model.id.hasPrefix("gpt-4o") {
                XCTAssertEqual(model.supportedEndpoint, .chatCompletions,
                               "\(model.id) should use Chat Completions")
                XCTAssertFalse(model.usesMaxCompletionTokens,
                               "\(model.id) should use max_tokens")
            }
        }
    }

    func testLLMModelDefaultEndpoint() {
        // Models created without specifying endpoint should default to chatCompletions
        let model = LLMModel(
            id: "test-model",
            displayName: "Test",
            provider: .anthropic,
            supportsTools: false,
            supportsVision: false,
            maxContextTokens: 4_096
        )
        XCTAssertEqual(model.supportedEndpoint, .chatCompletions)
        XCTAssertFalse(model.usesMaxCompletionTokens)
    }

    // MARK: - supportsTemperature Tests

    func testLLMModelDefaultSupportsTemperature() {
        // Models created without specifying supportsTemperature should default to true
        let model = LLMModel(
            id: "test-model",
            displayName: "Test",
            provider: .openAI,
            supportsTools: true,
            supportsVision: false,
            maxContextTokens: 128_000
        )
        XCTAssertTrue(model.supportsTemperature)
    }

    func testLLMModelSupportsTemperatureFalse() {
        let model = LLMModel(
            id: "o3",
            displayName: "o3",
            provider: .openAI,
            supportsTools: true,
            supportsVision: true,
            maxContextTokens: 200_000,
            supportsTemperature: false
        )
        XCTAssertFalse(model.supportsTemperature)
    }

    func testReasoningModelsDoNotSupportTemperature() {
        let registry = ModelRegistry()
        let openAIModels = registry.models(for: .openAI)

        for model in openAIModels {
            if model.id == "o3" || model.id == "o4-mini" {
                XCTAssertFalse(model.supportsTemperature,
                               "\(model.id) should not support temperature")
            } else {
                XCTAssertTrue(model.supportsTemperature,
                              "\(model.id) should support temperature")
            }
        }
    }

    func testDefaultRegistryContainsReasoningModels() {
        let registry = ModelRegistry()
        let ids = registry.models(for: .openAI).map { $0.id }
        XCTAssertTrue(ids.contains("o3"))
        XCTAssertTrue(ids.contains("o4-mini"))
    }
}
