// ClaudeProvider.swift
// AgentApp
//
// Concrete LLMProvider implementation for Anthropic's Claude API.
// Supports streaming responses, tool calling, and system prompts.
//
// Architecture Decision: The provider is a struct conforming to Sendable
// for safe use across actor boundaries. URLSession handles networking.
// The streaming implementation uses Server-Sent Events (SSE) parsing.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Claude Provider

struct ClaudeProvider: LLMProvider {
    let providerName = "Claude"
    let availableModels = [
        "claude-3.5-sonnet",
        "claude-3.7-sonnet",
        "claude-opus-4",
        "claude-opus-4.6"
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
        baseURL: URL = URL(string: "https://api.anthropic.com")!,
        session: URLSession = .shared
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.baseURL = baseURL
        self.session = session
    }
    #else
    init(
        apiKeyProvider: @escaping @Sendable () -> String?,
        baseURL: URL = URL(string: "https://api.anthropic.com")!
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
        // URLSession.AsyncBytes not available on Linux.
        // This code path exists only for compilation verification.
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

                    // Parse Server-Sent Events stream
                    var currentToolCall: ToolCall?
                    var toolArgumentsBuffer = ""
                    var currentToolID = ""
                    var currentToolName = ""

                    for try await line in bytes.lines {
                        guard !Task.isCancelled else {
                            continuation.finish(throwing: AgentError.cancelled)
                            return
                        }

                        // SSE format: "data: {...}"
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard jsonString != "[DONE]" else { break }

                        guard let data = jsonString.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let eventType = event["type"] as? String else {
                            continue
                        }

                        switch eventType {
                        case "content_block_start":
                            if let contentBlock = event["content_block"] as? [String: Any],
                               let blockType = contentBlock["type"] as? String {
                                if blockType == "tool_use" {
                                    currentToolID = contentBlock["id"] as? String ?? UUID().uuidString
                                    currentToolName = contentBlock["name"] as? String ?? ""
                                    toolArgumentsBuffer = ""
                                }
                            }

                        case "content_block_delta":
                            if let delta = event["delta"] as? [String: Any],
                               let deltaType = delta["type"] as? String {
                                switch deltaType {
                                case "text_delta":
                                    if let text = delta["text"] as? String {
                                        continuation.yield(.token(text))
                                    }
                                case "input_json_delta":
                                    if let partial = delta["partial_json"] as? String {
                                        toolArgumentsBuffer += partial
                                    }
                                default:
                                    break
                                }
                            }

                        case "content_block_stop":
                            if !currentToolName.isEmpty {
                                currentToolCall = ToolCall(
                                    id: currentToolID,
                                    name: currentToolName,
                                    arguments: toolArgumentsBuffer
                                )
                                continuation.yield(.toolCallStart(currentToolCall!))
                                currentToolName = ""
                                toolArgumentsBuffer = ""
                            }

                        case "message_stop":
                            break

                        default:
                            break
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
            print("[ClaudeProvider] No API key available at request time")
            throw AgentError.authenticationFailed
        }
        print("[ClaudeProvider] Using API key for request")

        let url = baseURL.appendingPathComponent("/v1/messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        // Separate system messages from conversation
        let systemContent = messages
            .filter { $0.role == .system }
            .compactMap { $0.content }
            .joined(separator: "\n")

        let conversationMessages = messages.filter { $0.role != .system }

        var body: [String: Any] = [
            "model": configuration.model,
            "max_tokens": configuration.maxTokens,
            "stream": stream
        ]

        if !systemContent.isEmpty {
            body["system"] = systemContent
        }

        body["messages"] = conversationMessages.map { encodeMessage($0) }

        if !tools.isEmpty {
            body["tools"] = tools.map { encodeTool($0) }
        }

        if let temperature = Optional(configuration.temperature), temperature >= 0 {
            body["temperature"] = temperature
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func encodeMessage(_ message: AgentMessage) -> [String: Any] {
        var encoded: [String: Any] = [
            "role": message.role.rawValue
        ]

        if let content = message.content {
            if message.role == .tool, let result = message.toolResult {
                encoded["role"] = "user"
                encoded["content"] = [
                    [
                        "type": "tool_result",
                        "tool_use_id": result.toolCallID,
                        "content": content
                    ]
                ]
            } else {
                encoded["content"] = content
            }
        }

        if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
            var contentArray: [[String: Any]] = []
            if let text = message.content {
                contentArray.append(["type": "text", "text": text])
            }
            for call in toolCalls {
                var toolUse: [String: Any] = [
                    "type": "tool_use",
                    "id": call.id,
                    "name": call.name
                ]
                if let args = try? JSONSerialization.jsonObject(
                    with: call.arguments.data(using: .utf8) ?? Data()
                ) {
                    toolUse["input"] = args
                } else {
                    toolUse["input"] = [String: Any]()
                }
                contentArray.append(toolUse)
            }
            encoded["content"] = contentArray
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

        var inputSchema: [String: Any] = [
            "type": tool.parameters.type,
            "properties": props
        ]
        if let required = tool.parameters.required {
            inputSchema["required"] = required
        }

        return [
            "name": tool.name,
            "description": tool.description,
            "input_schema": inputSchema
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
