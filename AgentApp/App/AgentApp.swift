// AgentApp.swift
// AgentApp
//
// The main entry point for the iPad AI Agent application.
// Sets up the dependency container, bootstraps services, and
// presents the root navigation view.
//
// Architecture Decision: The app uses @StateObject for the DependencyContainer
// to ensure it lives for the entire app lifecycle. The container is passed
// through the environment so all child views can access shared dependencies.

#if canImport(SwiftUI)
import SwiftUI

// MARK: - App Entry Point

@main
struct AgentApp: App {
    @StateObject private var container = DependencyContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
                .environmentObject(container.settings)
                .task {
                    await container.bootstrap()
                }
        }
    }
}

// MARK: - Root View

/// Root navigation view that manages the split view layout for iPad.
/// Uses NavigationSplitView for the sidebar + detail pattern
/// optimized for iPad screen sizes.
struct RootView: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var selectedSessionID: UUID?
    @State private var showSettings = false
    @State private var sessions: [ConversationSession] = []

    var body: some View {
        NavigationSplitView {
            // Sidebar: Session list
            List(selection: $selectedSessionID) {
                ForEach(sessions) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title)
                            .font(.headline)
                        Text(session.updatedAt.relativeString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(session.id)
                }
                .onDelete(perform: deleteSessions)
            }
            .navigationTitle("Conversations")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: createNewSession) {
                        Label("New Chat", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(action: { showSettings = true }) {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
        } detail: {
            // Detail: Chat view
            if let sessionID = selectedSessionID {
                ChatView(sessionID: sessionID)
                    .id(sessionID)
            } else {
                ContentUnavailableView(
                    "No Conversation Selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Select a conversation or create a new one to start chatting.")
                )
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .task {
            await loadSessions()
        }
    }

    private func loadSessions() async {
        do {
            sessions = try await container.conversationStore.listSessions()
        } catch {
            print("Failed to load sessions: \(error)")
        }
    }

    private func createNewSession() {
        Task {
            guard let runtime = container.makeAgentRuntime() else {
                showSettings = true
                return
            }
            do {
                let session = try await runtime.createSession(title: "New Chat")
                sessions.insert(session, at: 0)
                selectedSessionID = session.id
            } catch {
                print("Failed to create session: \(error)")
            }
        }
    }

    private func deleteSessions(at offsets: IndexSet) {
        Task {
            for index in offsets {
                let session = sessions[index]
                do {
                    try await container.conversationStore.deleteSession(session.id)
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
}
#endif
