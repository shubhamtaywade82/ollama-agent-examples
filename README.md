# Ollama Agent Examples

> Comprehensive examples demonstrating agent patterns using the `ollama-client` gem.

This repository contains **complete agent examples** that demonstrate real-world agent patterns, tool execution, multi-step workflows, and domain-specific implementations.

## 🔗 Related Repository

This examples repository complements the **[ollama-client](https://github.com/shubhamtaywade82/ollama-client)** gem, which provides the transport layer and core client functionality.

**Installation:**
```ruby
gem "ollama-client"
```

## 📚 Repository Structure

```
ollama-agent-examples/
├── README.md           # This file
├── basic/              # Basic agent patterns and workflows
├── trading/            # Trading agent examples
│   └── dhanhq/        # DhanHQ trading platform examples
├── coding/             # Code generation and analysis agents
├── rag/                # RAG (Retrieval-Augmented Generation) examples
├── advanced/           # Advanced patterns and edge cases
└── tools/              # Tool execution and routing patterns
```

## 🎯 What This Repository Contains

### ✅ Agent Examples
- Multi-step agent workflows
- Tool execution patterns
- Agent loops and convergence logic
- Domain-specific implementations
- Error handling patterns
- Performance testing examples

### 🚫 What This Repository Does NOT Contain

This repository does **NOT** contain:
- Minimal client usage examples (see `ollama-client/examples/`)
- Transport layer code (see `ollama-client`)
- Protocol implementation (see `ollama-client`)

## 📖 Examples by Category

### Basic (`basic/`)
- Simple tool calling
- Multi-step agents
- Chat session patterns
- Complete workflows
- Interactive consoles

### Trading (`trading/dhanhq/`)
- DhanHQ trading platform integration
- Market analysis agents
- Technical indicators
- Market scanners
- Trading services

### Coding (`coding/`)
- Code review agents
- Refactoring agents
- Code generation patterns

### RAG (`rag/`)
- Document Q&A
- Semantic search
- Context injection patterns

### Advanced (`advanced/`)
- Complex multi-step workflows
- Error handling patterns
- Edge case handling
- Performance testing
- Complex schema examples

### Tools (`tools/`)
- Tool execution patterns
- Tool routing
- Structured tool organization

## 🚀 Getting Started

1. **Install the gem:**
   ```bash
   gem install ollama-client
   ```

2. **Clone this repository:**
   ```bash
   git clone https://github.com/shubhamtaywade82/ollama-agent-examples.git
   cd ollama-agent-examples
   ```

3. **Run an example:**
   ```bash
   # Basic multi-step agent
   ruby basic/multi_step_agent_e2e.rb
   
   # Trading agent example
   ruby trading/dhanhq/technical_analysis_runner.rb
   
   # Tool calling example
   ruby tools/test_tool_calling.rb
   ```

## 📝 Requirements

- Ruby 3.0+
- Ollama server running (default: `http://localhost:11434`)
- `ollama-client` gem installed

## 🔧 Configuration

Set environment variables if needed:
- `OLLAMA_BASE_URL` - Ollama server URL (default: `http://localhost:11434`)
- `OLLAMA_MODEL` - Default model to use

## 🤝 Contributing

Contributions are welcome! Please ensure your examples:
- Demonstrate clear agent patterns
- Include comments explaining the approach
- Follow Ruby best practices
- Link back to relevant `ollama-client` documentation

## 📄 License

This examples repository is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## 🔗 Links

- **Main Client Gem:** [ollama-client](https://github.com/shubhamtaywade82/ollama-client)
- **Examples Repository:** [ollama-agent-examples](https://github.com/shubhamtaywade82/ollama-agent-examples)
