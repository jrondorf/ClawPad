// SessionStore.swift
// AgentApp
//
// Observable store that manages chat session list and navigation state.
// Creates sessions directly via ConversationStore without requiring
// an LLM provider, decoupling session creation from API key configuration.
//
// Architecture Decision: SessionStore owns the navigation-level session
// state (list + selection) while ConversationStore handles persistence.
// This separation keeps the UI layer independent of the agent runtime.

import Foundation

// MARK: - Chat Session

/// Lightweight UI-level model representing a conversation session.
struct ChatSession: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var createdAt: Date
}

// MARK: - Session Store

#if canImport(Combine)
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var selectedSessionID: UUID?

    private let conversationStore: ConversationStore

    init(conversationStore: ConversationStore) {
        self.conversationStore = conversationStore
    }

    /// Loads sessions from the persistent store.
    func loadSessions() async {
        do {
            let stored = try await conversationStore.listSessions()
            sessions = stored.map {
                ChatSession(id: $0.id, title: $0.title, createdAt: $0.createdAt)
            }
        } catch {
            print("Failed to load sessions: \(error)")
        }
    }

    /// Creates a new chat session and selects it for navigation.
    func createNewSession() async {
        let chatSession = ChatSession(
            id: UUID(),
            title: "New Chat",
            createdAt: Date()
        )
        let conversationSession = ConversationSession(
            id: chatSession.id,
            title: chatSession.title,
            createdAt: chatSession.createdAt
        )
        do {
            try await conversationStore.createSession(conversationSession)
            sessions.insert(chatSession, at: 0)
            selectedSessionID = chatSession.id
        } catch {
            print("Failed to create session: \(error)")
        }
    }

    /// Deletes sessions at the given offsets.
    func deleteSessions(at offsets: IndexSet) async {
        for index in offsets {
            let session = sessions[index]
            do {
                try await conversationStore.deleteSession(session.id)
            } catch {
                print("Failed to delete session: \(error)")
            }
        }
        sessions.remove(atOffsets: offsets)
        if let id = selectedSessionID, !sessions.contains(where: { $0.id == id }) {
            selectedSessionID = nil
        }
    }
}
#else
/// Fallback SessionStore for non-Apple platforms (compilation verification only).
final class SessionStore: @unchecked Sendable {
    var sessions: [ChatSession] = []
    var selectedSessionID: UUID?

    private let conversationStore: ConversationStore

    init(conversationStore: ConversationStore) {
        self.conversationStore = conversationStore
    }

    func loadSessions() async {
        do {
            let stored = try await conversationStore.listSessions()
            sessions = stored.map {
                ChatSession(id: $0.id, title: $0.title, createdAt: $0.createdAt)
            }
        } catch {
            print("Failed to load sessions: \(error)")
        }
    }

    func createNewSession() async {
        let chatSession = ChatSession(
            id: UUID(),
            title: "New Chat",
            createdAt: Date()
        )
        let conversationSession = ConversationSession(
            id: chatSession.id,
            title: chatSession.title,
            createdAt: chatSession.createdAt
        )
        do {
            try await conversationStore.createSession(conversationSession)
            sessions.insert(chatSession, at: 0)
            selectedSessionID = chatSession.id
        } catch {
            print("Failed to create session: \(error)")
        }
    }

    func deleteSessions(at offsets: IndexSet) async {
        for index in offsets {
            let session = sessions[index]
            do {
                try await conversationStore.deleteSession(session.id)
            } catch {
                print("Failed to delete session: \(error)")
            }
        }
        // Remove in reverse order to preserve indices
        for index in offsets.sorted().reversed() {
            sessions.remove(at: index)
        }
        if let id = selectedSessionID, !sessions.contains(where: { $0.id == id }) {
            selectedSessionID = nil
        }
    }
}
#endif
