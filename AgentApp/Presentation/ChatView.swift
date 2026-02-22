// ChatView.swift
// AgentApp
//
// The main chat interface for interacting with the AI agent.
// Displays streaming messages, handles user input, and shows
// tool execution activity.
//
// Architecture Decision: ChatView owns a ChatViewModel that manages
// the interaction with AgentRuntime. This follows MVVM and keeps
// view logic separate from business logic. The view model is
// @MainActor for safe UI updates.

#if canImport(SwiftUI)
import SwiftUI

// MARK: - Chat View Model

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [AgentMessage] = []
    @Published var streamingText: String = ""
    @Published var isStreaming: Bool = false
    @Published var toolLog: [ToolLogEntry] = []
    @Published var errorMessage: String?
    @Published var showToolLog: Bool = false

    private var currentTask: Task<Void, Never>?

    struct ToolLogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let toolName: String
        let status: ToolStatus
        let detail: String

        enum ToolStatus {
            case started, completed, failed
        }
    }

    /// Sends a user message and processes the agent's streamed response.
    func sendMessage(_ text: String, sessionID: UUID, container: DependencyContainer) {
        guard !text.trimmed.isEmpty else { return }
        guard !isStreaming else { return }

        guard let runtime = container.makeAgentRuntime() else {
            errorMessage = "Please configure an API key in Settings."
            return
        }

        isStreaming = true
        streamingText = ""
        errorMessage = nil

        currentTask = Task {
            do {
                let stream = try await runtime.handleUserMessage(text, sessionID: sessionID)

                for await event in stream {
                    switch event {
                    case .token(let token):
                        streamingText += token

                    case .toolCallStart(let call):
                        toolLog.append(ToolLogEntry(
                            timestamp: Date(),
                            toolName: call.name,
                            status: .started,
                            detail: "Arguments: \(call.arguments.truncated(to: 200))"
                        ))

                    case .toolResult(let result):
                        let status: ToolLogEntry.ToolStatus = result.isError ? .failed : .completed
                        toolLog.append(ToolLogEntry(
                            timestamp: Date(),
                            toolName: result.toolCallID,
                            status: status,
                            detail: result.content.truncated(to: 200)
                        ))
                        // Reset streaming text for next LLM turn
                        streamingText = ""

                    case .done(let message):
                        // Refresh full message list from store
                        messages = try await runtime.getMessages(sessionID: sessionID)
                        streamingText = ""
                        _ = message // Silences unused warning

                    case .error(let error):
                        errorMessage = error.localizedDescription
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            isStreaming = false
        }
    }

    /// Cancels the current streaming response.
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isStreaming = false
        streamingText = ""
    }

    /// Loads existing messages for a session.
    func loadMessages(sessionID: UUID, container: DependencyContainer) async {
        do {
            messages = try await container.conversationStore.messages(for: sessionID)
        } catch {
            errorMessage = "Failed to load messages: \(error.localizedDescription)"
        }
    }
}

// MARK: - Chat View

struct ChatView: View {
    let sessionID: UUID
    @EnvironmentObject var container: DependencyContainer
    @StateObject private var viewModel = ChatViewModel()
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        // Streaming indicator
                        if viewModel.isStreaming && !viewModel.streamingText.isEmpty {
                            MessageBubble(message: AgentMessage(
                                sessionID: sessionID,
                                role: .assistant,
                                content: viewModel.streamingText
                            ))
                            .id("streaming")
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: viewModel.streamingText) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }

            // Error banner
            if let error = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.errorMessage = nil
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }

            Divider()

            // Input bar
            HStack(spacing: 12) {
                // Tool log toggle
                Button(action: { viewModel.showToolLog.toggle() }) {
                    Image(systemName: "wrench.and.screwdriver")
                        .foregroundColor(viewModel.toolLog.isEmpty ? .secondary : .blue)
                }

                // Text input
                TextField("Message...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onSubmit { sendMessage() }

                // Send / Cancel button
                if viewModel.isStreaming {
                    Button(action: { viewModel.cancel() }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                } else {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(inputText.isBlank ? .secondary : .blue)
                    }
                    .disabled(inputText.isBlank)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { viewModel.showToolLog.toggle() }) {
                    Label("Tool Log", systemImage: "list.bullet.rectangle")
                }
            }
        }
        .sheet(isPresented: $viewModel.showToolLog) {
            ToolLogView(entries: viewModel.toolLog)
        }
        .task {
            await viewModel.loadMessages(sessionID: sessionID, container: container)
            isInputFocused = true
        }
    }

    private func sendMessage() {
        let text = inputText
        inputText = ""
        viewModel.sendMessage(text, sessionID: sessionID, container: container)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if viewModel.isStreaming {
            proxy.scrollTo("streaming", anchor: .bottom)
        } else if let lastMessage = viewModel.messages.last {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }
}
#endif

