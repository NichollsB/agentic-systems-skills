# Tool Design: Anthropic API-Specific Features

Addendum to the community `tool-design` skill. Covers Anthropic-specific tool use capabilities not available in other providers.

---

## Strict Mode: Guaranteed Schema Conformance

Without strict mode, a booking system asking for `passengers: int` might receive `passengers: "two"` or `passengers: "2"`, breaking downstream functions. Enable strict mode to guarantee schema conformance:

```python
# Claude API (Anthropic)
tool_def = {
    "name": "book_flight",
    "description": "Book a flight for specified passengers. Use when user wants to purchase or reserve a flight.",
    "strict": True,  # guarantees schema conformance
    "input_schema": {
        "type": "object",
        "required": ["origin", "destination", "passengers"],
        "properties": {
            "origin": {"type": "string", "description": "IATA airport code, e.g. LHR"},
            "destination": {"type": "string", "description": "IATA airport code, e.g. JFK"},
            "passengers": {"type": "integer", "description": "Number of passengers (1-9)"}
        }
    }
}
```

---

## Tool Use Examples: `input_examples` Field

JSON schemas define what is structurally valid but cannot express usage patterns -- when to include optional parameters, which combinations make sense, or what conventions your API expects. Tool use examples provide this guidance.

```python
tool_def = {
    "name": "search_users",
    "description": "Search users by name or email. Use this to find user IDs before calling other user-related tools.",
    "input_schema": {...},
    "input_examples": [
        {"query": "john smith", "response_format": "concise"},
        {"query": "john@company.com", "response_format": "detailed"}
    ]
}
```

### Impact

> Anthropic internal testing: adding examples improved tool accuracy from **72% to 90%** on complex parameter handling. Each example adds ~20-100 tokens to prompt cost.

Released November 2025 as part of Anthropic's advanced tool use features.

---

## Tool Search Tool: On-Demand Discovery

Solves a critical scaling problem. As agents integrate hundreds of tools, stuffing all definitions into context upfront can consume 50,000+ tokens before the agent reads a single user request. The Tool Search Tool allows the agent to search for and load tools on demand, keeping only relevant tool definitions in context.

```python
tools = [
    {"type": "tool_search_tool_regex_20251119", "name": "tool_search_tool_regex"},
    {"type": "code_execution_20250825", "name": "code_execution"},
    # Your tools -- each marked with defer_loading=True for dynamic discovery
]
```

This moves tool use from simple function calling toward intelligent orchestration, enabling agents to work across hundreds of tools without context bloat. Released November 2025.

---

## Programmatic Tool Calling: Code Orchestration Pattern

Instead of natural language tool calling where each invocation requires a full inference pass, Claude writes Python code that orchestrates multiple tool calls, processes intermediate results in code, and returns only a final summary to context.

### Impact

> Reduced context consumption from **200KB of raw data to 1KB of results** on complex tasks. Intermediate tool results stay in the code execution environment, not in the LLM context.

This is one of the most impactful context efficiency improvements for agents with many integrations. Released November 2025. Independently validated by Cloudflare, who calls this "Code Mode."

### Pattern

Configure code execution alongside your tools. The agent writes Python scripts that call tools, processes intermediate results in the code environment, and returns only the final output to context. This moves from:

- **Before**: N tool calls x (definition tokens + result tokens)
- **After**: 1 code execution x (code tokens + summary tokens)

For complex multi-tool tasks, this reduces context consumption by an order of magnitude.
