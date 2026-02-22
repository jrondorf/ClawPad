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
                .environmentObject(container.sessionStore)
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
///
/// Architecture Decision: Session creation is handled by SessionStore
/// directly through ConversationStore, without requiring an LLM provider.
/// This decouples "New Chat" from API key configuration. Settings is
/// reachable only via the dedicated gear button.
struct RootView: View {
    @EnvironmentObject var container: DependencyContainer
    @EnvironmentObject var sessionStore: SessionStore
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            // Sidebar: Session list
            List(selection: $sessionStore.selectedSessionID) {
                ForEach(sessionStore.sessions) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title)
                            .font(.headline)
                        Text(session.createdAt.relativeString)
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
            if let sessionID = sessionStore.selectedSessionID {
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
            await sessionStore.loadSessions()
        }
    }

    private func createNewSession() {
        Task {
            await sessionStore.createNewSession()
        }
    }

    private func deleteSessions(at offsets: IndexSet) {
        Task {
            await sessionStore.deleteSessions(at: offsets)
        }
    }
}
#endif
