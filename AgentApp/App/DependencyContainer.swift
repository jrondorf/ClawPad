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

// MARK: - Keychain Service

/// Secure API key storage abstraction using the iOS Keychain.
/// Uses Security framework for iPadOS Keychain access.
///
/// Architecture Decision: Named KeychainService (not Helper) to reflect
/// its role as a first-class service abstraction with save/read/delete.
///
/// Security: API keys are stored encrypted in the system Keychain,
/// never in UserDefaults or plain files.
struct KeychainService: Sendable {
    static let shared = KeychainService()

    private let service = "com.agentapp.apikeys"

    func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }

        #if os(iOS) || os(macOS) || os(tvOS) || os(watchOS) || os(visionOS)
        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecUseDataProtectionKeychain as String: true
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            print("[KeychainService] Failed to save key for account: \(key), status: \(status)")
            throw AgentError.serializationFailed("Failed to save API key to Keychain: \(status)")
        }
        print("[KeychainService] Successfully saved key for account: \(key)")
        #endif
    }

    func read(key: String) -> String? {
        #if os(iOS) || os(macOS) || os(tvOS) || os(watchOS) || os(visionOS)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            print("[KeychainService] No key found in Keychain for account: \(key)")
            return nil
        }
        let value = String(data: data, encoding: .utf8)
        print("[KeychainService] Key exists for account \(key): \(value != nil && !(value?.isEmpty ?? true))")
        return value
        #else
        return nil
        #endif
    }

    func delete(key: String) {
        #if os(iOS) || os(macOS) || os(tvOS) || os(watchOS) || os(visionOS)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemDelete(query as CFDictionary)
        print("[KeychainService] Deleted key for account: \(key)")
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
///
/// Architecture Decision: API keys are never stored in UserDefaults.
/// The Keychain is read at access time, ensuring the provider always
/// gets the latest persisted key without stale configuration state.
#if canImport(Combine)
import Combine

final class SettingsManager: ObservableObject, @unchecked Sendable {
    @Published var selectedProvider: String {
        didSet { UserDefaults.standard.set(selectedProvider, forKey: "selectedProvider") }
    }
    @Published var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "selectedModel") }
    }

    let keychain: KeychainService

    init(keychain: KeychainService = .shared) {
        self.keychain = keychain
        self.selectedProvider = UserDefaults.standard.string(forKey: "selectedProvider") ?? "Claude"
        self.selectedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "claude-3.7-sonnet"
    }

    /// Whether an OpenAI API key is stored in the Keychain.
    var hasOpenAIKey: Bool {
        guard let key = keychain.read(key: "openai_api_key") else { return false }
        return !key.isEmpty
    }

    /// Whether a Claude API key is stored in the Keychain.
    var hasClaudeKey: Bool {
        guard let key = keychain.read(key: "claude_api_key") else { return false }
        return !key.isEmpty
    }

    var claudeAPIKey: String? {
        get { keychain.read(key: "claude_api_key") }
        set {
            if let value = newValue {
                do {
                    try keychain.save(key: "claude_api_key", value: value)
                } catch {
                    print("[SettingsManager] Failed to save Claude API key: \(error)")
                }
            } else {
                keychain.delete(key: "claude_api_key")
            }
            objectWillChange.send()
        }
    }

    var openAIAPIKey: String? {
        get { keychain.read(key: "openai_api_key") }
        set {
            if let value = newValue {
                do {
                    try keychain.save(key: "openai_api_key", value: value)
                } catch {
                    print("[SettingsManager] Failed to save OpenAI API key: \(error)")
                }
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

    let keychain: KeychainService

    init(keychain: KeychainService = .shared) {
        self.keychain = keychain
    }

    /// Whether an OpenAI API key is stored in the Keychain.
    var hasOpenAIKey: Bool {
        guard let key = keychain.read(key: "openai_api_key") else { return false }
        return !key.isEmpty
    }

    /// Whether a Claude API key is stored in the Keychain.
    var hasClaudeKey: Bool {
        guard let key = keychain.read(key: "claude_api_key") else { return false }
        return !key.isEmpty
    }

    var claudeAPIKey: String? {
        get { keychain.read(key: "claude_api_key") }
        set {
            if let value = newValue {
                do {
                    try keychain.save(key: "claude_api_key", value: value)
                } catch {
                    print("[SettingsManager] Failed to save Claude API key: \(error)")
                }
            } else {
                keychain.delete(key: "claude_api_key")
            }
        }
    }

    var openAIAPIKey: String? {
        get { keychain.read(key: "openai_api_key") }
        set {
            if let value = newValue {
                do {
                    try keychain.save(key: "openai_api_key", value: value)
                } catch {
                    print("[SettingsManager] Failed to save OpenAI API key: \(error)")
                }
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
    ///
    /// Architecture Decision: The provider receives a closure that reads
    /// the API key from Keychain at request time. This ensures the provider
    /// always uses the latest key, even if settings change after creation.
    func makeProvider() -> LLMProvider? {
        switch settings.selectedProvider {
        case "Claude":
            guard settings.hasClaudeKey else {
                print("[DependencyContainer] No Claude API key found in Keychain")
                return nil
            }
            let keychain = settings.keychain
            print("[DependencyContainer] Creating ClaudeProvider with dynamic key retrieval")
            return ClaudeProvider(apiKeyProvider: {
                keychain.read(key: "claude_api_key")
            })
        case "OpenAI":
            guard settings.hasOpenAIKey else {
                print("[DependencyContainer] No OpenAI API key found in Keychain")
                return nil
            }
            let keychain = settings.keychain
            print("[DependencyContainer] Creating OpenAIProvider with dynamic key retrieval")
            return OpenAIProvider(apiKeyProvider: {
                keychain.read(key: "openai_api_key")
            })
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

    /// Creates an LLM provider based on current settings.
    ///
    /// Architecture Decision: The provider receives a closure that reads
    /// the API key from Keychain at request time. This ensures the provider
    /// always uses the latest key, even if settings change after creation.
    func makeProvider() -> LLMProvider? {
        switch settings.selectedProvider {
        case "Claude":
            guard settings.hasClaudeKey else {
                print("[DependencyContainer] No Claude API key found in Keychain")
                return nil
            }
            let keychain = settings.keychain
            print("[DependencyContainer] Creating ClaudeProvider with dynamic key retrieval")
            return ClaudeProvider(apiKeyProvider: {
                keychain.read(key: "claude_api_key")
            })
        case "OpenAI":
            guard settings.hasOpenAIKey else {
                print("[DependencyContainer] No OpenAI API key found in Keychain")
                return nil
            }
            let keychain = settings.keychain
            print("[DependencyContainer] Creating OpenAIProvider with dynamic key retrieval")
            return OpenAIProvider(apiKeyProvider: {
                keychain.read(key: "openai_api_key")
            })
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
