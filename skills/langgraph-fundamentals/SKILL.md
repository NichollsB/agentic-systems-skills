---
name: langgraph-fundamentals
description: Design and build LangGraph graphs — state schemas, node functions, edges, routing, loop guards, subgraphs, parallelism, checkpointing, streaming, and human-in-the-loop. Use this skill when the user needs to implement a LangGraph graph from scratch, design a TypedDict state schema, write node functions, wire edges with routing logic, add loop guards, implement scatter-gather parallelism, choose a checkpointer, set up streaming, or add human-in-the-loop interrupts. Also use when the user says things like "help me build this in LangGraph", "design my graph state", "wire my nodes together", "my graph loops forever", "which checkpointer should I use", "add human review to my graph", or is implementing any LangGraph-based system.
---

# LangGraph Fundamentals

This skill guides the design and implementation of a complete LangGraph graph. It covers the full progression: state schema → node functions → edge wiring → advanced features (subgraphs, parallelism, checkpointing, streaming, HITL).

Use the steps below to reason through the design, but present the output as a complete graph implementation — state schema, node stubs, wiring code, and configuration — with rationale for each decision.

When including flow diagrams, use plain ASCII characters (`|`, `-`, `+`, `>`) not Unicode box-drawing characters — they render incorrectly in many environments.

## Step 1: Understand the graph's purpose

Before designing anything, get clear on what the graph does. Either ask the user or extract from context:

- What are the major phases or stages?
- What decisions does the graph need to make (routing points)?
- What data flows between stages?
- Does it need persistence, human-in-the-loop, parallelism, or streaming?

If the user has already made architecture decisions (possibly using the `agentic-architecture` skill), use those as input.

## Step 2: Design the state schema

State schema design is the most important decision and should happen first. A poor schema touches every node and every test.

### What belongs in state

Design around **what the graph needs to route on**, not what individual nodes use internally. Three categories:

1. **Routing fields** — edges read these to decide the next node. Examples: `current_phase`, `confidence_score`, `error_count`, `reflection_count`.
2. **Persisted results** — downstream nodes consume upstream outputs. Examples: `messages`, `plan`, `tool_results`, `final_output`.
3. **Metadata** — observability and debugging. Examples: `session_id`, `trace_id`.

Transient values used and discarded within a single node belong in **local variables**, not state.

### Schema rules

- Use `TypedDict` with `total=False` — allows nodes to return partial updates
- Use `Annotated[list, add_messages]` for message history — standard reducer for conversations
- **Reducers are mandatory** when parallel branches write to the same field — without them: `InvalidUpdateError`
- Keep state **serialisable** — JSON-compatible types only (checkpointing requires this)
- Separate `InputState` / `OutputState` if the graph has a public API boundary

### Choosing reducers

| Reducer | Use when | Example |
|---------|----------|---------|
| `add_messages` | Message lists (deduplicates by ID) | `messages: Annotated[list, add_messages]` |
| `operator.add` | Collecting results from parallel workers | `results: Annotated[list, operator.add]` |
| Custom function | Merging dicts, taking max, unions | `def merge(a, b): return {**a, **b}` |
| No reducer | Field written by one node at a time | `confidence_score: float` |

Only add reducers where parallel writes actually happen.

## Step 3: Design node functions

Each node does **exactly one thing**. If describing what a node does requires "and" — split it.

### Node conventions

- Accept state, return a **partial update dict** — only changed fields
- Return `{}` for no-op — explicit, not implicit
- **Never mutate** the incoming state object
- Accept dependencies via **injection** (model factories, config) — not hardcoded
- Routing functions are **pure functions on state** — no LLM calls, no side effects

### Common node patterns

| Pattern | What it does |
|---------|-------------|
| **LLM call** | Reads context from state, calls LLM, writes result |
| **Tool execution** | Reads tool call from state, executes, writes result |
| **Validation** | Reads output, scores it, writes confidence/errors |
| **Load/save** | Reads from or writes to external memory at graph entry/exit |
| **Skill node** | Loads a SKILL.md as system message, calls LLM with it. See `addendums/skill-integration-patterns.md` for the dual-use wrapper pattern |

### Testability check

Every node must be testable in isolation. If it can't be tested without wiring the full graph, it has too many dependencies.

```python
# Routing functions — pure, no LLM
def test_route_escalates_at_max_errors():
    state = {"error_count": 3, "confidence_score": 0.5}
    assert route_after_validation(state) == "escalate"

# LLM nodes — inject a mock
def test_plan_node():
    mock_llm = GenericFakeChatModel(messages=iter([
        AIMessage(content='{"steps": ["search", "analyse"]}')
    ]))
    result = plan_node(state, model_factory=MockFactory(mock_llm))
    assert len(result["plan"]) == 2
```

## Step 4: Wire edges

Start with the simplest possible wiring. Add complexity only where the graph genuinely branches.

### Edge types

| Type | Use when |
|------|----------|
| **Static** | Node A always flows to Node B |
| **Conditional** | Next node depends on state |
| **Entry** | First node: `builder.add_edge(START, "intake")` |
| **Finish** | Terminal: `builder.add_edge("output", END)` |

Prefer static edges for linear flows. The design test for conditional edges: if the routing function can't be written in 5 lines, redesign the nodes.

### Routing functions

```python
def route_after_validation(state) -> Literal["retry", "format_output", "escalate"]:
    if state["error_count"] >= 3:
        return "escalate"
    if state["confidence_score"] < 0.7:
        return "retry"
    return "format_output"
```

Use `Command(goto=..., update={...})` when a node needs to both update state and control routing.

### Loop guards

**Every cycle must have a loop guard.** Guard goes before the quality gate so the loop always terminates:

```python
def should_continue(state) -> Literal["reflect", "finalise"]:
    if state.get("reflection_count", 0) >= MAX_REFLECTIONS:  # guard first
        return "finalise"
    if state.get("quality_score", 0) >= THRESHOLD:            # quality second
        return "finalise"
    return "reflect"
```

For every cycle, document: counter field, max value, and what happens at the limit.

## Step 5: Add advanced features (as needed)

Only include what the graph actually requires. Skip sections that don't apply.

### Subgraphs

Use for: reusable capabilities across graphs, state isolation, or encapsulating unequal-length parallel branches. **Not** for code organisation — use Python modules for that.

- Subgraph has its own `StateGraph` with its own schema
- Same-name keys are automatically mapped at the boundary
- This is how you prevent state bleed in multi-agent systems

### Parallelism

**Static fan-out** — branches known at compile time:
```python
builder.add_edge("start", "branch_a")
builder.add_edge("start", "branch_b")
```

**Dynamic fan-out (scatter-gather)** — runtime N via `Send()`:
```python
def scatter(state) -> list[Send]:
    return [Send("worker", {"task": t}) for t in state["tasks"]]
```
State needs a reducer to collect results: `results: Annotated[list, operator.add]`

**Pipeline parallelism** — independent sequential stages operating on different state fields. Express as fan-out from a single start node where each branch works on its own field. Useful when stages don't share data.

A slow worker blocks the entire superstep — encapsulate slow paths in subgraphs with timeouts. Benchmarks show 137x speedup for parallel search operations.

### Checkpointer wiring

Compile the graph with a checkpointer to enable state persistence:
```python
from langgraph.checkpoint.memory import MemorySaver
graph = builder.compile(checkpointer=MemorySaver())
```

Quick reference for which checkpointer to use:
- **Dev/testing without HITL** → `MemorySaver`
- **Dev/testing with HITL or any persistence need** → `SqliteSaver`
- **Production** → `PostgresSaver`

**If the graph uses `interrupt()`, do not use `MemorySaver`** — human review can take hours or days, and `MemorySaver` loses state on restart.

For detailed checkpointer selection, setup, connection pooling, and cross-thread memory, see the `memory-and-persistence` skill. For MCP tool integration patterns, see `addendums/mcp-langgraph-patterns.md`.

### Streaming

| Mode | What it streams | Use when |
|------|----------------|----------|
| `"messages"` | Token-by-token LLM output | Interactive chat |
| `"updates"` | Node-level state updates | Dashboards |
| `"custom"` | Whatever you emit via `get_stream_writer()` | Progress bars, status |

Combine modes: `stream_mode=["updates", "custom"]`. Pass `subgraphs=True` to stream from subgraphs. Use `version="v2"` for the latest streaming format.

For custom progress indicators, use `get_stream_writer()`:
```python
from langgraph.config import get_stream_writer
writer = get_stream_writer()
writer({"status": "Processing step 3 of 5..."})
```

### Human-in-the-loop

Use `interrupt()` to pause for human input. State is checkpointed at the interrupt point.

```python
# Inside the node — pause execution
def review_node(state) -> dict:
    decision = interrupt({"question": "Approve?", "draft": state["draft"]})
    return {"approved": decision == "yes"}
```

The caller handles the interrupt/resume loop:
```python
config = {"configurable": {"thread_id": "session-1"}}
result = graph.invoke(initial_state, config)

while result.get("__interrupt__"):
    interrupt_data = result["__interrupt__"][0]
    user_input = input(f"{interrupt_data.value}: ")
    result = graph.invoke(Command(resume=user_input), config)
```

Critical rules:
- Keep `interrupt()` calls in consistent order — never conditionally skip
- Avoid side effects before `interrupt()` — the entire node re-executes on resume
- Checkpointer must support persistence if review takes time (not `MemorySaver`)

## Step 6: Present the implementation

Output a complete graph implementation:

1. **State schema** — TypedDict with field categories commented and reducers annotated
2. **Node stubs** — function signatures with what each reads, writes, and why
3. **Graph wiring** — `StateGraph` builder code with all edges and routing functions
4. **Loop guards** — for every cycle: counter, max, behaviour at limit
5. **Configuration** — checkpointer, streaming mode, thread ID strategy (only if applicable)
6. **Test sketch** — one example test per node type showing independent testability

Note which advanced features were included and which were skipped, with reasoning.
