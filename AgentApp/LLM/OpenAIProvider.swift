// OpenAIProvider.swift
// AgentApp
//
// Concrete LLMProvider implementation for OpenAI's Responses API.
// Supports streaming responses, tool/function calling, and system prompts.
//
// Architecture Decision: Follows the same pattern as ClaudeProvider.
// Both providers parse SSE streams but handle different JSON schemas.
// The abstract LLMProvider protocol ensures the AgentRuntime doesn't
// need to know which provider is being used.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - OpenAI Provider

struct OpenAIProvider: LLMProvider {
    let providerName = "OpenAI"
    let availableModels = [
        "gpt-4.1",
        "gpt-4.1-mini",
        "gpt-4.1-nano",
        "o3",
        "o4-mini"
    ]

    /// Closure that provides the API key at request time.
    /// Architecture Decision: Using a closure instead of a stored key ensures
    /// the provider always reads the latest value from Keychain, avoiding
    /// stale configuration after settings changes without app restart.
    private let apiKeyProvider: @Sendable () -> String?
    private let baseURL: URL

    #if !os(Linux)
    private let session: URLSession

    init(
        apiKeyProvider: @escaping @Sendable () -> String?,
        baseURL: URL = URL(string: "https://api.openai.com")!,
        session: URLSession = .shared
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.baseURL = baseURL
        self.session = session
    }
    #else
    init(
        apiKeyProvider: @escaping @Sendable () -> String?,
        baseURL: URL = URL(string: "https://api.openai.com")!
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.baseURL = baseURL
    }
    #endif

    // MARK: - Streaming Completion

    func streamCompletion(
        messages: [AgentMessage],
        tools: [ToolDefinition],
        configuration: LLMConfiguration
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        #if os(Linux)
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: AgentError.llmRequestFailed("Streaming not supported on this platform"))
        }
        #else
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try buildRequest(
                        messages: messages,
                        tools: tools,
                        configuration: configuration,
                        stream: true
                    )

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AgentError.networkError("Invalid response type"))
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
                        let errorBody = try await collectErrorBody(bytes: bytes)
                        if httpResponse.statusCode == 401 {
                            continuation.finish(throwing: AgentError.authenticationFailed)
                        } else {
                            continuation.finish(throwing: AgentError.llmRequestFailed(
                                "HTTP \(httpResponse.statusCode): \(errorBody)"
                            ))
                        }
                        return
                    }

                    // Parse OpenAI Responses API SSE stream
                    var currentEvent: String = ""

                    for try await line in bytes.lines {
                        guard !Task.isCancelled else {
                            continuation.finish(throwing: AgentError.cancelled)
                            return
                        }

                        if line.hasPrefix("event: ") {
                            currentEvent = String(line.dropFirst(7))
                            continue
                        }

                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard jsonString != "[DONE]" else { break }

                        // Handle stream completion/error events
                        if currentEvent == "response.completed" { break }
                        if currentEvent == "response.failed" || currentEvent == "error" {
                            if let data = jsonString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                let msg = (json["message"] as? String)
                                    ?? (json["error"] as? String)
                                    ?? "Unknown error"
                                continuation.finish(throwing: AgentError.llmRequestFailed(msg))
                            } else {
                                continuation.finish(throwing: AgentError.llmRequestFailed(jsonString))
                            }
                            return
                        }

                        guard let data = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            continue
                        }

                        // response.output_text.delta → yield token
                        if currentEvent == "response.output_text.delta" {
                            if let delta = json["delta"] as? String {
                                continuation.yield(.token(delta))
                            }
                            continue
                        }

                        // response.output_item.done → check for function_call
                        if currentEvent == "response.output_item.done" {
                            if let item = json["item"] as? [String: Any],
                               let type_ = item["type"] as? String, type_ == "function_call",
                               let id = item["id"] as? String,
                               let name = item["name"] as? String,
                               let arguments = item["arguments"] as? String {
                                let toolCall = ToolCall(id: id, name: name, arguments: arguments)
                                continuation.yield(.toolCallStart(toolCall))
                            }
                            continue
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: AgentError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        #endif
    }

    // MARK: - Request Building

    #if !os(Linux)
    private func buildRequest(
        messages: [AgentMessage],
        tools: [ToolDefinition],
        configuration: LLMConfiguration,
        stream: Bool
    ) throws -> URLRequest {
        // Read API key at request time for dynamic retrieval
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            print("[OpenAIProvider] No API key available at request time")
            throw AgentError.authenticationFailed
        }
        print("[OpenAIProvider] Using API key for request")

        let url = baseURL.appendingPathComponent("/v1/responses")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": configuration.model,
            "stream": stream,
            "max_output_tokens": configuration.maxTokens
        ]

        body["input"] = messages.map { encodeMessage($0) }

        if !tools.isEmpty {
            body["tools"] = tools.map { encodeTool($0) }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func encodeMessage(_ message: AgentMessage) -> [String: Any] {
        // Tool result messages
        if let result = message.toolResult {
            return [
                "role": "tool",
                "content": [
                    [
                        "type": "function_call_output",
                        "call_id": result.toolCallID,
                        "output": result.content
                    ]
                ]
            ]
        }

        // Assistant messages with tool calls
        if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
            let content: [[String: Any]] = toolCalls.map { call in
                [
                    "type": "function_call",
                    "call_id": call.id,
                    "name": call.name,
                    "arguments": call.arguments
                ]
            }
            return [
                "role": "assistant",
                "content": content
            ]
        }

        // Assistant text messages
        if message.role == .assistant {
            return [
                "role": "assistant",
                "content": [
                    [
                        "type": "output_text",
                        "text": message.content ?? ""
                    ]
                ]
            ]
        }

        // System and user messages
        return [
            "role": message.role.rawValue,
            "content": message.content ?? ""
        ]
    }

    private func encodeTool(_ tool: ToolDefinition) -> [String: Any] {
        var props: [String: Any] = [:]
        for (key, prop) in tool.parameters.properties {
            var propDict: [String: Any] = ["type": prop.type]
            if let desc = prop.description {
                propDict["description"] = desc
            }
            if let enumVals = prop.enumValues {
                propDict["enum"] = enumVals
            }
            props[key] = propDict
        }

        var parameters: [String: Any] = [
            "type": tool.parameters.type,
            "properties": props
        ]
        if let required = tool.parameters.required {
            parameters["required"] = required
        }

        return [
            "type": "function",
            "name": tool.name,
            "description": tool.description,
            "parameters": parameters
        ]
    }

    private func collectErrorBody(bytes: URLSession.AsyncBytes) async throws -> String {
        var body = ""
        for try await line in bytes.lines {
            body += line
            if body.count > 1000 { break }
        }
        return body
    }
    #endif
}
