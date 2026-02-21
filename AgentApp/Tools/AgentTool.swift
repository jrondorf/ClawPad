// AgentTool.swift
// AgentApp
//
// Defines the protocol for agent tools and their execution context.
// Tools are sandbox-safe operations that the LLM can invoke during conversation.
// No shell execution or arbitrary file system access is permitted.
//
// Architecture Decision: Tools conform to a protocol rather than using closures
// to enable type-safe registration, JSON schema generation, and testability.

import Foundation

// MARK: - Tool Execution Context

/// Context provided to tools during execution.
/// Contains session information and scoped capabilities.
struct ToolExecutionContext: Sendable {
    let sessionID: UUID
    let timestamp: Date

    init(sessionID: UUID, timestamp: Date = Date()) {
        self.sessionID = sessionID
        self.timestamp = timestamp
    }
}

// MARK: - Agent Tool Protocol

/// Protocol that all agent tools must conform to.
/// Tools are Sendable for safe use across actor boundaries.
///
/// Security: Tools operate within the iPadOS sandbox.
/// No tool should execute shell commands, access arbitrary files,
/// or open network connections outside the app's entitlements.
protocol AgentTool: Sendable {
    /// Unique identifier for this tool, used in LLM tool call references.
    var name: String { get }

    /// Human-readable description sent to the LLM to explain tool capabilities.
    var description: String { get }

    /// JSON-schema definition of the tool's parameters.
    var definition: ToolDefinition { get }

    /// Executes the tool with the given arguments.
    ///
    /// - Parameters:
    ///   - arguments: A dictionary of argument values parsed from the LLM's JSON.
    ///   - context: Execution context with session info.
    /// - Returns: A string result to be sent back to the LLM.
    /// - Throws: `AgentError.toolExecutionFailed` on failure.
    func execute(arguments: [String: Any], context: ToolExecutionContext) async throws -> String
}

// MARK: - Tool Validation

extension AgentTool {
    /// Validates that all required parameters are present in the arguments.
    func validateRequiredArguments(
        _ arguments: [String: Any],
        required: [String]
    ) throws {
        for key in required {
            guard arguments[key] != nil else {
                throw AgentError.invalidToolArguments(
                    "Missing required argument '\(key)' for tool '\(name)'"
                )
            }
        }
    }

    /// Safely extracts a string argument, throwing a descriptive error if missing or wrong type.
    func stringArgument(_ key: String, from arguments: [String: Any]) throws -> String {
        guard let value = arguments[key] as? String else {
            throw AgentError.invalidToolArguments(
                "Argument '\(key)' must be a string for tool '\(name)'"
            )
        }
        return value
    }

    /// Safely extracts an optional string argument.
    func optionalStringArgument(_ key: String, from arguments: [String: Any]) -> String? {
        return arguments[key] as? String
    }
}
