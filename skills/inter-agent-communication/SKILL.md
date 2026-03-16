---
name: inter-agent-communication
description: Design inter-agent communication contracts for multi-agent systems -- choosing communication primitives (shared state, tool-based handoffs, A2A protocol), defining context transfer contracts, handling communication failures, and selecting communication architecture patterns. Use this skill when the user is building a multi-agent system and needs to decide how agents talk to each other, when they ask about agent handoffs or the swarm pattern, when designing A2A protocol integration for cross-process or cross-framework agents, when dealing with the telephone game problem in agent chains, when an agent hands off to another and the receiving agent lacks context, when designing communication contracts between agents, or when debugging communication failures in multi-agent systems. Also triggers on phrases like "how should my agents communicate", "agent handoff", "pass context between agents", "A2A protocol", "shared state vs message passing", "swarm pattern", or "agents losing context in chains".
---

# Inter-Agent Communication

This skill designs the communication layer for a multi-agent system. It answers: how do agents exchange information, hand off control, and maintain context across boundaries?

Use the steps below to reason through decisions, but present the output as a Communication Contract -- conclusions with rationale, not a thinking log.

**Scope boundary:** This skill covers *how* agents communicate. *Which* topology to use (supervisor, swarm, hierarchical) belongs in `agentic-architecture`. *How* to wire LangGraph state and nodes belongs in `langgraph-fundamentals`. Security and trust boundaries for inter-agent messages belong in `guardrails-and-security`.

## Step 1: Understand the multi-agent system

Before designing communication, get clear on the system's shape. Extract from context or ask:

- How many agents are there, and what does each one do?
- Are agents in the same process, or distributed across services?
- What topology has been chosen? (supervisor, swarm, orchestrator-worker, hierarchical)
- What data needs to flow between agents?
- Are there external or third-party agents that must interoperate?

If the user has already described the system, extract answers first and confirm rather than re-asking.

## Step 2: Select communication primitives

There are three tiers of communication primitive. Select the right tier for each agent-to-agent boundary in the system.

### Tier 1: Shared state (default for intra-graph)

All agents read and write the same TypedDict state. This is the primary mechanism for agents within a single LangGraph graph.

Properties:
- Zero overhead -- no serialisation or network calls
- Fully checkpointable and auditable via LangGraph's checkpointer
- All agents see the full state (use field-level scoping to limit visibility)

Use by default when agents are nodes in the same graph.

Design decision -- what goes in shared state vs. tool arguments:
- **Shared state**: Data that persists across the conversation and is needed by multiple agents. Examples: user profile, accumulated findings, conversation history, task status.
- **Tool arguments**: Data specific to one handoff that the receiving agent needs only for this invocation. Examples: the specific query to research, a document ID to analyse.

### Tier 2: Tool-based handoffs (swarm pattern)

An agent calls a `transfer_to_<agent>` tool, routing control without a central coordinator. Each agent decides when it is out of scope and hands off to the appropriate specialist.

```python
from langgraph.prebuilt import create_handoff_tool

billing_handoff = create_handoff_tool(
    agent_name="billing_agent",
    description="Transfer to billing agent for payment and subscription queries"
)
support_handoff = create_handoff_tool(
    agent_name="support_agent",
    description="Transfer to support agent for technical troubleshooting"
)
```

Key distinction from supervisor: in swarm, each agent decides when it is out of scope. In supervisor, a central coordinator makes all routing decisions.

Use when agents are in the same process but need decoupled, autonomous routing.

### Tier 3: A2A protocol (cross-process / cross-framework)

Google's Agent2Agent protocol (released April 2025) is an open standard using JSON-RPC 2.0 over HTTP/SSE. It solves cross-framework coordination -- LangGraph, CrewAI, AutoGen, and OpenAI Agents SDK agents can interoperate.

Use when agents run in separate processes, separate services, or different frameworks.

Core concepts:
- **Agent Card**: machine-readable manifest at `/.well-known/agent.json` describing capabilities, skills, I/O modes, and endpoint URL
- **Context ID**: groups messages into a conversation thread (analogous to `thread_id`)
- **Task ID**: identifies each individual request within a conversation
- **RPC methods**: `message/send` (synchronous), `message/stream` (SSE streaming), `tasks/get` (async polling)

LangGraph A2A compatibility: any LangGraph agent with a `messages` key in state is automatically A2A-compatible when deployed via LangGraph Agent Server (langgraph-api >= 0.4.21):

```python
class AgentState(TypedDict):
    messages: Annotated[list, add_messages]  # required for A2A compatibility

async def call_specialist_agent(state: AgentState) -> dict:
    async with aiohttp.ClientSession() as session:
        payload = {
            "jsonrpc": "2.0",
            "id": str(uuid.uuid4()),
            "method": "message/send",
            "params": {
                "message": {
                    "role": "user",
                    "parts": [{"kind": "text", "text": state["query"]}],
                    "messageId": str(uuid.uuid4()),
                    "contextId": state.get("a2a_context_id"),
                }
            }
        }
        response = await session.post(SPECIALIST_URL + "/a2a", json=payload)
        result = await response.json()
        return {"specialist_response": extract_text(result)}
```

**A2A vs MCP:** MCP extends what a single agent can *do* (tool access). A2A expands how agents *collaborate* (agent-to-agent messaging). They are complementary, not competing.

### Tier selection decision table

| Scenario | Tier |
|----------|------|
| Agents are nodes in the same LangGraph graph | Tier 1: Shared state |
| Agents in same process, decoupled autonomous routing | Tier 2: Tool-based handoffs |
| Agents in different services, same framework | Tier 3: A2A |
| Cross-vendor, cross-framework agents | Tier 3: A2A |

For each agent boundary in the system, assign a tier and justify the choice.

## Step 3: Design the context transfer contract

When an agent hands off to another, the receiving agent needs sufficient context to continue without re-asking the user. This is the most common failure point in multi-agent systems.

### The HandoffContext contract

Every handoff must transfer these five fields:

```python
class HandoffContext(TypedDict):
    original_request: str           # What the user originally asked
    work_completed: list[str]       # What has already been done
    relevant_findings: dict         # Key data accumulated so far
    handoff_reason: str             # Why this agent is handing off
    continuation_instructions: str  # What the receiving agent should do next
```

Design each field for the specific system. The `relevant_findings` dict should contain only what the receiving agent needs -- not the entire conversation history.

### The telephone game problem

In agent chains (A -> B -> C -> D), context degrades at each handoff. Each agent summarises what came before, losing detail. By agent D, the original request may be unrecognisable.

The fix: use a `forward_message` tool pattern. Instead of each agent summarising and forwarding, maintain an immutable record of the original request and key findings that flows through the chain unchanged. Each agent appends to `work_completed` and `relevant_findings` but never modifies `original_request`.

```
Without forward_message (telephone game):

  User request --> Agent A summarises --> Agent B summarises -->
  Agent C gets a distorted version of the original request

With forward_message pattern:

  User request --> stored in original_request (immutable)
                   Agent A appends findings
                   Agent B appends findings
                   Agent C reads original_request directly
```

For each handoff in the system, define what goes into each HandoffContext field.

## Step 4: Select a communication architecture pattern

These patterns describe how messages flow through the system. The topology (from `agentic-architecture`) constrains which patterns apply.

### Pipeline (sequential)

```
  [Research] --> [Analysis] --> [Writing] --> [Review]
```

Fixed-stage handoffs. Each agent completes its work and passes to the next. Simple and predictable. Good for well-defined workflows where stages are known in advance.

Communication design: each stage produces a structured output that the next stage consumes. Define the schema for each stage boundary.

### Hub-and-spoke (supervisor)

```
                    [Supervisor]
                   /     |      \
            [Agent A] [Agent B] [Agent C]
```

Central supervisor routes to specialists, validates outputs, assembles final response. The supervisor sees all communication.

Communication design: supervisor sends task instructions down; agents return structured results up. Define the instruction format and result format.

### Swarm (decentralised)

```
  [Agent A] <--> [Agent B] <--> [Agent C]
       \                          /
        +---- [Agent D] ---------+
```

Agents route autonomously via handoff tools. No central coordinator sees all messages. Better resilience, harder to debug and audit.

Communication design: each agent needs handoff tools for every agent it might route to. Define the handoff tool descriptions carefully -- they are the routing mechanism.

### Scatter-gather (parallel)

```
              [Orchestrator]
             / |    |    |  \
          [W1][W2][W3][W4][W5]
             \ |    |    |  /
              [Aggregator]
```

Orchestrator fans out to N agents simultaneously, collects all outputs, synthesises. Best for independent subtasks.

Communication design: define the fan-out instruction format, the worker result format, and the aggregation strategy. All workers must return results in a compatible schema.

For the system being designed, select the pattern and specify the message formats at each boundary.

## Step 5: Design communication failure handling

Multi-agent communication fails. Design for these failure modes:

### Bad output from a subagent

The most common failure. A subagent returns output that is:
- **Off-topic**: the agent misunderstood the task or drifted
- **Incomplete**: the agent returned partial results
- **Malformed**: the output doesn't match the expected schema
- **Hallucinated**: the agent fabricated data not grounded in its inputs

Mitigation strategies:
1. **Schema validation**: validate every inter-agent message against a defined schema before accepting it
2. **Output review node**: a lightweight validation step between agents that checks relevance and completeness
3. **Retry with feedback**: if output fails validation, retry the agent with specific feedback about what was wrong (max 2-3 retries)
4. **Fallback routing**: if an agent consistently fails, route to an alternative agent or escalate to supervisor

### Communication timeout

For A2A (Tier 3) communication, agents may not respond.

Mitigation:
- Set explicit deadlines on all A2A calls
- Implement retry with exponential backoff
- Define a fallback behaviour when a remote agent is unreachable

### Context overflow

Handoff context grows too large for the receiving agent's context window.

Mitigation:
- Summarise `work_completed` entries beyond a threshold
- Keep `relevant_findings` to key-value pairs, not full documents
- Use references (IDs, URLs) instead of inline data for large artifacts

For each failure mode relevant to the system, define the handling strategy.

## Step 6: Present the communication contract

Present the decisions as a structured Communication Contract. Use this format:

```
# Communication Contract: [System Name]

## System Overview
[1-2 sentences: what agents exist and what they do]

## Communication Primitives
[For each agent boundary: which tier and why]

## Context Transfer Contracts
[For each handoff: what goes in each HandoffContext field]

## Message Flow Pattern
[Which architecture pattern; message format at each boundary]

## Failure Handling
[For each relevant failure mode: detection and response]

## A2A Integration (if applicable)
[Agent Card design, endpoint configuration, context/task ID strategy]
```

Ask the user if the contract looks right before considering this complete.
