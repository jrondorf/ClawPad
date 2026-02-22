// DependencyContainer.swift
// AgentApp
//
// Centralized dependency injection container. Creates and wires all
// application components at launch time.
//
// Architecture Decision: Using a container instead of global singletons
// enables testability (swap implementations for mocks), supports
// multi-agent configurations, and makes dependencies explicit.
// The container is created once in the App and passed through the
// SwiftUI environment.

import Foundation

// MARK: - Keychain Helper

/// Minimal Keychain wrapper for secure API key storage.
/// Uses Security framework for iPadOS Keychain access.
///
/// Security: API keys are stored encrypted in the system Keychain,
/// never in UserDefaults or plain files.
struct KeychainHelper: Sendable {
    static let shared = KeychainHelper()

    private let service = "com.agentapp.apikeys"

    func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }

        #if os(iOS) || os(macOS) || os(tvOS) || os(watchOS) || os(visionOS)
        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AgentError.serializationFailed("Failed to save API key to Keychain: \(status)")
        }
        #endif
    }

    func load(key: String) -> String? {
        #if os(iOS) || os(macOS) || os(tvOS) || os(watchOS) || os(visionOS)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
        #else
        return nil
        #endif
    }

    func delete(key: String) {
        #if os(iOS) || os(macOS) || os(tvOS) || os(watchOS) || os(visionOS)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        #endif
    }
}

// MARK: - Settings Manager

/// Observable settings manager for the application.
/// Manages API keys via Keychain and model preferences via UserDefaults.
///
/// On Apple platforms, uses ObservableObject + @Published for SwiftUI binding.
/// The @unchecked Sendable conformance is safe because all mutations happen
/// on the main thread via SwiftUI's observation system.
#if canImport(Combine)
import Combine

final class SettingsManager: ObservableObject, @unchecked Sendable {
    @Published var selectedProvider: String {
        didSet { UserDefaults.standard.set(selectedProvider, forKey: "selectedProvider") }
    }
    @Published var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "selectedModel") }
    }

    private let keychain = KeychainHelper.shared

    init() {
        self.selectedProvider = UserDefaults.standard.string(forKey: "selectedProvider") ?? "Claude"
        self.selectedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "claude-3.7-sonnet"
    }

    var claudeAPIKey: String? {
        get { keychain.load(key: "claude_api_key") }
        set {
            if let value = newValue {
                try? keychain.save(key: "claude_api_key", value: value)
            } else {
                keychain.delete(key: "claude_api_key")
            }
            objectWillChange.send()
        }
    }

    var openAIAPIKey: String? {
        get { keychain.load(key: "openai_api_key") }
        set {
            if let value = newValue {
                try? keychain.save(key: "openai_api_key", value: value)
            } else {
                keychain.delete(key: "openai_api_key")
            }
            objectWillChange.send()
        }
    }
}
#else
/// Fallback SettingsManager for non-Apple platforms (used for compilation verification).
final class SettingsManager: @unchecked Sendable {
    var selectedProvider: String = "Claude"
    var selectedModel: String = "claude-3.7-sonnet"

    private let keychain = KeychainHelper.shared

    var claudeAPIKey: String? {
        get { keychain.load(key: "claude_api_key") }
        set {
            if let value = newValue {
                try? keychain.save(key: "claude_api_key", value: value)
            } else {
                keychain.delete(key: "claude_api_key")
            }
        }
    }

    var openAIAPIKey: String? {
        get { keychain.load(key: "openai_api_key") }
        set {
            if let value = newValue {
                try? keychain.save(key: "openai_api_key", value: value)
            } else {
                keychain.delete(key: "openai_api_key")
            }
        }
    }
}
#endif

// MARK: - Dependency Container

/// Assembles and provides all application dependencies.
/// Created once at app launch and injected into the SwiftUI environment.
///
/// Extensibility: New agents can be added by creating additional
/// AgentRuntime instances with different configurations and providers.
#if canImport(Combine)
@MainActor
final class DependencyContainer: ObservableObject {
    let settings: SettingsManager
    let conversationStore: ConversationStore
    let toolRegistry: ToolRegistry
    let modelRegistry: ModelRegistry
    let sessionStore: SessionStore

    init() {
        self.settings = SettingsManager()
        self.conversationStore = ConversationStore()
        self.toolRegistry = ToolRegistry()
        self.modelRegistry = ModelRegistry()
        self.sessionStore = SessionStore(conversationStore: conversationStore)
    }

    /// Initializes the container by registering tools and loading data.
    func bootstrap() async {
        // Register built-in tools
        do {
            try await toolRegistry.register(DateTimeTool())
            try await toolRegistry.register(CalculatorTool())
        } catch {
            print("Warning: Failed to register tools: \(error)")
        }

        // Load persisted conversations
        do {
            try await conversationStore.loadFromDisk()
        } catch {
            print("Warning: Failed to load conversations: \(error)")
        }
    }

    /// Creates an LLM provider based on current settings.
    func makeProvider() -> LLMProvider? {
        switch settings.selectedProvider {
        case "Claude":
            guard let apiKey = settings.claudeAPIKey, !apiKey.isEmpty else { return nil }
            return ClaudeProvider(apiKey: apiKey)
        case "OpenAI":
            guard let apiKey = settings.openAIAPIKey, !apiKey.isEmpty else { return nil }
            return OpenAIProvider(apiKey: apiKey)
        default:
            return nil
        }
    }

    /// Creates an AgentRuntime with the current configuration.
    func makeAgentRuntime() -> AgentRuntime? {
        guard let provider = makeProvider() else { return nil }
        let config = AgentConfiguration(
            model: settings.selectedModel,
            temperature: 0.7
        )
        return AgentRuntime(
            provider: provider,
            toolRegistry: toolRegistry,
            conversationStore: conversationStore,
            configuration: config
        )
    }
}
#else
/// Fallback DependencyContainer for non-Apple platforms (used for compilation verification).
final class DependencyContainer: @unchecked Sendable {
    let settings: SettingsManager
    let conversationStore: ConversationStore
    let toolRegistry: ToolRegistry
    let modelRegistry: ModelRegistry
    let sessionStore: SessionStore

    init() {
        self.settings = SettingsManager()
        self.conversationStore = ConversationStore()
        self.toolRegistry = ToolRegistry()
        self.modelRegistry = ModelRegistry()
        self.sessionStore = SessionStore(conversationStore: conversationStore)
    }

    func bootstrap() async {
        do {
            try await toolRegistry.register(DateTimeTool())
            try await toolRegistry.register(CalculatorTool())
        } catch {
            print("Warning: Failed to register tools: \(error)")
        }

        do {
            try await conversationStore.loadFromDisk()
        } catch {
            print("Warning: Failed to load conversations: \(error)")
        }
    }

    func makeProvider() -> LLMProvider? {
        switch settings.selectedProvider {
        case "Claude":
            guard let apiKey = settings.claudeAPIKey, !apiKey.isEmpty else { return nil }
            return ClaudeProvider(apiKey: apiKey)
        case "OpenAI":
            guard let apiKey = settings.openAIAPIKey, !apiKey.isEmpty else { return nil }
            return OpenAIProvider(apiKey: apiKey)
        default:
            return nil
        }
    }

    func makeAgentRuntime() -> AgentRuntime? {
        guard let provider = makeProvider() else { return nil }
        let config = AgentConfiguration(
            model: settings.selectedModel,
            temperature: 0.7
        )
        return AgentRuntime(
            provider: provider,
            toolRegistry: toolRegistry,
            conversationStore: conversationStore,
            configuration: config
        )
    }
}
#endif
