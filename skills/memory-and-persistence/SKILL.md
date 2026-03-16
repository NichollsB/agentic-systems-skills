---
name: memory-and-persistence
description: Set up LangGraph persistence — checkpointer selection, PostgresSaver/SqliteSaver configuration, cross-thread memory with PostgresStore, load/save node patterns, and context rot compaction. Use this skill when the user needs to persist graph state across sessions, choose between MemorySaver/SqliteSaver/PostgresSaver/RedisSaver, set up cross-session memory, implement load/save memory nodes, or handle context rot in long-running agents. Also use when the user says things like "how do I persist state", "my agent forgets between sessions", "set up checkpointing", "which checkpointer should I use", "how do I share memory across threads", or "my agent degrades on long conversations".
---

# Memory and Persistence

This skill sets up the persistence layer for a LangGraph agent — checkpointing for thread-level state, cross-thread memory for knowledge that persists across sessions, and compaction strategies for context rot in long-running conversations.

Use the steps below to reason through the design, but present the output as working configuration code and node patterns with rationale.

## Step 1: Understand the memory requirements

Before choosing infrastructure, get clear on what needs to persist. Either ask the user or extract from context:

- Does the agent need to survive process restarts? (session continuity)
- Does the agent need to remember things across separate conversations? (cross-session memory)
- How long do conversations typically run? (context rot risk)
- Is there human-in-the-loop that introduces long pauses? (durability requirement)
- What environment is this for? (local dev, staging, production)

## Step 2: Understand the four memory types

Agentic systems use a multi-tier memory architecture. Understanding the types helps decide what to persist where.

| Type | What it is | Storage | Lifetime |
|------|-----------|---------|----------|
| **In-context (working)** | Current state object and message history | LangGraph state | Current session, cleared unless checkpointed |
| **Episodic** | Records of past interactions and outcomes — "last time I tried X, Y happened" | PostgresStore or similar | Indefinite, structured as task/actions/outcomes/lessons |
| **Semantic** | General facts, domain knowledge, user preferences | Vector database via RAG | Indefinite |
| **Procedural** | Skills and tool schemas — how to do things | SKILL.md files, tool definitions | Survives compaction, no retrieval overhead |

Most agents need in-context (checkpointer) and episodic (store). Semantic memory is an add-on for knowledge-heavy domains. Procedural memory is handled by the skill and tool systems, not by the persistence layer.

For memory backend selection (Mem0, Zep/Graphiti, Letta, Cognee), see the community `memory-systems` skill. For the memory tier decision table, see `references/decision-memory-tier.md`.

## Step 3: Select a checkpointer

The checkpointer persists graph state at every node transition, enabling resume, replay, and time-travel debugging.

| Checkpointer | Best for | Key characteristics |
|---|---|---|
| **MemorySaver** | Dev/testing without HITL | Zero config, fast. Lost on process restart. |
| **SqliteSaver** | CLI tools, local dev, HITL | Simple file-based persistence. Survives restarts. Single-process only. |
| **PostgresSaver** | Production | Durable, queryable, enterprise-grade. Requires Postgres. |
| **RedisSaver** | High-throughput production | Fast distributed access. Requires Redis 8.0+. |

Selection rules:
- **If the graph uses `interrupt()` for human-in-the-loop, do not use `MemorySaver`** — reviews can take hours or days, and MemorySaver loses state on restart
- **If multiple processes need to access the same state** → PostgresSaver or RedisSaver
- **If you just need local persistence** → SqliteSaver
- **If you're writing tests** → MemorySaver is fine (fast, no cleanup)

### PostgresSaver setup (production)

```python
from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver
from psycopg_pool import AsyncConnectionPool

# Use a connection pool — do not create a new connection per checkpoint
pool = AsyncConnectionPool(
    conninfo="postgresql://user:pass@host:5432/dbname",
    min_size=2,
    max_size=10,
)

checkpointer = AsyncPostgresSaver(pool)
await checkpointer.setup()  # creates tables on first run

graph = builder.compile(checkpointer=checkpointer)
```

### SqliteSaver setup (local dev)

```python
from langgraph.checkpoint.sqlite.aio import AsyncSqliteSaver

checkpointer = AsyncSqliteSaver.from_conn_string("agent_state.db")
graph = builder.compile(checkpointer=checkpointer)
```

### Thread ID strategy

Use structured thread IDs that encode tenant, user, and session:

```python
thread_id = f"tenant-{tenant_id}:user-{user_id}:session-{session_id}"
config = {"configurable": {"thread_id": thread_id}}
result = graph.invoke(inputs, config)
```

This enables querying checkpoints by tenant or user for admin, debugging, and compliance.

## Step 4: Set up cross-thread memory (if needed)

Thread-level checkpointing persists state within a session. Cross-thread memory persists knowledge *across* sessions — things the agent learns that should be available in future conversations.

```python
from langgraph.store.postgres import PostgresStore

store = PostgresStore.from_conn_string(DB_URL)
```

### Load memories node

Wire this as the first node in the graph — it loads relevant memories before the agent starts reasoning:

```python
def load_memories_node(state: AgentState) -> dict:
    memories = store.search(
        namespace=("user_memory", state["user_id"]),
        query=state["messages"][-1].content,
        limit=5
    )
    return {"loaded_memories": [m.value for m in memories]}
```

### Save memories node

Wire this as the last node — it persists outcomes worth remembering:

```python
def save_memory_node(state: AgentState) -> dict:
    if state.get("outcome_worth_saving"):
        store.put(
            namespace=("user_memory", state["user_id"]),
            key=f"outcome_{state['trace_id']}",
            value={
                "task": state["original_task"],
                "approach": state["approach_taken"],
                "outcome": state["final_output"],
                "lessons": state.get("lessons_learned")
            }
        )
    return {}
```

The key design decision: **not everything should be saved**. Only persist outcomes that would change future behaviour — task results, lessons learned, user preferences. Saving everything creates noise that degrades retrieval quality.

## Step 5: Design a compaction strategy (if needed)

Context rot is real — all models experience performance degradation with long contexts. This is not just a cost problem; quality degrades as context grows. Proactive compaction is a correctness requirement for long-running agents.

### Three-tier compaction

| Tier | Storage | What it holds | Trigger |
|------|---------|--------------|---------|
| **Hot** | In-context state | Last 10 turns verbatim | Always present |
| **Warm** | Checkpointer | LLM-generated summary of older turns | At 70-80% context capacity |
| **Cold** | PostgresStore | Structured task records (episodic memory) | Per-session end |

### Observation masking (do this first)

Before resorting to LLM-based summarisation, apply observation masking: keep the last 10 turns verbatim, but mask (remove or truncate) tool observations from older turns. Research shows this cuts costs by **52% while improving solve rates by 2.6%**.

Observation masking is cheaper, faster, and more effective than summarisation. Only escalate to LLM summarisation if masking alone doesn't keep context within budget.

### Compaction trigger

Trigger compaction at **70-80% of context capacity**, not at the limit. Waiting until the context window is full means the compaction prompt itself may not fit, or the model's reasoning quality has already degraded.

## Step 6: Present the configuration

Output:

1. **Checkpointer selection** — which one and why, with setup code
2. **Thread ID strategy** — structured format for the use case
3. **Cross-thread memory** (if needed) — store setup, load/save node patterns, what gets persisted and what doesn't
4. **Compaction strategy** (if needed) — which tier, observation masking configuration, compaction trigger threshold
5. **Environment mapping** — what changes between dev/staging/production (e.g., MemorySaver in tests, SqliteSaver locally, PostgresSaver in prod)

**Supporting reference docs** (load if needed):
- `references/decision-memory-tier.md` — memory type and compaction tier decision tables
- `addendums/context-engineering-strategies.md` — Anthropic's Write/Select/Compress/Isolate framework for context management
