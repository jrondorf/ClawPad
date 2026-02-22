// KeychainServiceTests.swift
// AgentAppTests
//
// Tests for KeychainService, SettingsManager key properties,
// and dynamic API key retrieval in providers.

import XCTest
@testable import AgentApp

final class KeychainServiceTests: XCTestCase {

    // MARK: - KeychainService Tests

    func testKeychainServiceSharedInstance() {
        let service = KeychainService.shared
        // Verify the shared instance is accessible and consistent
        XCTAssertNotNil(service)
    }

    func testKeychainServiceReadReturnsNilForMissingKey() {
        let service = KeychainService.shared
        // On Linux (CI), Keychain is not available so read always returns nil.
        // On Apple platforms, a non-existent key should also return nil.
        let result = service.read(key: "nonexistent_test_key_\(UUID().uuidString)")
        XCTAssertNil(result)
    }

    // MARK: - SettingsManager hasOpenAIKey / hasClaudeKey Tests

    func testSettingsManagerHasOpenAIKeyReturnsFalseWithoutKey() {
        let settings = SettingsManager()
        // On Linux, Keychain is unavailable so hasOpenAIKey should be false.
        // On Apple platforms with a fresh Keychain, it should also be false.
        XCTAssertFalse(settings.hasOpenAIKey)
    }

    func testSettingsManagerHasClaudeKeyReturnsFalseWithoutKey() {
        let settings = SettingsManager()
        XCTAssertFalse(settings.hasClaudeKey)
    }

    func testSettingsManagerOpenAIAPIKeyReturnsNilWithoutKey() {
        let settings = SettingsManager()
        XCTAssertNil(settings.openAIAPIKey)
    }

    func testSettingsManagerClaudeAPIKeyReturnsNilWithoutKey() {
        let settings = SettingsManager()
        XCTAssertNil(settings.claudeAPIKey)
    }

    // MARK: - Provider Dynamic Key Tests

    func testOpenAIProviderCreationWithClosure() {
        // Verify the provider can be created with a closure-based key provider
        let provider = OpenAIProvider(apiKeyProvider: { "test-key" })
        XCTAssertEqual(provider.providerName, "OpenAI")
        XCTAssertFalse(provider.availableModels.isEmpty)
    }

    func testClaudeProviderCreationWithClosure() {
        let provider = ClaudeProvider(apiKeyProvider: { "test-key" })
        XCTAssertEqual(provider.providerName, "Claude")
        XCTAssertFalse(provider.availableModels.isEmpty)
    }

    func testOpenAIProviderWithNilKeyClosure() {
        // Provider should be creatable even with a nil-returning closure.
        // The error is thrown at request time, not at init.
        let provider = OpenAIProvider(apiKeyProvider: { nil })
        XCTAssertEqual(provider.providerName, "OpenAI")
    }

    func testClaudeProviderWithNilKeyClosure() {
        let provider = ClaudeProvider(apiKeyProvider: { nil })
        XCTAssertEqual(provider.providerName, "Claude")
    }

    // MARK: - DependencyContainer makeProvider Tests

    func testMakeProviderReturnsNilWithoutKey() {
        let container = DependencyContainer()
        // Without any API key in Keychain, makeProvider should return nil
        let provider = container.makeProvider()
        XCTAssertNil(provider)
    }

    func testMakeAgentRuntimeReturnsNilWithoutKey() {
        let container = DependencyContainer()
        let runtime = container.makeAgentRuntime()
        XCTAssertNil(runtime)
    }
}
