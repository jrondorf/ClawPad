// ToolLogView.swift
// AgentApp
//
// Displays a log of tool executions during the conversation.
// Shows tool names, execution status, timing, and result previews.
// Useful for debugging and understanding agent behavior.

#if canImport(SwiftUI)
import SwiftUI

// MARK: - Tool Log View

struct ToolLogView: View {
    let entries: [ChatViewModel.ToolLogEntry]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No Tool Activity",
                        systemImage: "wrench.and.screwdriver",
                        description: Text("Tool executions will appear here when the agent uses tools.")
                    )
                } else {
                    List(entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                statusIcon(for: entry.status)
                                Text(entry.toolName)
                                    .font(.headline)
                                Spacer()
                                Text(entry.timestamp.shortString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(entry.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Tool Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func statusIcon(for status: ChatViewModel.ToolLogEntry.ToolStatus) -> some View {
        switch status {
        case .started:
            Image(systemName: "arrow.right.circle")
                .foregroundStyle(.blue)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
#endif
