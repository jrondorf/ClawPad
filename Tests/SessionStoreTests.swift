// SessionStoreTests.swift
// AgentAppTests
//
// Tests for ChatSession and SessionStore.

import XCTest
@testable import AgentApp

final class SessionStoreTests: XCTestCase {

    // MARK: - ChatSession Tests

    func testChatSessionCreation() {
        let id = UUID()
        let date = Date()
        let session = ChatSession(id: id, title: "Test Chat", createdAt: date)

        XCTAssertEqual(session.id, id)
        XCTAssertEqual(session.title, "Test Chat")
        XCTAssertEqual(session.createdAt, date)
    }

    func testChatSessionHashable() {
        let id = UUID()
        let session1 = ChatSession(id: id, title: "Chat 1", createdAt: Date())
        let session2 = ChatSession(id: id, title: "Chat 1", createdAt: session1.createdAt)

        XCTAssertEqual(session1, session2)

        var set = Set<ChatSession>()
        set.insert(session1)
        set.insert(session2)
        XCTAssertEqual(set.count, 1)
    }

    func testChatSessionIdentifiable() {
        let session = ChatSession(id: UUID(), title: "Test", createdAt: Date())
        // Identifiable requires id property
        XCTAssertNotNil(session.id)
    }

    // MARK: - SessionStore Tests

    func testSessionStoreCreateNewSession() async {
        let store = ConversationStore(storageDirectory: temporaryDirectory())
        let sessionStore = SessionStore(conversationStore: store)

        await sessionStore.createNewSession()

        XCTAssertEqual(sessionStore.sessions.count, 1)
        XCTAssertEqual(sessionStore.sessions.first?.title, "New Chat")
        XCTAssertNotNil(sessionStore.selectedSessionID)
        XCTAssertEqual(sessionStore.selectedSessionID, sessionStore.sessions.first?.id)
    }

    func testSessionStoreCreateMultipleSessions() async {
        let store = ConversationStore(storageDirectory: temporaryDirectory())
        let sessionStore = SessionStore(conversationStore: store)

        await sessionStore.createNewSession()
        await sessionStore.createNewSession()
        await sessionStore.createNewSession()

        XCTAssertEqual(sessionStore.sessions.count, 3)
        // Most recent session should be selected
        XCTAssertEqual(sessionStore.selectedSessionID, sessionStore.sessions.first?.id)
    }

    func testSessionStoreLoadSessions() async {
        let dir = temporaryDirectory()
        let store = ConversationStore(storageDirectory: dir)

        // Create sessions directly in conversation store
        let session1 = ConversationSession(title: "Session 1")
        let session2 = ConversationSession(title: "Session 2")
        try? await store.createSession(session1)
        try? await store.createSession(session2)

        let sessionStore = SessionStore(conversationStore: store)
        await sessionStore.loadSessions()

        XCTAssertEqual(sessionStore.sessions.count, 2)
    }

    func testSessionStoreDeleteSessions() async {
        let store = ConversationStore(storageDirectory: temporaryDirectory())
        let sessionStore = SessionStore(conversationStore: store)

        await sessionStore.createNewSession()
        await sessionStore.createNewSession()
        XCTAssertEqual(sessionStore.sessions.count, 2)

        await sessionStore.deleteSessions(at: IndexSet(integer: 0))
        XCTAssertEqual(sessionStore.sessions.count, 1)
    }

    func testSessionStoreDeleteSelectedSession() async {
        let store = ConversationStore(storageDirectory: temporaryDirectory())
        let sessionStore = SessionStore(conversationStore: store)

        await sessionStore.createNewSession()
        let selectedID = sessionStore.selectedSessionID
        XCTAssertNotNil(selectedID)

        await sessionStore.deleteSessions(at: IndexSet(integer: 0))
        XCTAssertNil(sessionStore.selectedSessionID)
    }

    func testCreateNewSessionDoesNotRequireRuntime() async {
        // This test verifies the core fix: session creation works
        // without an LLM provider/runtime being configured.
        let store = ConversationStore(storageDirectory: temporaryDirectory())
        let sessionStore = SessionStore(conversationStore: store)

        // No API keys, no runtime — should still succeed
        await sessionStore.createNewSession()

        XCTAssertEqual(sessionStore.sessions.count, 1)
        XCTAssertNotNil(sessionStore.selectedSessionID)
    }

    // MARK: - Helpers

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionStoreTests-\(UUID().uuidString)")
    }
}
