# ollama-agent-examples

Standalone Ruby example scripts demonstrating agent patterns with the `ollama-client` gem. Reference/tutorial repo — no app server, no tests required.

## Stack

- Ruby scripts (no Rails, no gem structure)
- `ollama-client` gem
- Ollama (local LLM, must be running)

## Structure

```
basic/         # Basic chat, structured output, personas, sessions
trading/       # Trading agent examples
  dhanhq/      # DhanHQ-specific trading examples
coding/        # Code generation and review agents
rag/           # RAG (retrieval-augmented generation) patterns
advanced/      # Multi-step agents, complex workflows
tools/         # Tool execution and routing patterns
```

## Key rules

- This is a **reference/examples repo** — not a production system
- Each script is self-contained and runnable independently
- Requires local Ollama server running at `localhost:11434`
- Never add real API credentials to examples — use env vars or placeholders
- DhanHQ trading examples use DhanHQ credentials from `.env`
