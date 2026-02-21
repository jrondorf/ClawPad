// ConversationStore.swift
// AgentApp
//
// Persistent storage for conversation sessions and messages.
// Uses an actor for thread-safe access to the underlying storage.
//
// Architecture Decision: This implementation uses an in-memory store with
// JSON file persistence for simplicity and iPadOS sandbox compatibility.
// For production, this can be swapped to SwiftData or SQLite via GRDB
// by conforming to the same ConversationStoreProtocol.
//
// The actor isolation ensures that concurrent reads/writes from the
// AgentRuntime and UI layer are safely serialized.

import Foundation

// MARK: - Conversation Store Protocol

/// Protocol for conversation persistence, enabling testability and
/// future migration to different storage backends (SwiftData, SQLite).
protocol ConversationStoreProtocol: Sendable {
    func createSession(_ session: ConversationSession) async throws
    func updateSession(_ session: ConversationSession) async throws
    func listSessions() async throws -> [ConversationSession]
    func deleteSession(_ sessionID: UUID) async throws

    func appendMessage(_ message: AgentMessage) async throws
    func messages(for sessionID: UUID) async throws -> [AgentMessage]
    func messageCount(for sessionID: UUID) async throws -> Int
    func deleteMessages(for sessionID: UUID) async throws
    func lastMessages(for sessionID: UUID, count: Int) async throws -> [AgentMessage]
}

// MARK: - In-Memory Conversation Store

/// Actor-isolated conversation store with JSON file persistence.
/// Messages and sessions are kept in memory for fast access and
/// periodically flushed to disk for durability.
actor ConversationStore: ConversationStoreProtocol {
    private var sessions: [UUID: ConversationSession] = [:]
    private var messages: [UUID: [AgentMessage]] = [:]
    private let storageURL: URL

    init(storageDirectory: URL? = nil) {
        if let dir = storageDirectory {
            self.storageURL = dir
        } else {
            let documentsPath = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first!
            self.storageURL = documentsPath.appendingPathComponent("AgentConversations")
        }
    }

    // MARK: - Session Operations

    func createSession(_ session: ConversationSession) async throws {
        sessions[session.id] = session
        messages[session.id] = []
        try await persistToDisk()
    }

    func updateSession(_ session: ConversationSession) async throws {
        sessions[session.id] = session
        try await persistToDisk()
    }

    func listSessions() async throws -> [ConversationSession] {
        return Array(sessions.values).sorted { $0.updatedAt > $1.updatedAt }
    }

    func deleteSession(_ sessionID: UUID) async throws {
        sessions.removeValue(forKey: sessionID)
        messages.removeValue(forKey: sessionID)
        try await persistToDisk()
    }

    // MARK: - Message Operations

    func appendMessage(_ message: AgentMessage) async throws {
        if messages[message.sessionID] == nil {
            messages[message.sessionID] = []
        }
        messages[message.sessionID]?.append(message)

        // Update session timestamp
        if var session = sessions[message.sessionID] {
            session.updatedAt = message.timestamp
            sessions[message.sessionID] = session
        }

        try await persistToDisk()
    }

    func messages(for sessionID: UUID) async throws -> [AgentMessage] {
        return messages[sessionID] ?? []
    }

    func messageCount(for sessionID: UUID) async throws -> Int {
        return messages[sessionID]?.count ?? 0
    }

    func deleteMessages(for sessionID: UUID) async throws {
        messages[sessionID] = []
        try await persistToDisk()
    }

    func lastMessages(for sessionID: UUID, count: Int) async throws -> [AgentMessage] {
        guard let sessionMessages = messages[sessionID] else { return [] }
        let startIndex = max(0, sessionMessages.count - count)
        return Array(sessionMessages[startIndex...])
    }

    // MARK: - Persistence

    /// Loads stored data from disk. Call once at app startup.
    func loadFromDisk() async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)

        let sessionsURL = storageURL.appendingPathComponent("sessions.json")
        let messagesURL = storageURL.appendingPathComponent("messages.json")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if fileManager.fileExists(atPath: sessionsURL.path) {
            let data = try Data(contentsOf: sessionsURL)
            let loadedSessions = try decoder.decode([ConversationSession].self, from: data)
            self.sessions = Dictionary(uniqueKeysWithValues: loadedSessions.map { ($0.id, $0) })
        }

        if fileManager.fileExists(atPath: messagesURL.path) {
            let data = try Data(contentsOf: messagesURL)
            let loadedMessages = try decoder.decode([AgentMessage].self, from: data)
            self.messages = Dictionary(grouping: loadedMessages, by: { $0.sessionID })
        }
    }

    private func persistToDisk() async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        let sessionsURL = storageURL.appendingPathComponent("sessions.json")
        let sessionsData = try encoder.encode(Array(sessions.values))
        try sessionsData.write(to: sessionsURL, options: .atomic)

        let messagesURL = storageURL.appendingPathComponent("messages.json")
        let allMessages = messages.values.flatMap { $0 }
        let messagesData = try encoder.encode(allMessages)
        try messagesData.write(to: messagesURL, options: .atomic)
    }
}
