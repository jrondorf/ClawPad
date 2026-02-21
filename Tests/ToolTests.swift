// ToolTests.swift
// AgentAppTests
//
// Tests for the tool system: ToolRegistry, and example tools.

import XCTest
@testable import AgentApp

final class ToolTests: XCTestCase {

    // MARK: - ToolRegistry Tests

    func testToolRegistration() async throws {
        let registry = ToolRegistry()
        try await registry.register(CalculatorTool())

        let tool = await registry.tool(named: "calculator")
        XCTAssertNotNil(tool)
        XCTAssertEqual(tool?.name, "calculator")
    }

    func testDuplicateRegistrationFails() async throws {
        let registry = ToolRegistry()
        try await registry.register(CalculatorTool())

        do {
            try await registry.register(CalculatorTool())
            XCTFail("Expected error for duplicate registration")
        } catch {
            // Expected
        }
    }

    func testToolExecution() async throws {
        let registry = ToolRegistry()
        try await registry.register(CalculatorTool())

        let toolCall = ToolCall(
            id: "call_1",
            name: "calculator",
            arguments: "{\"operation\":\"add\",\"a\":5,\"b\":3}"
        )

        let context = ToolExecutionContext(sessionID: UUID())
        let result = await registry.execute(toolCall: toolCall, context: context)

        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.content, "8")
    }

    func testToolNotFoundExecution() async {
        let registry = ToolRegistry()

        let toolCall = ToolCall(
            id: "call_1",
            name: "nonexistent",
            arguments: "{}"
        )

        let context = ToolExecutionContext(sessionID: UUID())
        let result = await registry.execute(toolCall: toolCall, context: context)

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("not found"))
    }

    func testAllDefinitions() async throws {
        let registry = ToolRegistry()
        try await registry.register(CalculatorTool())
        try await registry.register(DateTimeTool())

        let definitions = await registry.allDefinitions()
        XCTAssertEqual(definitions.count, 2)
    }

    // MARK: - CalculatorTool Tests

    func testCalculatorAdd() async throws {
        let calc = CalculatorTool()
        let context = ToolExecutionContext(sessionID: UUID())

        let result = try await calc.execute(
            arguments: ["operation": "add", "a": 10, "b": 5],
            context: context
        )
        XCTAssertEqual(result, "15")
    }

    func testCalculatorDivide() async throws {
        let calc = CalculatorTool()
        let context = ToolExecutionContext(sessionID: UUID())

        let result = try await calc.execute(
            arguments: ["operation": "divide", "a": 10, "b": 4],
            context: context
        )
        XCTAssertEqual(result, "2.5")
    }

    func testCalculatorDivideByZero() async throws {
        let calc = CalculatorTool()
        let context = ToolExecutionContext(sessionID: UUID())

        do {
            _ = try await calc.execute(
                arguments: ["operation": "divide", "a": 10, "b": 0],
                context: context
            )
            XCTFail("Expected division by zero error")
        } catch {
            // Expected
        }
    }

    func testCalculatorMissingArgs() async throws {
        let calc = CalculatorTool()
        let context = ToolExecutionContext(sessionID: UUID())

        do {
            _ = try await calc.execute(
                arguments: ["operation": "add"],
                context: context
            )
            XCTFail("Expected missing arguments error")
        } catch {
            // Expected
        }
    }

    // MARK: - DateTimeTool Tests

    func testDateTimeISO8601() async throws {
        let tool = DateTimeTool()
        let context = ToolExecutionContext(sessionID: UUID())

        let result = try await tool.execute(
            arguments: ["format": "iso8601"],
            context: context
        )

        // Should contain date components
        XCTAssertTrue(result.contains("T"))
        XCTAssertTrue(result.count > 10)
    }

    func testDateTimeUnix() async throws {
        let tool = DateTimeTool()
        let context = ToolExecutionContext(sessionID: UUID())

        let result = try await tool.execute(
            arguments: ["format": "unix"],
            context: context
        )

        // Should be a number
        XCTAssertNotNil(Double(result))
    }

    func testDateTimeDefault() async throws {
        let tool = DateTimeTool()
        let context = ToolExecutionContext(sessionID: UUID())

        let result = try await tool.execute(
            arguments: [:],
            context: context
        )

        // Default is iso8601
        XCTAssertTrue(result.contains("T"))
    }
}
