// MessageBubble.swift
// AgentApp
//
// Renders a single message in the chat view.
// Supports different visual styles for user, assistant, system, and tool messages.
//
// Architecture Decision: MessageBubble is a pure view component with no
// business logic. It receives an AgentMessage and renders it with appropriate
// styling based on the message role.

#if canImport(SwiftUI)
import SwiftUI

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: AgentMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Role label
                HStack(spacing: 4) {
                    roleIcon
                    Text(roleLabel)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }

                // Message content
                if let content = message.content, !content.isEmpty {
                    Text(content)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(bubbleBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                // Tool calls indicator
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    ForEach(toolCalls) { call in
                        HStack(spacing: 6) {
                            Image(systemName: "wrench.fill")
                                .font(.caption2)
                            Text("Called: \(call.name)")
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                // Tool result indicator
                if let result = message.toolResult {
                    HStack(spacing: 6) {
                        Image(systemName: result.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(result.isError ? .red : .green)
                        Text(result.content.truncated(to: 100))
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(result.isError ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Timestamp
                Text(message.timestamp.shortString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if message.role != .user {
                Spacer(minLength: 60)
            }
        }
    }

    // MARK: - Styling

    @ViewBuilder
    private var roleIcon: some View {
        switch message.role {
        case .user:
            Image(systemName: "person.circle.fill")
                .foregroundStyle(.blue)
        case .assistant:
            Image(systemName: "cpu")
                .foregroundStyle(.purple)
        case .system:
            Image(systemName: "gear")
                .foregroundStyle(.gray)
        case .tool:
            Image(systemName: "wrench.and.screwdriver")
                .foregroundStyle(.orange)
        }
    }

    private var roleLabel: String {
        switch message.role {
        case .user: return "You"
        case .assistant: return "Assistant"
        case .system: return "System"
        case .tool: return "Tool"
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        switch message.role {
        case .user:
            Color.blue
                .opacity(0.15)
        case .assistant:
            Color(.systemGray6)
        case .system:
            Color.gray
                .opacity(0.1)
        case .tool:
            Color.orange
                .opacity(0.1)
        }
    }
}
#endif
