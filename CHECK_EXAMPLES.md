# Example Validation Checklist

This document tracks which examples have been validated and any issues found.

## Syntax Validation ✅

All Ruby files have been syntax-checked:
```bash
find . -name "*.rb" -exec ruby -c {} \;
```
**Result**: All files pass syntax validation.

## Dependency Check

### Required Gems
- ✅ `ollama_client` - Available and working
- ⚠️ `dhan_hq` - Required for trading examples (external dependency)

### Testing Examples

To test examples, you need:

1. **Ollama Server Running**
   ```bash
   # Check if Ollama is running
   curl http://localhost:11434/api/tags
   ```

2. **Environment Variables** (optional)
   ```bash
   export OLLAMA_BASE_URL="http://localhost:11434"
   export OLLAMA_MODEL="llama3.1:8b"
   ```

3. **Run Simple Example**
   ```bash
   # This will make actual API calls to Ollama
   ruby tools/test_tool_calling.rb
   ```

## Examples by Category

### ✅ Basic Examples (No External Dependencies)
- `basic/multi_step_agent_e2e.rb` - ✅ Syntax OK
- `basic/complete_workflow.rb` - ✅ Syntax OK
- `basic/chat_session_example.rb` - ✅ Syntax OK
- `basic/personas_example.rb` - ✅ Syntax OK

### ✅ Tools Examples (No External Dependencies)
- `tools/test_tool_calling.rb` - ✅ Syntax OK, ✅ Runtime Tested (works!)
- `tools/tool_calling_direct.rb` - ✅ Syntax OK
- `tools/tool_calling_pattern.rb` - ✅ Syntax OK
- `tools/structured_tools.rb` - ✅ Syntax OK

### ⚠️ Trading Examples (Requires `dhan_hq` gem)
- `trading/test_dhanhq_tool_calling.rb` - ✅ Syntax OK
- `trading/dhanhq_agent.rb` - ✅ Syntax OK
- `trading/dhanhq_tools.rb` - ✅ Syntax OK (requires `dhan_hq` gem)
- `trading/dhan_console.rb` - ✅ Syntax OK

**Note**: Trading examples require the `dhan_hq` gem which is an external dependency. These examples will fail to load if the gem is not installed, but the syntax is valid.

### ✅ Advanced Examples (No External Dependencies)
- `advanced/advanced_error_handling.rb` - ✅ Syntax OK
- `advanced/advanced_edge_cases.rb` - ✅ Syntax OK
- `advanced/advanced_complex_schemas.rb` - ✅ Syntax OK
- `advanced/advanced_performance_testing.rb` - ✅ Syntax OK

## Running Examples

### Prerequisites
1. Ollama server running on `http://localhost:11434` (or set `OLLAMA_BASE_URL`)
2. A model installed (e.g., `llama3.1:8b`)
3. `ollama-client` gem installed

### Simple Test (No Ollama Required)
```bash
# Just check syntax
ruby -c tools/test_tool_calling.rb
```

### Full Test (Requires Ollama)
```bash
# Make sure Ollama is running
ollama serve

# In another terminal, run an example
ruby tools/test_tool_calling.rb
```

## Known Issues

### Trading Examples
- Require `dhan_hq` gem (external dependency)
- May require API keys/credentials for DhanHQ platform
- These are domain-specific examples and may not run without proper setup

### Path Dependencies
- All `require_relative` paths have been verified
- All files use `require "ollama_client"` (gem dependency)
- No hardcoded absolute paths (except configurable via env vars)

## Validation Status

- ✅ **Syntax**: All files pass Ruby syntax validation
- ✅ **Dependencies**: `ollama_client` gem available
- ✅ **Imports**: All require statements verified
- ✅ **Runtime Test**: `tools/test_tool_calling.rb` successfully executed and made API calls to Ollama
- ✅ **Trading Dependencies**: `dhan_hq` gem is available
- ⚠️ **Runtime**: Examples require Ollama server to run (expected)

## Next Steps

To fully test examples:
1. Ensure Ollama server is running
2. Install required model: `ollama pull llama3.1:8b`
3. Run a simple example: `ruby tools/test_tool_calling.rb`
4. For trading examples, install `dhan_hq` gem and configure credentials
