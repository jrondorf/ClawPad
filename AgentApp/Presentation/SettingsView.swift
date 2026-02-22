// SettingsView.swift
// AgentApp
//
// Settings interface for configuring API keys, selecting LLM providers,
// and managing application preferences.
//
// Architecture Decision: Model options are loaded dynamically from
// ModelRegistry, grouped by provider, with capability indicators.
// This eliminates hardcoded model enums and supports future model additions.
//
// Security: API keys are displayed as secure fields and stored in Keychain.
// Keys are never logged, persisted in UserDefaults, or sent to analytics.

#if canImport(SwiftUI)
import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @State private var claudeKey: String = ""
    @State private var openAIKey: String = ""
    @State private var showSavedAlert = false

    /// The provider type derived from the current settings selection.
    private var selectedProviderType: LLMProviderType {
        LLMProviderType(rawValue: settings.selectedProvider) ?? .anthropic
    }

    /// Models available for the currently selected provider.
    private var modelsForProvider: [LLMModel] {
        container.modelRegistry.models(for: selectedProviderType)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Provider Selection
                Section {
                    Picker("LLM Provider", selection: $settings.selectedProvider) {
                        ForEach(LLMProviderType.allCases, id: \.rawValue) { provider in
                            Text(providerDisplayName(provider)).tag(provider.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: settings.selectedProvider) { _, newProvider in
                        // Auto-select the first model when switching providers
                        if let providerType = LLMProviderType(rawValue: newProvider),
                           let firstModel = container.modelRegistry.models(for: providerType).first {
                            settings.selectedModel = firstModel.id
                        }
                    }
                } header: {
                    Text("Provider")
                } footer: {
                    Text("Select which LLM provider to use for conversations.")
                }

                // Model Selection — dynamically loaded from ModelRegistry
                Section("Model") {
                    Picker("Model", selection: $settings.selectedModel) {
                        ForEach(modelsForProvider) { model in
                            HStack {
                                Text(model.displayName)
                                Spacer()
                                modelCapabilityIcons(model)
                            }
                            .tag(model.id)
                        }
                    }

                    // Capability legend
                    if let selected = modelsForProvider.first(where: { $0.id == settings.selectedModel }) {
                        HStack(spacing: 12) {
                            if selected.supportsTools {
                                Label("Tools", systemImage: "wrench.fill")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                            if selected.supportsVision {
                                Label("Vision", systemImage: "eye.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                            if selected.maxContextTokens >= 200_000 {
                                Label("Large Context", systemImage: "text.alignleft")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                // API Keys
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Claude API Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SecureField("sk-ant-...", text: $claudeKey)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("OpenAI API Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SecureField("sk-...", text: $openAIKey)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    Button("Save API Keys") {
                        saveKeys()
                    }
                    .buttonStyle(.borderedProminent)
                } header: {
                    Text("API Keys")
                } footer: {
                    Text("API keys are stored securely in the device Keychain and never leave your device except when making API requests over TLS.")
                }

                // About
                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Runtime", value: "Swift Actor-based")
                    LabeledContent("Platform", value: "iPadOS 17+")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Settings Saved", isPresented: $showSavedAlert) {
                Button("OK") { }
            } message: {
                Text("Your API keys have been securely stored in the Keychain.")
            }
            .onAppear {
                // Pre-fill with masked indicators if keys exist
                claudeKey = settings.claudeAPIKey != nil ? "" : ""
                openAIKey = settings.openAIAPIKey != nil ? "" : ""
            }
        }
    }

    // MARK: - Helpers

    private func providerDisplayName(_ provider: LLMProviderType) -> String {
        switch provider {
        case .anthropic: return "Claude (Anthropic)"
        case .openAI: return "OpenAI"
        }
    }

    @ViewBuilder
    private func modelCapabilityIcons(_ model: LLMModel) -> some View {
        HStack(spacing: 4) {
            if model.supportsTools {
                Image(systemName: "wrench.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
            if model.supportsVision {
                Image(systemName: "eye.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
            if model.maxContextTokens >= 200_000 {
                Image(systemName: "text.alignleft")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func saveKeys() {
        if !claudeKey.isEmpty {
            settings.claudeAPIKey = claudeKey
            print("[SettingsView] Claude API key saved to Keychain")
        }
        if !openAIKey.isEmpty {
            settings.openAIAPIKey = openAIKey
            print("[SettingsView] OpenAI API key saved to Keychain")
        }
        print("[SettingsView] hasClaudeKey: \(settings.hasClaudeKey), hasOpenAIKey: \(settings.hasOpenAIKey)")
        showSavedAlert = true
    }
}
#endif
