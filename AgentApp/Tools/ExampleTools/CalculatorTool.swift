// CalculatorTool.swift
// AgentApp
//
// An example sandbox-safe tool that performs basic arithmetic.
// Demonstrates input validation and structured error handling.

import Foundation

// MARK: - Calculator Tool

/// A tool that performs basic arithmetic operations.
/// Sandbox-safe: performs only in-memory computation.
struct CalculatorTool: AgentTool {
    let name = "calculator"
    let description = "Performs basic arithmetic operations (add, subtract, multiply, divide) on two numbers."

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: description,
            parameters: ToolDefinition.ToolParameters(
                properties: [
                    "operation": ToolDefinition.ParameterProperty(
                        type: "string",
                        description: "The arithmetic operation to perform.",
                        enumValues: ["add", "subtract", "multiply", "divide"]
                    ),
                    "a": ToolDefinition.ParameterProperty(
                        type: "number",
                        description: "The first operand.",
                        enumValues: nil
                    ),
                    "b": ToolDefinition.ParameterProperty(
                        type: "number",
                        description: "The second operand.",
                        enumValues: nil
                    )
                ],
                required: ["operation", "a", "b"]
            )
        )
    }

    func execute(arguments: [String: Any], context: ToolExecutionContext) async throws -> String {
        try validateRequiredArguments(arguments, required: ["operation", "a", "b"])
        let operation = try stringArgument("operation", from: arguments)

        // Numbers may come as Int or Double from JSON parsing
        let a = extractNumber(arguments["a"])
        let b = extractNumber(arguments["b"])

        guard let aVal = a, let bVal = b else {
            throw AgentError.invalidToolArguments("Arguments 'a' and 'b' must be numbers.")
        }

        let result: Double
        switch operation.lowercased() {
        case "add":
            result = aVal + bVal
        case "subtract":
            result = aVal - bVal
        case "multiply":
            result = aVal * bVal
        case "divide":
            guard bVal != 0 else {
                throw AgentError.toolExecutionFailed("Division by zero is not allowed.")
            }
            result = aVal / bVal
        default:
            throw AgentError.invalidToolArguments(
                "Unknown operation '\(operation)'. Use: add, subtract, multiply, divide."
            )
        }

        // Format nicely: remove trailing .0 for whole numbers
        if result == result.rounded() && !result.isInfinite && !result.isNaN {
            return String(format: "%.0f", result)
        }
        return String(result)
    }

    private func extractNumber(_ value: Any?) -> Double? {
        if let intVal = value as? Int { return Double(intVal) }
        if let doubleVal = value as? Double { return doubleVal }
        if let stringVal = value as? String { return Double(stringVal) }
        return nil
    }
}
