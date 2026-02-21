// OpenAIProvider.swift
// AgentApp
//
// Concrete LLMProvider implementation for OpenAI's Chat Completions API.
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
        "gpt-4o",
        "gpt-4o-mini",
        "gpt-4-turbo",
        "o1-preview",
        "o1-mini"
    ]

    private let apiKey: String
    private let baseURL: URL

    #if !os(Linux)
    private let session: URLSession

    init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.openai.com")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
    }
    #else
    init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.openai.com")!
    ) {
        self.apiKey = apiKey
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

                    // Parse OpenAI SSE stream
                    var toolCallBuffers: [Int: (id: String, name: String, arguments: String)] = [:]

                    for try await line in bytes.lines {
                        guard !Task.isCancelled else {
                            continuation.finish(throwing: AgentError.cancelled)
                            return
                        }

                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard jsonString != "[DONE]" else { break }

                        guard let data = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let choice = choices.first,
                              let delta = choice["delta"] as? [String: Any] else {
                            continue
                        }

                        // Handle text content
                        if let content = delta["content"] as? String {
                            continuation.yield(.token(content))
                        }

                        // Handle tool calls
                        if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                            for toolCallDelta in toolCalls {
                                guard let index = toolCallDelta["index"] as? Int else { continue }

                                if let id = toolCallDelta["id"] as? String {
                                    let function = toolCallDelta["function"] as? [String: Any]
                                    toolCallBuffers[index] = (
                                        id: id,
                                        name: function?["name"] as? String ?? "",
                                        arguments: function?["arguments"] as? String ?? ""
                                    )
                                } else if let function = toolCallDelta["function"] as? [String: Any] {
                                    if let name = function["name"] as? String, !name.isEmpty {
                                        toolCallBuffers[index]?.name += name
                                    }
                                    if let args = function["arguments"] as? String {
                                        toolCallBuffers[index]?.arguments += args
                                    }
                                }
                            }
                        }

                        // Check for finish reason
                        if let finishReason = choice["finish_reason"] as? String,
                           finishReason == "tool_calls" {
                            // Emit all buffered tool calls
                            for index in toolCallBuffers.keys.sorted() {
                                if let buffer = toolCallBuffers[index] {
                                    let toolCall = ToolCall(
                                        id: buffer.id,
                                        name: buffer.name,
                                        arguments: buffer.arguments
                                    )
                                    continuation.yield(.toolCallStart(toolCall))
                                }
                            }
                            toolCallBuffers.removeAll()
                        }
                    }

                    // Emit any remaining tool calls
                    for index in toolCallBuffers.keys.sorted() {
                        if let buffer = toolCallBuffers[index] {
                            let toolCall = ToolCall(
                                id: buffer.id,
                                name: buffer.name,
                                arguments: buffer.arguments
                            )
                            continuation.yield(.toolCallStart(toolCall))
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
        let url = baseURL.appendingPathComponent("/v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": configuration.model,
            "max_tokens": configuration.maxTokens,
            "temperature": configuration.temperature,
            "stream": stream
        ]

        body["messages"] = messages.map { encodeMessage($0) }

        if !tools.isEmpty {
            body["tools"] = tools.map { encodeTool($0) }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func encodeMessage(_ message: AgentMessage) -> [String: Any] {
        var encoded: [String: Any] = [
            "role": message.role.rawValue
        ]

        if let content = message.content {
            encoded["content"] = content
        }

        // Encode tool calls in assistant messages
        if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
            encoded["tool_calls"] = toolCalls.map { call -> [String: Any] in
                [
                    "id": call.id,
                    "type": "function",
                    "function": [
                        "name": call.name,
                        "arguments": call.arguments
                    ]
                ]
            }
        }

        // Encode tool results
        if let result = message.toolResult {
            encoded["role"] = "tool"
            encoded["tool_call_id"] = result.toolCallID
            encoded["content"] = result.content
        }

        return encoded
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
            "function": [
                "name": tool.name,
                "description": tool.description,
                "parameters": parameters
            ]
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
