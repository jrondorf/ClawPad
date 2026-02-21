// SettingsView.swift
// AgentApp
//
// Settings interface for configuring API keys, selecting LLM providers,
// and managing application preferences.
//
// Security: API keys are displayed as secure fields and stored in Keychain.
// Keys are never logged, persisted in UserDefaults, or sent to analytics.

#if canImport(SwiftUI)
import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss

    @State private var claudeKey: String = ""
    @State private var openAIKey: String = ""
    @State private var showSavedAlert = false

    var body: some View {
        NavigationStack {
            Form {
                // Provider Selection
                Section {
                    Picker("LLM Provider", selection: $settings.selectedProvider) {
                        Text("Claude (Anthropic)").tag("Claude")
                        Text("OpenAI").tag("OpenAI")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Provider")
                } footer: {
                    Text("Select which LLM provider to use for conversations.")
                }

                // Model Selection
                Section("Model") {
                    if settings.selectedProvider == "Claude" {
                        Picker("Model", selection: $settings.selectedModel) {
                            Text("Claude Sonnet 4").tag("claude-sonnet-4-20250514")
                            Text("Claude Opus 4").tag("claude-opus-4-20250514")
                            Text("Claude 3.5 Haiku").tag("claude-3-5-haiku-20241022")
                        }
                    } else {
                        Picker("Model", selection: $settings.selectedModel) {
                            Text("GPT-4o").tag("gpt-4o")
                            Text("GPT-4o Mini").tag("gpt-4o-mini")
                            Text("GPT-4 Turbo").tag("gpt-4-turbo")
                            Text("o1 Preview").tag("o1-preview")
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

    private func saveKeys() {
        if !claudeKey.isEmpty {
            settings.claudeAPIKey = claudeKey
        }
        if !openAIKey.isEmpty {
            settings.openAIAPIKey = openAIKey
        }
        showSavedAlert = true
    }
}
#endif
