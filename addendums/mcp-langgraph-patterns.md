# MCP Integration Patterns for LangGraph

Reference doc for LangGraph-specific MCP integration: when to use MCP vs native tools, interceptors, code execution mode, search_tools, and security.

---

## MCP vs. Native Tools: Decision Criteria

| Criterion | Use MCP | Use Native LangGraph Tools |
|-----------|---------|---------------------------|
| Connecting to well-supported external services (GitHub, Slack, Google Drive, Jira, Salesforce) | Yes -- community MCP server likely exists | |
| Users bring their own tools without modifying agent code | Yes | |
| Tool discovery at runtime across many integrations | Yes | |
| Cross-framework interoperability | Yes | |
| Tool implements core agent logic or state management | | Yes |
| **Tool needs access to graph state, the store, or the checkpointer** | | **Yes -- MCP servers cannot see these** |
| Tight control over error handling and retry logic | | Yes |
| Small, focused agent where MCP overhead is not worth it | | Yes |

**Most common production pattern**: use both together. Core reasoning tools are native; external integrations are MCP. `langchain-mcp-adapters` converts MCP tools into LangChain tool objects, making them indistinguishable from native tools within a LangGraph agent.

> **Key rule**: If it needs graph state, the store, or the checkpointer, it must be a native tool.

---

## Interceptor Pattern: Bridging MCP and LangGraph Runtime Context

MCP servers run as separate processes -- they cannot see LangGraph state, the store, or the checkpointer. **Interceptors** in `langchain-mcp-adapters` bridge this gap, providing middleware-like control over tool calls.

```python
from langchain_mcp_adapters.interceptors import MCPToolCallRequest

async def personalise_search(request: MCPToolCallRequest, handler):
    """Inject user preferences into search queries from the LangGraph store."""
    runtime = request.runtime
    prefs = runtime.store.get(("preferences",), runtime.context.user_id)
    if prefs and request.name == "search":
        request = request.override(args={
            **request.args,
            "language": prefs.value.get("language", "en"),
        })
    return await handler(request)
```

### Interceptors Returning Command Objects

Interceptors can return `Command` objects to update agent state or route to a different graph node based on tool results -- making MCP tools first-class participants in LangGraph control flow.

This enables patterns like:
- Routing to an error-handling node when an MCP tool returns an error
- Updating graph state with enriched data from the interceptor
- Conditional branching based on MCP tool results

---

## Code Execution Mode for Context Efficiency

As agents connect to more MCP servers, loading all tool definitions upfront and passing intermediate results through the context window becomes expensive.

### The Pattern

Instead of making individual tool calls and accumulating results in context, the agent writes code that orchestrates multiple tool calls, processes intermediate results in the code environment, and returns only the final output to context.

**Before**: N tool calls x (definition tokens + result tokens)
**After**: 1 code execution x (code tokens + summary tokens)

For complex multi-tool tasks, this reduces context consumption by an order of magnitude.

### How to Implement

1. Configure code execution alongside MCP tools
2. Instruct the agent to write Python scripts that call MCP tools
3. Configure the code execution environment with access to the MCP client

Anthropic (and independently Cloudflare, who calls this "Code Mode") found this to be one of the most impactful context efficiency improvements for agents with many integrations.

---

## search_tools: Lazy Tool Discovery at Scale

At scale -- hundreds of MCP servers, thousands of tools -- loading all tool definitions upfront is not viable. The `search_tools` pattern:

1. Provide a `search_tools` tool that queries available MCP tool definitions on demand
2. The agent searches for the tool it needs based on the current task
3. Only that tool's definition is loaded into context
4. The agent then calls the discovered tool

This keeps context viable when the total tool surface area is large, and pairs naturally with Anthropic's Tool Search Tool (`tool_search_tool_regex_20251119`).

---

## Security: Trust Tiers Applied to MCP Servers

MCP servers run with whatever permissions they are granted. A malicious or compromised MCP server can instruct the agent to take unintended actions. Apply the same trust tier model as for agent tools:

| Trust Tier | Applied To | What Is Permitted |
|-----------|-----------|-------------------|
| **Gold** | System-generated, verified MCP servers | Read/write, external calls, sensitive data |
| **Silver** | Internal MCP servers, validated | Read/write own namespace, internal APIs |
| **Untrusted** | Third-party/community MCP servers | Read-only, sandboxed, no external calls |

### Security Checklist

- Audit all MCP server code before use
- Treat third-party MCP servers as **untrusted** until verified
- Never grant MCP servers write access to sensitive systems without pre-execution checks
- Use the harness to tokenise sensitive data before it flows through the model (passing tokens rather than real PII to the LLM, detokenising only when data flows between external systems)
