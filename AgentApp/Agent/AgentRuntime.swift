// AgentRuntime.swift
// AgentApp
//
// The core agent runtime implemented as a Swift actor.
// Orchestrates the conversation loop: context assembly → LLM call → tool dispatch → response.
//
// Architecture Decision: Using an actor ensures thread-safe access to
// conversation state and prevents data races when streaming responses
// while processing tool calls. The runtime is the central coordinator
// that connects all system components.
//
// The handleUserMessage method returns an AsyncStream<StreamEvent> that
// the UI observes for real-time token rendering and tool execution updates.

import Foundation

// MARK: - Agent Runtime

actor AgentRuntime {
    private let provider: LLMProvider
    private let toolRegistry: ToolRegistry
    private let conversationStore: ConversationStore
    private let contextAssembler: ContextAssembler
    private let configuration: AgentConfiguration

    /// Maximum number of tool call rounds before forcing a text response.
    /// Prevents infinite loops when the LLM repeatedly calls tools.
    private let maxToolRounds: Int = 10

    init(
        provider: LLMProvider,
        toolRegistry: ToolRegistry,
        conversationStore: ConversationStore,
        contextAssembler: ContextAssembler = ContextAssembler(),
        configuration: AgentConfiguration = AgentConfiguration()
    ) {
        self.provider = provider
        self.toolRegistry = toolRegistry
        self.conversationStore = conversationStore
        self.contextAssembler = contextAssembler
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Handles a user message and returns a stream of events.
    ///
    /// This is the main entry point for the agent runtime. It:
    /// 1. Persists the user message
    /// 2. Assembles context (system prompt + history)
    /// 3. Streams the LLM response
    /// 4. Detects and executes tool calls
    /// 5. Loops back to the LLM with tool results
    /// 6. Continues until a text response (no tool calls) is produced
    ///
    /// - Parameters:
    ///   - text: The user's message text.
    ///   - sessionID: The conversation session ID.
    /// - Returns: An async stream of `StreamEvent` values for the UI to observe.
    func handleUserMessage(_ text: String, sessionID: UUID) async throws -> AsyncStream<StreamEvent> {
        // 1. Persist the user message
        let userMessage = AgentMessage(
            sessionID: sessionID,
            role: .user,
            content: text
        )
        try await conversationStore.appendMessage(userMessage)

        // 2. Create the response stream
        return AsyncStream<StreamEvent> { continuation in
            Task { [weak self] in
                guard let self = self else {
                    continuation.finish()
                    return
                }
                do {
                    try await self.runAgentLoop(sessionID: sessionID, continuation: continuation)
                } catch {
                    if let agentError = error as? AgentError {
                        continuation.yield(.error(agentError))
                    } else {
                        continuation.yield(.error(.llmRequestFailed(error.localizedDescription)))
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Agent Loop

    /// The core agent loop that handles LLM interaction and tool calling.
    private func runAgentLoop(
        sessionID: UUID,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) async throws {
        var toolRound = 0

        while toolRound < maxToolRounds {
            guard !Task.isCancelled else {
                throw AgentError.cancelled
            }

            // Fetch history and assemble context
            let history = try await conversationStore.messages(for: sessionID)
            let tools = await toolRegistry.allDefinitions()
            let contextMessages = contextAssembler.assemble(
                configuration: configuration,
                history: history
            )

            // Stream LLM response
            var contentParts: [String] = []
            var toolCalls: [ToolCall] = []

            let stream = provider.streamCompletion(
                messages: contextMessages,
                tools: tools,
                configuration: configuration.llmConfiguration
            )

            for try await event in stream {
                guard !Task.isCancelled else {
                    throw AgentError.cancelled
                }

                switch event {
                case .token(let text):
                    contentParts.append(text)
                    continuation.yield(.token(text))
                case .toolCallStart(let call):
                    toolCalls.append(call)
                    continuation.yield(.toolCallStart(call))
                case .error(let error):
                    throw error
                case .done, .toolResult:
                    break
                }
            }

            // Persist the assistant response
            let assistantContent = contentParts.isEmpty ? nil : contentParts.joined()
            let assistantMessage = AgentMessage(
                sessionID: sessionID,
                role: .assistant,
                content: assistantContent,
                toolCalls: toolCalls.isEmpty ? nil : toolCalls
            )
            try await conversationStore.appendMessage(assistantMessage)

            // If no tool calls, we're done
            if toolCalls.isEmpty {
                continuation.yield(.done(assistantMessage))
                return
            }

            // Execute tool calls and persist results
            for toolCall in toolCalls {
                let context = ToolExecutionContext(sessionID: sessionID)
                let result = await toolRegistry.execute(toolCall: toolCall, context: context)

                continuation.yield(.toolResult(result))

                let toolMessage = AgentMessage(
                    sessionID: sessionID,
                    role: .tool,
                    content: result.content,
                    toolResult: result
                )
                try await conversationStore.appendMessage(toolMessage)
            }

            toolRound += 1
        }

        // Safety: if we hit max rounds, generate a final message
        let warningMessage = AgentMessage(
            sessionID: sessionID,
            role: .assistant,
            content: "I've reached the maximum number of tool call rounds. Please provide further guidance."
        )
        try await conversationStore.appendMessage(warningMessage)
        continuation.yield(.done(warningMessage))
    }

    // MARK: - Session Management

    /// Creates a new conversation session.
    func createSession(title: String = "New Conversation") async throws -> ConversationSession {
        let session = ConversationSession(title: title, agentConfigID: configuration.id)
        try await conversationStore.createSession(session)
        return session
    }

    /// Retrieves messages for a session.
    func getMessages(sessionID: UUID) async throws -> [AgentMessage] {
        return try await conversationStore.messages(for: sessionID)
    }

    /// Lists all sessions.
    func listSessions() async throws -> [ConversationSession] {
        return try await conversationStore.listSessions()
    }

    /// Deletes a session and its messages.
    func deleteSession(_ sessionID: UUID) async throws {
        try await conversationStore.deleteMessages(for: sessionID)
        try await conversationStore.deleteSession(sessionID)
    }
}
