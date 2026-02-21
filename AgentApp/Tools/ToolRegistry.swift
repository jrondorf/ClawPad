// ToolRegistry.swift
// AgentApp
//
// A thread-safe registry for agent tools. Uses an actor to ensure
// safe concurrent access when tools are registered or looked up
// during agent runtime execution.
//
// Architecture Decision: The registry is an actor rather than a class with
// locks, leveraging Swift concurrency for safe isolation. Tools are registered
// at startup via the DependencyContainer and looked up by the AgentRuntime
// during tool call dispatch.

import Foundation

// MARK: - Tool Registry

actor ToolRegistry {
    private var tools: [String: AgentTool] = [:]

    /// Registers a tool in the registry.
    /// - Parameter tool: The tool to register.
    /// - Throws: If a tool with the same name is already registered.
    func register(_ tool: AgentTool) throws {
        guard tools[tool.name] == nil else {
            throw AgentError.toolExecutionFailed(
                "Tool '\(tool.name)' is already registered."
            )
        }
        tools[tool.name] = tool
    }

    /// Looks up a tool by name.
    /// - Parameter name: The tool name to look up.
    /// - Returns: The registered tool, or nil if not found.
    func tool(named name: String) -> AgentTool? {
        return tools[name]
    }

    /// Executes a tool call by looking up the tool and invoking it.
    ///
    /// - Parameters:
    ///   - toolCall: The tool call from the LLM.
    ///   - context: The execution context.
    /// - Returns: A `ToolResult` containing the execution output.
    func execute(toolCall: ToolCall, context: ToolExecutionContext) async -> ToolResult {
        guard let tool = tools[toolCall.name] else {
            return ToolResult(
                toolCallID: toolCall.id,
                content: "Error: Tool '\(toolCall.name)' not found.",
                isError: true
            )
        }

        do {
            let arguments = try toolCall.decodedArguments()
            let result = try await tool.execute(arguments: arguments, context: context)
            return ToolResult(
                toolCallID: toolCall.id,
                content: result
            )
        } catch {
            return ToolResult(
                toolCallID: toolCall.id,
                content: "Error executing tool '\(toolCall.name)': \(error.localizedDescription)",
                isError: true
            )
        }
    }

    /// Returns tool definitions for all registered tools.
    /// Used when sending available tools to the LLM.
    func allDefinitions() -> [ToolDefinition] {
        return tools.values.map { $0.definition }
    }

    /// Returns the names of all registered tools.
    func registeredToolNames() -> [String] {
        return Array(tools.keys)
    }
}
