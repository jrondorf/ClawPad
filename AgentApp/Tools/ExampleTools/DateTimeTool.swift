// DateTimeTool.swift
// AgentApp
//
// An example sandbox-safe tool that returns the current date and time.
// Demonstrates the AgentTool protocol implementation pattern.

import Foundation

// MARK: - Date/Time Tool

/// A simple tool that returns the current date and time in various formats.
/// This is sandbox-safe as it only reads the system clock.
struct DateTimeTool: AgentTool {
    let name = "get_current_datetime"
    let description = "Returns the current date and time. Optionally specify a format: 'iso8601', 'readable', or 'unix'."

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: description,
            parameters: ToolDefinition.ToolParameters(
                properties: [
                    "format": ToolDefinition.ParameterProperty(
                        type: "string",
                        description: "The date format to use. Options: 'iso8601' (default), 'readable', 'unix'.",
                        enumValues: ["iso8601", "readable", "unix"]
                    )
                ],
                required: nil
            )
        )
    }

    func execute(arguments: [String: Any], context: ToolExecutionContext) async throws -> String {
        let format = optionalStringArgument("format", from: arguments) ?? "iso8601"
        let now = Date()

        switch format.lowercased() {
        case "unix":
            return String(format: "%.0f", now.timeIntervalSince1970)
        case "readable":
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            formatter.timeStyle = .long
            return formatter.string(from: now)
        default: // iso8601
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: now)
        }
    }
}
