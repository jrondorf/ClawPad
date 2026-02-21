# ClawPad

AI Agent Client for iPad — a production-ready SwiftUI application that acts as a powerful AI agent interface, optimized for iPadOS sandboxing constraints.

## Architecture

ClawPad uses a layered, modular architecture following MVVM and clean architecture principles:

```
AgentApp/
├── App/                    # Entry point and dependency injection
│   ├── AgentApp.swift          # @main SwiftUI app with NavigationSplitView
│   └── DependencyContainer.swift  # DI container, Keychain helper, settings
│
├── Presentation/           # SwiftUI views (MVVM pattern)
│   ├── ChatView.swift          # Chat interface with streaming + ChatViewModel
│   ├── MessageBubble.swift     # Message rendering (user/assistant/tool roles)
│   ├── ToolLogView.swift       # Tool execution activity log
│   └── SettingsView.swift      # API key and model configuration
│
├── Agent/                  # Core agent runtime (actor-isolated)
│   ├── AgentRuntime.swift      # Swift actor: message routing, tool dispatch, LLM loop
│   ├── AgentMessage.swift      # Message types, tool calls, errors, sessions
│   └── ContextAssembler.swift  # System prompt + history assembly with truncation
│
├── LLM/                    # LLM provider abstraction layer
│   ├── LLMProvider.swift       # Protocol + ToolDefinition + LLMResponse types
│   ├── ClaudeProvider.swift    # Anthropic Claude API (SSE streaming)
│   └── OpenAIProvider.swift    # OpenAI Chat Completions API (SSE streaming)
│
├── Tools/                  # Protocol-based tool system
│   ├── AgentTool.swift         # Tool protocol with JSON schema definitions
│   ├── ToolRegistry.swift      # Actor-isolated tool registry and dispatch
│   └── ExampleTools/
│       ├── CalculatorTool.swift    # Basic arithmetic (sandbox-safe)
│       └── DateTimeTool.swift      # Date/time queries (sandbox-safe)
│
├── Memory/                 # Conversation persistence and token management
│   ├── ConversationStore.swift # Actor-isolated store with JSON persistence
│   └── TokenManager.swift      # Token estimation and context window truncation
│
└── Utilities/
    └── Extensions.swift        # String, Date, Array, AsyncStream helpers
```

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Swift actors** for AgentRuntime, ToolRegistry, ConversationStore | Thread-safe isolation without manual locks |
| **Protocol-based LLM providers** | Open/Closed Principle; easy to add local LLMs |
| **Protocol-based tools** | Type-safe registration, JSON schema generation |
| **Keychain for API keys** | iPadOS security best practice; never in UserDefaults |
| **No singletons** | DependencyContainer enables testing with mock implementations |
| **AsyncThrowingStream** for responses | Real-time token streaming with cancellation support |
| **#if canImport guards** | Cross-platform compilation verification on Linux CI |

## Requirements

- iPad Air / Pro with M2 or higher
- iPadOS 17.0+
- Swift 5.9+
- Xcode 15+

## Agent Runtime Flow

```
User Message → AgentRuntime.handleUserMessage()
  ├── Persist user message to ConversationStore
  ├── Assemble context (system prompt + history + token truncation)
  ├── Stream to LLMProvider
  │   ├── Receive tokens → yield to UI via AsyncStream
  │   └── Receive tool calls → dispatch to ToolRegistry
  │       ├── Execute tool (sandbox-safe)
  │       ├── Persist tool result
  │       └── Loop back to LLM with updated context
  └── Yield .done when complete (no more tool calls)
```

## Building & Testing

```bash
# Build (verifies core logic compiles)
swift build

# Run tests
swift test
```

> **Note:** SwiftUI views require Xcode and the iOS SDK. The `Package.swift` enables CI verification of all non-UI code on Linux.

## Security

- API keys stored in iPadOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- All LLM API calls use TLS (HTTPS only)
- Input sanitized before tool execution (null byte/control character removal)
- Tools operate within iPadOS sandbox (no shell execution, no arbitrary file access)
- No hardcoded secrets anywhere in the codebase

## Extensibility

- **Multi-agent**: Create multiple `AgentRuntime` instances with different `AgentConfiguration` profiles
- **New tools**: Implement `AgentTool` protocol and register in `ToolRegistry`
- **New LLM providers**: Implement `LLMProvider` protocol (e.g., local LLM, Gemini)
- **Remote tool execution**: Tools can make sandboxed network calls to microservices

