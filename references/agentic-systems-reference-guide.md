# Building Performant Agentic AI Systems: A 2024-2025 Reference Guide

This guide synthesises current best practices across model selection and evaluation, graph architecture, inter-agent communication, self-validation, guardrails, tool design, the AgentSkills.io open standard, token efficiency, LiteLLM, Langfuse observability, and complete project architecture. It is drawn from official documentation, research papers, and production experience from Anthropic, OpenAI, Google, JetBrains, and enterprise practitioners.

---

## 1. Model Selection: Evaluation-Driven Role Assignment

The dominant production pattern is **heterogeneous model routing** -- different models for different roles. The core principle: start with your most capable model everywhere to establish a quality ceiling, then systematically downgrade roles where a cheaper model maintains acceptable quality. Never optimise costs before you have a working quality baseline.

### Role-based model mapping

| Role | Tier | Example models | Key requirement |
|------|------|----------------|-----------------|
| Orchestrator / Planner | Frontier | Claude Opus 4.6, o3, GPT-5 | Complex reasoning, task decomposition |
| Tool calling / Execution | Mid-tier | Claude Sonnet 4.5, GPT-4.1 | Reliable function calling, structured output |
| Reflection / Critique | Mid-tier | Claude Sonnet 4.5, GPT-4o | Nuanced judgment, quality assessment |
| Classification / Routing | Fast/cheap | Claude Haiku 4.5, GPT-4o-mini | Sub-second latency, binary decisions |
| Summarisation / Extraction | Fast/cheap | Claude Haiku 4.5, GPT-4o-mini | Lower stakes, high throughput |
| Validation / Grading | Fast/cheap | Claude Haiku 4.5, GPT-4o-mini | Structural checks, pass/fail scoring |
| Deep reasoning | Reasoning-specialised | o3, o4-mini high effort, Claude extended thinking | Proofs, complex analysis |

Anthropic's own guidance from the tool use docs: **use Claude Opus 4.6 for complex tools and ambiguous queries** -- it handles multiple tools better and seeks clarification when needed. **Use Claude Haiku models for straightforward tools**, though Haiku may infer missing parameters rather than requesting them explicitly.

### The CLASSic evaluation framework for model selection

The enterprise-grade evaluation methodology for model selection in agentic systems is the **CLASSic framework** (Aisera, ICLR 2025), which assesses five dimensions in combination:

- **C**ost: operational expenses including API usage, token consumption, infrastructure overhead
- **L**atency: end-to-end response times under realistic load
- **A**ccuracy: correctness in selecting and executing the right tool/workflow for a given input
- **S**tability: consistency and robustness across diverse inputs, domains, and varying conditions (the metric that catches models that look good on average but have high variance)
- **S**ecurity: resilience against adversarial inputs, prompt injection, and data leaks

This framework is what makes model selection rigorous rather than anecdotal. A model that scores highest on accuracy but lowest on stability is often the wrong choice for a production agentic system -- you need both.

### Eval-driven model selection methodology

Standard static LLM benchmarks (MMLU, HELM) are built for single-shot tasks and do not measure what agents actually do. The correct benchmarks for agentic model selection:

- **Berkeley Function-Calling Leaderboard (BFCL)**: standardised tool calling across thousands of real-world APIs, with AST-correctness scoring. The primary benchmark for selecting models for tool-use roles.
- **SWE-bench Verified**: real-world software engineering on GitHub issues; best proxy for models that need to reason about existing codebases and modify them.
- **AgentBench**: multi-environment evaluation across OS, database, knowledge graph, web shopping, and web browsing tasks. Measures planning, reasoning, tool use, and decision-making in interactive environments.
- **tau-bench**: retail and airline booking domains with explicit `pass@k` metric for consistency evaluation.

The `pass@k` metric is crucial and underused: run the same task k times and measure what fraction of runs succeed. A model with 80% average accuracy but high variance (60% of runs fail) is worse for production than a model with 70% accuracy and near-zero variance.

**Infrastructure effect on benchmarks**: Anthropic's engineering team found that "infrastructure configuration can swing agentic coding benchmarks by several percentage points -- sometimes more than the leaderboard gap between top models." Benchmark scores measured in the right conditions (production-representative prompt lengths, realistic concurrency, correct caching configuration) matter more than abstract leaderboard positions.

### The three-tier routing architecture

| Tier | Models | Roles |
|------|--------|-------|
| Tier 1 (fast/cheap) | Haiku 4.5, GPT-4o-mini | Routing, classification, validation, summaries |
| Tier 2 (mid-range) | Sonnet 4.5, GPT-4.1 | Standard tasks, tool calling, execution, reflection |
| Tier 3 (frontier) | Opus 4.6, o3 | Complex reasoning, planning, high-stakes decisions |

Use a **cheaper model for initial generation and a stronger model for critique/reflection** -- this is the highest-leverage model-routing pattern in reflection-based flows. The reflector is where intelligence is most valuable; the generator can be fast and cheap.

Fallback chains should cross providers for resilience: `claude-sonnet -> gpt-4.1 -> gpt-4o`.

Research from RouteLLM shows routing 90% of traffic to small models yields ~86% cost savings. The operative metric is **cost-normalised accuracy** (CNA = accuracy / cost_per_task), not raw accuracy.

### When to apply the frontier model

Use frontier models when: reasoning requires more than three hops; the task involves novel tool combinations not seen in training; the agent is planning a multi-agent workflow; or the decision is irreversible. Use smaller models everywhere else.

---

## 2. Graph Architecture: Nodes, Edges, State, and Design Standards

LangGraph is an **agentic state machine** -- explicit, replayable, and auditable. Built around Nodes (functions), Edges (transitions), and State (shared typed dictionary). Framework overhead is ~14ms per query.

### State schema design standards

**State schema design is the most important architectural decision and should happen first.** A poor schema is expensive to change later because it touches every node and every test.

Design the schema around **what the graph needs to route on**, not what individual nodes use. Only fields that inform routing decisions or need persistence across multiple nodes belong in state. Transient values used and discarded within a single node belong in local variables.

```python
class AgentState(TypedDict, total=False):
    # Routing fields -- edges read these to determine the next node
    current_phase: Literal["plan", "execute", "validate", "complete"]
    confidence_score: float
    error_count: int
    reflection_count: int

    # Persisted results -- downstream nodes use these
    messages: Annotated[list, add_messages]  # standard reducer
    plan: list[str]
    tool_results: dict[str, Any]
    validation_errors: list[str]
    final_output: str

    # Metadata -- for observability
    session_id: str
    trace_id: str
    original_task: str
```

State schema rules:
- Use `Annotated[list, add_messages]` for message history -- standard reducer for conversational state
- Use `total=False` on TypedDict to allow nodes to return partial updates (only changed fields)
- Reducers are **mandatory** when parallel branches write to the same field -- without them you get `InvalidUpdateError`
- Keep state **serialisable** -- no Python objects, only JSON-compatible types (checkpointing requires this)
- Separate `InputState` / `OutputState` TypedDicts if your graph has a public API contract to enforce at the boundary

### Node design standards

**Each node does exactly one thing.** The single responsibility principle applies here as strictly as in any software system. A node that calls an LLM, parses its output, calls a tool, and updates three state fields is four nodes.

```python
# Bad: one node doing too much
def process_node(state: AgentState) -> AgentState:
    plan = llm.invoke(planning_prompt)      # should be plan_node
    results = execute_plan(plan)            # should be execute_node
    validated = validate_results(results)  # should be validate_node
    return {"plan": plan, "results": results, "validated": validated}

# Good: atomic, independently testable nodes
def plan_node(state: AgentState) -> dict:
    plan = llm.invoke(planning_prompt(state["messages"]))
    return {"plan": plan.steps}

def execute_node(state: AgentState) -> dict:
    results = [execute_step(s) for s in state["plan"]]
    return {"tool_results": dict(zip(state["plan"], results))}

def validate_node(state: AgentState) -> dict:
    score = evaluator.score(state["tool_results"])
    return {"confidence_score": score}
```

Node return conventions:
- Return a partial state update (dict with only changed fields), not the full state
- Return `{}` to signal a no-op (explicit, not implicit)
- Never mutate the incoming state object

### Edge and routing design

Prefer **simple static edges** for linear flows. Use conditional edges only where behaviour genuinely branches. The test: if you cannot write the routing function in 5 lines, redesign the nodes.

```python
def route_after_validation(state: AgentState) -> Literal["retry", "format_output", "escalate"]:
    if state["error_count"] >= 3:          # loop guard -- always check first
        return "escalate"
    if state["confidence_score"] < 0.7:
        return "retry"
    return "format_output"

builder.add_conditional_edges("validate_node", route_after_validation)
```

**Loop guards are mandatory for every cycle in the graph.** Check the guard condition before the quality gate so a loop always terminates regardless of what the model produces:

```python
def should_continue_reflection(state: AgentState) -> Literal["reflect", "finalise"]:
    if state.get("reflection_count", 0) >= MAX_REFLECTIONS:  # loop guard first
        return "finalise"
    if state.get("quality_score", 0) >= QUALITY_THRESHOLD:   # quality gate second
        return "finalise"
    return "reflect"
```

Use `Command(goto=..., update={...})` when a node needs to both update state and control routing:

```python
def execute_node(state: AgentState) -> Command:
    result = run_tool(state["next_tool"])
    if result.error:
        return Command(goto="handle_error", update={"last_error": result.error})
    return Command(goto="validate", update={"tool_results": result.data})
```

### Subgraph design standards

Use subgraphs for: (a) reusable capability used in multiple graphs, (b) state isolation between the subgraph and parent, (c) encapsulating unequal-length parallel branches. Do not create subgraphs purely to organise code -- that is what Python modules are for.

Subgraph state isolation rules:
- The subgraph has its own `StateGraph` with its own schema
- Keys with the same name are automatically mapped at the boundary
- Subgraph does not read parent-only fields; parent does not read subgraph-internal fields
- This is the boundary that prevents state bleed between agents in multi-agent systems

### Parallelism patterns

**Scatter-gather**: distribute to N parallel workers, collect results. Use `Send()` for dynamic N (known only at runtime):

```python
def scatter(state: AgentState) -> list[Send]:
    return [Send("worker", {"task": t}) for t in state["tasks"]]

class AgentState(TypedDict):
    results: Annotated[list, operator.add]  # reducer: concatenate from all workers
```

**Pipeline parallelism**: independent sequential stages operating on different state fields -- express via fan-out from a single start node.

Benchmarks show **137x speedup** for parallel search operations. A slow worker blocks the entire superstep -- encapsulate slow paths in their own subgraphs with timeouts.

### Checkpointing

| Checkpointer | Best for | Key characteristics |
|---|---|---|
| **MemorySaver** | Development/testing | Fast, zero config, lost on restart |
| **SqliteSaver** | CLI tools, local dev | Simple persistence, survives restarts |
| **PostgresSaver** | **Production recommended** | Durable, queryable, enterprise-grade |
| **RedisSaver** | High-throughput production | Fast distributed access, requires Redis 8.0+ |

Use structured thread IDs: `"tenant-{id}:user-{id}:session-{id}"`. For cross-thread (cross-session) memory, use `PostgresStore` or `RedisStore` with namespaced keys.

### The interrupt mechanism for human-in-the-loop

```python
config = {"configurable": {"thread_id": "session-1"}}
result = graph.invoke(initial_state, config)

while result.get("__interrupt__"):
    interrupt_data = result["__interrupt__"][0]
    print(f"Agent asks: {interrupt_data.value}")
    user_input = input("> ")
    result = graph.invoke(Command(resume=user_input), config)
```

Critical: keep `interrupt()` calls in consistent order, never conditionally skip them within a node, and avoid side effects before `interrupt()` since the entire node re-executes on resume.

### Streaming for interactive CLI tools

```python
for chunk in graph.stream(inputs, stream_mode="messages", version="v2"):
    message_chunk, metadata = chunk["data"]
    if message_chunk.content:
        print(message_chunk.content, end="", flush=True)
```

Use `get_stream_writer()` via `stream_mode="custom"` for custom progress indicators. Combine modes (`stream_mode=["updates", "custom"]`) for dashboards. Pass `subgraphs=True` to stream from subgraphs.

### When LangGraph adds value versus overhead

Use LangGraph for: complex workflows with branches/retries/cycles, durable execution, human-in-the-loop, multi-agent routing, production observability. Use pure Python for simple linear one-shot workflows or quick prototypes.

---

## 3. Self-Validation, Reflection, and Self-Correction Patterns

**Self-correction is the single most powerful technique for elevating agent output quality.** LangGraph's cyclical graph support makes these patterns first-class rather than bolted-on. The key insight: reflection takes extra LLM calls but produces significantly higher quality outputs -- particularly for code generation, long-form writing, and structured data extraction where quality can be assessed programmatically or by the LLM itself.

### The three reflection architectures

**Basic reflection (generate-critique-revise)**: the simplest and most broadly applicable. A generator produces output; a reflector prompt critiques it; the generator revises based on the critique. 2-5 iteration max with a mandatory loop guard. Use a **stronger model for critique and a cheaper model for initial generation** -- the reflector is where intelligence is most valuable.

```
graph: generate -> grade -> [route_reflection] -> reflect -> generate (loop)
                                                -> finalise (exit when quality passes or MAX_REFLECTIONS reached)
```

**Reflexion (reflection with external grounding)**: extends basic reflection by grounding the critique in external data -- tool observations, search results, retrieved facts. The actor explicitly enumerates what it got wrong, uses tools to verify claims, and provides citations. Better than basic reflection for fact-sensitive tasks. The external grounding converts vague critique ("this is inaccurate") into specific corrections ("claim X is false -- search result Y says Z").

```
graph: draft -> execute_tools -> revise -> [loop check] -> draft (loop) | END
The revisor receives: original query + draft + tool observations + reflection
```

**LATS (Language Agent Tree Search)**: the most powerful and expensive. Generates multiple candidate responses, evaluates each with a reward function (UCT score = value/visits + exploration bonus), uses MCTS-style search to select the best path. Saves the best trajectory to external memory. Use only for high-stakes decisions where compute budget permits -- 10-50x more expensive than basic reflection.

### Self-correcting RAG (Corrective RAG pattern)

For retrieval-augmented flows, add grading nodes that evaluate documents and outputs before proceeding:

```
retrieve -> grade_documents -> [route]
    -> "relevant" -> generate -> grade_output -> [route]
        -> "hallucination_detected" -> transform_query -> retrieve (retry)
        -> "useful" -> END
    -> "irrelevant" -> transform_query -> web_search -> generate
```

Grade documents for relevance before generating. Grade generated output against documents (hallucination check) and against the question (usefulness check). This catches poor retrieval early and avoids hallucinations compounding through subsequent steps.

### Validation nodes as first-class graph citizens

A dedicated `validate_node` runs programmatic checks before LLM-based quality checks. Programmatic checks are instant and free; LLM checks are expensive and slow. Never combine both in the generator node.

```python
def validate_node(state: AgentState) -> dict:
    output = state["draft_output"]

    # Programmatic checks first (free, instant)
    errors = []
    if not output.get("summary"):
        errors.append("Missing required field: summary")
    if len(output.get("recommendations", [])) < 1:
        errors.append("Must include at least one recommendation")
    if not is_valid_json_schema(output, OUTPUT_SCHEMA):
        errors.append("Output does not conform to expected schema")

    if errors:
        return {
            "validation_errors": errors,
            "error_count": state.get("error_count", 0) + 1,
            "confidence_score": 0.0
        }

    # Semantic check (cheap model -- only runs if programmatic checks pass)
    score = validator_llm.invoke(grading_prompt(state["messages"], output))
    return {"confidence_score": float(score), "validation_errors": []}
```

### The plan-validate-execute pattern

For complex multi-step tasks, structure the graph explicitly around a validation gate:

```
parse_request -> plan -> validate_plan -> [route]
    -> "plan_invalid" -> replan -> validate_plan (loop with guard)
    -> "plan_valid" -> execute_steps (parallel) -> aggregate -> validate_output
        -> "output_invalid" -> reflect -> execute_steps (retry)
        -> "output_valid" -> format -> END
```

The validation node between plan and execution is the most valuable investment -- it catches structural problems before expensive execution happens.

---

## 4. Inter-Agent Communication Patterns

### Communication primitives: three tiers

**Tier 1: Shared state** -- the primary mechanism for agents within a single LangGraph graph. All agents read and write the same TypedDict state. Zero-overhead, serialisable, checkpointable, auditable. Use by default for intra-graph communication.

**Tier 2: Tool-based handoffs** -- for agents within the same process needing decoupled communication. An agent calls a `transfer_to_<agent>` tool, routing control without a central coordinator. This is the **swarm pattern**:

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

Swarm differs from supervisor: in swarm, each agent decides when it is out of scope; in supervisor, a central coordinator makes all routing decisions.

**Tier 3: A2A protocol** -- for agents running in separate processes or on different systems.

### The Agent2Agent (A2A) protocol

Google's Agent2Agent protocol (released April 2025) is an open standard using JSON-RPC 2.0 over HTTP/SSE. LangGraph natively supports A2A via LangGraph Agent Server (langgraph-api >= 0.4.21). This solves cross-framework agent coordination -- LangGraph, CrewAI, AutoGen, and OpenAI Agents SDK agents can now interoperate.

**Core concepts:**
- **Agent Card**: a machine-readable manifest at `/.well-known/agent.json` describing capabilities, skills, I/O modes, and the A2A endpoint URL
- **Context ID**: groups messages into a conversation thread (analogous to `thread_id`)
- **Task ID**: identifies each individual request within a conversation
- **RPC methods**: `message/send` (synchronous), `message/stream` (SSE streaming), `tasks/get` (async polling)

**LangGraph A2A compatibility**: any LangGraph agent with a `messages` key in state is automatically A2A-compatible when deployed via LangGraph Agent Server:

```python
class AgentState(TypedDict):
    messages: Annotated[list, add_messages]  # required for A2A compatibility

# Calling an A2A agent from another LangGraph graph
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
                    "contextId": state.get("a2a_context_id"),  # reuse for multi-turn
                }
            }
        }
        response = await session.post(SPECIALIST_URL + "/a2a", json=payload)
        result = await response.json()
        return {"specialist_response": extract_text(result)}
```

**A2A vs MCP:** MCP extends what a single agent can do (tool access). A2A expands how agents collaborate (agent-to-agent messaging). They are complementary.

| Scenario | Mechanism |
|----------|-----------|
| Agents in same graph/process | Shared state (Tier 1) |
| Agents in same process, decoupled routing | Tool-based handoffs (Tier 2) |
| Agents in different services, same framework | A2A (Tier 3) |
| Cross-vendor, cross-framework agents | A2A (Tier 3) |

### Inter-agent context transfer contract

When an agent hands off, the receiving agent needs sufficient context to continue without re-asking the user:

```python
class HandoffContext(TypedDict):
    original_request: str           # What the user originally asked
    work_completed: list[str]       # What has already been done
    relevant_findings: dict         # Key data accumulated so far
    handoff_reason: str             # Why this agent is handing off
    continuation_instructions: str  # What the receiving agent should do next
```

### Communication architecture patterns

**Pipeline (sequential)**: fixed-stage handoffs. Research -> Analysis -> Writing -> Review. Simple, predictable, good for well-defined workflows.

**Hub-and-spoke (supervisor)**: central supervisor routes to specialists, validates outputs, assembles final response. Good for multi-domain tasks requiring quality control.

**Swarm (decentralised)**: agents route autonomously via handoff tools. Better resilience, harder to debug and audit. Good for exploratory workflows.

**Scatter-gather (parallel)**: orchestrator fans out to N agents simultaneously, collects all outputs, synthesises. Best for independent subtasks.

---

## 5. Guardrails, Security, and Trust Boundaries

**Building the agent is only half the job. Building its constraints is the other half.** Agentic systems that can take real-world actions -- refunds, database writes, API calls, email sends -- need guardrails that are architectural, not cosmetic.

### The defence-in-depth guardrail stack

Effective guardrails operate in layers. No single layer is sufficient.

**Layer 1: Pre-execution checks (circuit breakers)**

Run before any irreversible tool is invoked. This is the most important layer -- it prevents harm before it happens:

```python
def pre_tool_check(tool_name: str, args: dict, state: AgentState) -> CheckResult:
    checks = [
        check_authorisation(tool_name, args, state["user_role"]),
        check_schema(tool_name, args),
        check_rate_limits(tool_name, state["session_id"]),
        check_risk_tier(tool_name, args, state["risk_threshold"]),
        check_policy_compliance(tool_name, args, state["tenant_id"]),
    ]
    failures = [c for c in checks if not c.passed]
    if failures:
        return CheckResult(blocked=True, reasons=[f.message for f in failures])
    return CheckResult(blocked=False)
```

**Layer 2: Runtime anomaly detection**

Monitors execution for unexpected patterns -- signs of prompt injection, unusual tool call sequences, or agents going off-task:

```python
class AnomalyDetector:
    def check(self, action: ToolCall, context: AgentState) -> AnomalyResult:
        if not self.is_relevant(action, context["original_task"]):
            return AnomalyResult(flag=True, type="task_drift")
        if self.looks_like_exfiltration(action):
            return AnomalyResult(flag=True, type="exfiltration_risk")
        if self.contains_injection_patterns(action.args):
            return AnomalyResult(flag=True, type="prompt_injection")
        return AnomalyResult(flag=False)
```

**Layer 3: Output guardrails**

Validate agent outputs before they reach users or downstream systems:
- **Schema validation**: does output conform to the declared JSON schema?
- **PII scanning**: does output contain sensitive data that should not be exposed?
- **Hallucination detection**: are claims grounded in retrieved context or tool results?
- **Policy compliance**: does output violate content or business policies?

**Layer 4: Human-in-the-loop escalation (final guardrail)**

For high-stakes actions exceeding automated risk thresholds. A mature HITL system pauses with an idempotency key, packages a compact case file, routes to the correct reviewer (finance for transactions, SRE for infra changes), and feeds outcomes back into detectors and policies. HITL is not a crutch for poorly designed systems -- it is the final guardrail, rarely invoked but decisive when necessary.

### Guardrail timing: three patterns

**Async (stream first, validate later)**: zero latency impact; agent streams while guardrails run in parallel; corrections issued post-hoc. Appropriate for low-stakes internal tools.

**Partial streaming with progressive validation**: validate intent and risk tier synchronously; stream response; apply output checks. Balanced approach for customer-facing tools.

**Synchronous (validate before responding)**: full pre-check before any output. Required for high-stakes irreversible actions (financial transactions, database writes, access provisioning). Adds latency but is the only safe option when mistakes cannot be corrected.

### Trust boundaries and least privilege

Agents should have exactly the permissions they need and nothing more:

```python
class AgentPermissions:
    allowed_tools: list[str]          # explicit allowlist, not denylist
    allowed_data_sources: list[str]
    can_write: bool
    can_call_external_apis: bool
    max_budget_usd: float
    allowed_tenant_ids: list[str]     # prevents cross-tenant data access
    token_expiry: datetime            # time-limited credentials
```

**Trust tiers for multi-agent systems:**

| Tier | Source | Trust level | What is permitted |
|------|--------|-------------|-------------------|
| **Gold** | System-generated, verified | Full | Read/write, external calls, sensitive data |
| **Silver** | Internal agents, validated | Partial | Read/write own namespace, internal APIs |
| **Untrusted** | User input, external agents, cloned repos | Restricted | Read-only, sandboxed, no external calls |

Apply trust tiers to retrieved content and A2A agent messages, not just user inputs. A compromised downstream A2A agent should not have silver trust by default.

**Memory hygiene:**
- Use TTLs on all persisted memories
- Purge or snapshot/rotate long-lived memories -- stale context causes incorrect decisions
- Restrict what gets persisted by default
- Sanitise external content before writing to vector stores (strip model-control tokens, apply PII redaction)
- Maintain a quarantine path for user-generated content before it enters retrieval

### Prompt injection defence

Prompt injection is the primary attack vector. Defence layers:

1. **Input sanitisation**: strip or escape model-control tokens before they enter prompts
2. **Structured prompts**: use XML tags to delineate user content from system instructions
3. **Output schema enforcement**: structured outputs constrain what the model can express
4. **Pre-tool checks**: validate tool arguments against expected formats -- injected instructions produce malformed args
5. **Restricted field flow**: allow/deny lists for which state fields can flow into prompts

The most dangerous pattern is allowing unsanitised external content (web pages, documents, emails) to flow directly into reasoning. Always intermediate with a read/summarise node before content enters a decision-making node.

---

## 6. Memory Architecture Patterns

Memory in agentic systems is a multi-tier architecture that enables reasoning across sessions, learning from experience, and avoiding repeated mistakes.

### The four memory types

**In-context (working memory)**: the current state object and message history. Finite, expensive, cleared between sessions unless checkpointed. This is what the agent is actively thinking about.

**Episodic memory**: records of past interactions and outcomes. Supports reasoning like "last time I tried X, Y happened." Key format: `task -> actions -> outcomes -> lessons_learned`.

**Semantic memory**: general facts, domain knowledge, user preferences. Stored in a vector database, accessed via RAG. Persists indefinitely.

**Procedural memory**: skills and how to use tools -- encoded in SKILL.md files and tool schemas. Survives context compaction and transfers across sessions without retrieval overhead.

### Memory architecture for interactive CLI tools

```python
from langgraph.checkpoint.postgres import PostgresSaver
from langgraph.store.postgres import PostgresStore

# Thread-level memory: persists within a conversation session
checkpointer = PostgresSaver.from_conn_string(DB_URL)

# Cross-thread memory: persists across sessions, shared across threads
store = PostgresStore.from_conn_string(DB_URL)

def load_memories_node(state: AgentState) -> dict:
    memories = store.search(
        namespace=("user_memory", state["user_id"]),
        query=state["messages"][-1].content,
        limit=5
    )
    return {"loaded_memories": [m.value for m in memories]}

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

### Context rot and compaction strategy

Chroma's research (Context-Rot, 2025) confirms that **all models experience performance degradation with long contexts**. The problem is not just cost -- quality degrades as context grows. This makes proactive compaction a correctness requirement, not just a cost optimisation.

| Tier | Storage | Retention | Trigger |
|------|---------|-----------|---------|
| **Hot** (active turns) | In-context state | Last 10 turns verbatim | Always |
| **Warm** (session summary) | Checkpointer | LLM-generated summary | At 70-80% context capacity |
| **Cold** (episodic archive) | PostgresStore | Structured task records | Per-session end |

JetBrains research (2025): **observation masking** (keeping latest 10 turns, masking older tool observations) cuts costs by **52% while improving solve rates by 2.6%** on SWE-bench. Use this before LLM-based summarisation, which adds its own latency and cost. Trigger compaction at 70-80% of context capacity, not at the limit.

---

## 7. Tool Design: The Agent-Computer Interface

Anthropic: "Think about how much effort goes into human-computer interfaces (HCI), and plan to invest just as much effort in creating good **agent-computer interfaces** (ACI)."

### Schema design that reduces LLM mistakes

**Tool descriptions are a contract between you and the LLM.** They determine when a tool is called, with what parameters, and how the output is interpreted. Underspecified descriptions cause wrong-tool selection; overlapping descriptions cause indecision.

**Strict mode for guaranteed schema conformance**. Without strict mode, a booking system asking for `passengers: int` might receive `passengers: "two"` or `passengers: "2"`, breaking downstream functions:

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

**Tool Use Examples** (Anthropic advanced tool use, November 2025): JSON schemas define what is structurally valid, but cannot express usage patterns -- when to include optional parameters, which combinations make sense, or what conventions your API expects. Tool use examples provide this guidance:

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

Anthropic internal testing: adding examples improved tool accuracy from **72% to 90%** on complex parameter handling. Each example adds ~20-100 tokens to prompt cost.

### Tool Search Tool: on-demand discovery

The **Tool Search Tool** (Anthropic, November 2025) solves a critical scaling problem. As agents integrate hundreds of tools, stuffing all definitions into context upfront can consume 50,000+ tokens before the agent reads a single user request. The Tool Search Tool allows the agent to search for and load tools on demand, keeping only relevant tool definitions in context for the current task:

```python
tools = [
    {"type": "tool_search_tool_regex_20251119", "name": "tool_search_tool_regex"},
    {"type": "code_execution_20250825", "name": "code_execution"},
    # Your tools -- each marked with defer_loading=True for dynamic discovery
]
```

This moves tool use from simple function calling toward intelligent orchestration, enabling agents to work across hundreds of tools without context bloat.

### Granularity: composite tools over atomic wrappers

Build **a few thoughtful composite tools targeting specific high-impact workflows** rather than wrapping every API endpoint individually. Instead of `list_users` + `list_events` + `create_event`, implement `schedule_event` that handles the full workflow internally, including error recovery.

Observable signals for consolidating tools: repeated multi-tool sequences in Langfuse traces (the agent always calls A then B then C), lots of redundant tool calls suggesting pages of results are being fetched repeatedly, and high tool error rates suggesting the LLM is calling tools with poor parameters.

### Tool result formatting for token efficiency

Return only **high-signal information**. Resolving UUIDs to human-readable names -- `{channel_name: "#general", channel_id: "C01234"}` vs `{id: "C01234"}` -- significantly reduces hallucinations in downstream reasoning because the LLM reasons better on semantically meaningful content.

**The `response_format` pattern**: implement a `response_format` enum parameter that lets the agent control verbosity:

```python
# Concise: ~72 tokens -- for planning and routing
{"name": "Alice Chen", "role": "Engineer", "user_id": "U1234"}

# Detailed: ~206 tokens -- for generating final output
{"name": "Alice Chen", "role": "Engineer", "user_id": "U1234",
 "email": "alice@company.com", "timezone": "PST", "manager": "Bob Smith", ...}
```

This allows intermediate steps to use cheap/fast tool responses, while final synthesis uses detailed responses only when needed.

**Token limits on tool responses**: enforce limits on what returns to context. Claude Code restricts tool responses to **25,000 tokens by default**. When truncating, include steering guidance: `"[First 50 results shown. Use offset=50 to see more, or add filters to narrow results.]"` This tells the agent how to get more information rather than hallucinating it.

**Programmatic Tool Calling** (Anthropic, November 2025): instead of natural language tool calling where each invocation requires a full inference pass, Claude writes Python code that orchestrates multiple tool calls, processes intermediate results in code, and returns only a final summary to context. This reduced context consumption from **200KB of raw data to 1KB of results** on complex tasks. Intermediate tool results stay in the code execution environment, not in the LLM context.

### Error handling that enables recovery

Design error responses to provide the agent with a clear recovery path:

    "Could not find channel 'genral'. Did you mean #general (ID: C01234)?
    Hint: Use search_channels to find the correct name first."

vs.

    "InvalidParameterException: channel not found"

The first gives the agent enough information to self-correct on the next try. The second requires another round-trip to diagnose.

Recovery hierarchy:
1. Retry with same parameters (transient errors)
2. Retry with modified parameters (input errors -- use the error message to correct)
3. Use a different tool (if alternatives exist)
4. Use cached data (if slightly stale is acceptable)
5. Graceful degradation (proceed with partial information)
6. Escalate to human (high-stakes operations)

### Eval-driven improvement loop

Tool design is iterative, not a one-shot exercise. The workflow that consistently produces reliable tools:

1. **Prototype quickly** — stand up a minimal implementation and test it locally. If using Claude Code, feed it any SDK docs or llms.txt files the tools depend on. Wrap the prototype in a local MCP server to test directly in Claude Code or Desktop.

2. **Build a realistic eval suite** — generate 20-30 tasks grounded in real-world usage, not toy examples. Each task should have a verifiable expected outcome. Realistic multi-step tasks (not trivial single-calls) are what surface real failure modes.

3. **Run evaluations with reasoning traces** — execute the agent loop against the eval suite and capture full transcripts including tool calls, tool responses, and the model's chain of thought. Metrics to capture per run: success rate, tool error rate, redundant call rate, tokens per task, and time-to-completion.

4. **Use the agent to analyse the transcripts** — paste evaluation transcripts into Claude Code and ask it to identify rough edges, propose description improvements, and refactor tools. Claude is effective at spotting inconsistencies across many tool definitions at once and can ensure descriptions stay self-consistent when changes are made.

5. **Measure the delta, not just the outcome** — re-run evals after each change and compare metrics. Small description tweaks can produce large accuracy gains (Anthropic achieved state-of-the-art SWE-bench performance through description refinements alone). Track which changes help and which regress.

6. **Watch for silent degradations in production** — tool descriptions that worked at launch can drift out of alignment as the tools evolve. Regular trace review in Langfuse catches these; the web search "2025 appending" example above was caught this way.

**On naming and namespacing**: naming choices have measurable effects on tool selection accuracy, and the optimal scheme varies by model — test naming conventions against your eval suite rather than assuming a convention will transfer.

### Tool metrics for ongoing optimisation

Monitor these metrics in Langfuse traces and use them to guide tool design improvements:

- **Redundant tool calls**: the agent is calling the same tool multiple times with identical parameters -- consider caching or consolidation
- **Tool errors for invalid parameters**: tool descriptions are unclear or missing examples -- add tool use examples
- **Tool errors for unknown parameters**: schema needs to expose more fields
- **High token consumption per tool call**: response truncation/filtering needs tightening
- **Long time-to-tool-result**: consider async job pattern for tools >10 seconds

Anthropic's own experience: when they launched Claude's web search tool, analysis of tool-calling traces revealed Claude was needlessly appending "2025" to search queries, biasing results. The fix was a single tool description improvement. Regular trace review catches these silent degradations.

### Parallel tool calls and async execution

Models can emit multiple tool calls in a single response. LangGraph's `ToolNode` handles parallel execution automatically. For long-running tools (>10s), use the async job pattern: return a job ID immediately and poll for completion, preventing timeout while preserving streaming.

### Caching tool results

Three caching layers:
- **Prompt caching** (provider-level): 45-90% cost reduction on repeated prompts (see Section 9)
- **Tool result caching** (application-level): deduplicate deterministic calls within a run (`func_name + args -> result`)
- **Semantic caching** (embedding-based): match semantically similar queries to existing results

Research on agentic plan caching shows reusing entire tool-call sequences for similar tasks reduces costs by **46.62%** while maintaining 96.67% of optimal performance.

---

## 8. Skills and the AgentSkills.io Open Standard

### What agentskills.io is

On December 18, 2025, Anthropic released Agent Skills as a **cross-platform open standard** at [agentskills.io](https://agentskills.io), adopted by **26+ platforms** including Claude Code, OpenAI Codex, GitHub Copilot (VS Code, CLI, coding agent), Cursor, Gemini CLI, and Spring AI. A skill you write once works identically across every compliant agent.

**MCP gives agents access to tools and data. Skills teach agents what to do with them.** Tools extend capability; skills extend competence.

### The SKILL.md format

```
skill-name/                    # Must match `name` frontmatter field exactly
+-- SKILL.md                   # Required: YAML frontmatter + Markdown body
+-- scripts/                   # Optional: executable code
+-- references/                # Optional: domain documentation
+-- assets/                    # Optional: templates, schemas
```

Frontmatter specification:

| Field | Required | Constraints |
|-------|----------|-------------|
| `name` | Yes | Max 64 chars, lowercase + hyphens only, no consecutive hyphens, must match directory name |
| `description` | Yes | Max 1024 chars -- describe WHAT and WHEN |
| `license` | No | License name or bundled file reference |
| `compatibility` | No | Max 500 chars, environment requirements |
| `metadata` | No | Arbitrary key-value map (author, version, etc.) |
| `allowed-tools` | No | Space-delimited pre-approved tools (experimental) |

### Progressive disclosure: the core efficiency mechanism

Three-tier loading that protects the context window:

| Tier | What loads | Token budget | When |
|------|-----------|-------------|------|
| **Metadata** | `name` + `description` | ~50-100 tokens per skill | Always, at startup |
| **Instructions** | Full `SKILL.md` body | <5,000 tokens (500 lines max) | When activated |
| **Resources** | `scripts/`, `references/`, `assets/` | On demand | When referenced in the body |

Register dozens of skills with negligible startup cost. **Tell the agent exactly when to load each resource**: `"Read references/api-errors.md if the API returns non-200."` -- not a vague "see references/ for details."

### Writing effective descriptions

The `description` is the **activation mechanism**, not documentation. Use imperative phrasing: "Use this skill when..." Focus on user intent. Err towards explicitness about edge cases. Hard limit: 1024 chars.

    # Bad
    description: Helps with PDFs.

    # Good -- what + when + keywords + indirect cases
    description: >
      Extracts text and tables from PDF files, fills PDF forms, and merges
      multiple PDFs. Use when working with PDF documents or when the user
      mentions PDFs, forms, document extraction, or fillable forms,
      even if they do not use those exact terms.

### Optimising descriptions empirically

Treat description optimisation as an empirical process. Design ~20 trigger eval queries (8-10 should trigger, 8-10 should not). Use a 60/40 train/validation split. The most valuable negative cases are **near-misses** -- queries sharing keywords but needing something different. Iterate 5 times max, selecting the iteration with the best validation pass rate, not the last one.

The `skill-creator` skill at `github.com/anthropics/skills` automates this loop end-to-end.

### Skill body best practices

Add what the agent lacks; omit what it knows. Match specificity to fragility -- explain *why* for flexible instructions; be prescriptive for fragile sequences. Provide defaults, not menus. Favour procedures over declarations. Keep under 500 lines.

**Four high-value body patterns:**
1. **Output templates** -- concrete structure to pattern-match against
2. **Checklists** -- `- [ ]` steps prevent agents from skipping stages
3. **Validation loops** -- run a validator, fix, repeat until passing
4. **Plan-validate-execute** -- produce an intermediate plan file, validate against a source of truth, then execute

**Structure for scale**: when SKILL.md becomes unwieldy, split content into separate files and reference them conditionally. If certain contexts are mutually exclusive or rarely used together, keeping paths separate reduces token usage. Reference files load only when needed, maintaining progressive disclosure.

**Anthropic's key insight**: "Think from Claude's perspective. Monitor how Claude uses your skill in real scenarios and iterate based on observations. Watch for unexpected trajectories or overreliance on certain contexts." Iterate with Claude -- ask it to capture successful approaches and common mistakes into reusable context within the skill.

### Scripts in skills

Bundle scripts when the agent independently reinvents the same logic. Code serves as both executable tools and documentation -- be clear whether Claude should run scripts directly or read them into context as reference.

Self-contained dependency management: PEP 723 for Python (`uv run`), `npx`/`bunx` for JS, `deno run` for TypeScript. Always pin versions.

Script design rules: no interactive prompts (agents operate in non-interactive shells), `--help` documentation, structured output (JSON/CSV), idempotency, predictable output size, dry-run support, meaningful exit codes.

### Evaluating skills

Run each test case with_skill and without_skill. Aggregate `pass_rate`, `time_seconds`, `tokens` (mean + stddev). The `delta` tells you what the skill costs vs. what it buys. Iterate: feed failed assertions + human feedback + execution transcripts to an LLM, ask for generalised improvements (not narrow patches), rerun.

### Dual-use: same skill in LangGraph and standalone

```python
def load_skill(skill_name: str) -> str:
    path = SKILLS_DIR / skill_name / "SKILL.md"
    return path.read_text().split("---", 2)[-1].strip()

# LangGraph node
def research_node(state: AgentState) -> dict:
    result = llm.invoke([SystemMessage(content=load_skill("deep-research")),
                         HumanMessage(content=state["query"])])
    return {"research_result": result.content}

# Standalone
def run_research(query: str) -> str:
    return llm.invoke([SystemMessage(content=load_skill("deep-research")),
                       HumanMessage(content=query)]).content
```

Design constraint: **do not embed graph state assumptions in SKILL.md**. Keep skills declarative; let the execution wrapper handle state management.

---

## 9. Token Efficiency and Latency Optimisation

### Context rot and the case for proactive management

Chroma's 2025 research paper (Context-Rot) establishes that **all models experience performance degradation with increasing input token count**. This is not just a cost problem -- quality degrades as context grows. Proactive context management is therefore both a cost and a correctness concern.

### Tiered memory architecture

| Tier | Strategy | Token cost | Fidelity |
|------|----------|-----------|----------|
| Immediate (last 3-5 turns) | Full verbatim history | High | Perfect |
| Recent (last 10-20 turns) | Sliding window buffer | Medium | High |
| Session (older turns) | LLM-generated summaries | Low | Medium |
| Long-term (cross-session) | Vector store + semantic retrieval | Very low | Variable |

JetBrains (2025): **observation masking** (keeping latest 10 turns, masking older tool observations) cuts costs by **52% while improving solve rates by 2.6%** on SWE-bench. Trigger LLM-based summarisation only at 70-80% capacity.

Anthropic's **compaction** pattern: when approaching the context limit, summarise the conversation and reinitiate with the summary. **Structured note-taking**: the agent writes notes persisted outside the context window, pulled back when needed.

### Prompt caching: the highest-leverage optimisation

Prompt caching reuses previously computed key-value (KV) tensors from attention layers, avoiding redundant computation on repeated prompt prefixes.

**Anthropic prompt caching specifics:**
- Cache writes cost **25% more** than base input token price (write price: $3.75/M -> cache write: $4.69/M for Sonnet)
- Cache reads cost **10% of base** input token price (90% savings on reads)
- TTL options: **5-minute** (default, 1.25x write cost) or **1-hour** (2x write cost)
- Minimum **1,024 tokens** per cache checkpoint
- Cache entries refresh on each hit within the TTL window
- **100% hit rate** when Anthropic receives a matching prefix (vs ~50% hit rate on OpenAI)

**OpenAI prompt caching specifics:**
- **Fully automatic** for prompts >=1,024 tokens
- **50% cost reduction** on cached tokens; up to **80% latency reduction**
- No explicit marking required -- just ensure the prompt prefix is stable

**Processing order (Anthropic)**: Anthropic processes request components in a specific order. Structure your prompts to match:

```
Tools -> System Message -> Message History
```

Static content (tool definitions, system instructions) goes first; dynamic content (user messages, tool results) appends at the end. This ensures the static prefix is maximally cached while the dynamic suffix changes across requests.

**TTL selection guidance**: use 5-minute TTL for interactive sessions where users respond quickly. Use 1-hour TTL when tasks take longer than 5 minutes (agentic side-agents, long document analysis). The 1-hour TTL costs 2x more to write but pays back when the same session continues beyond 5 minutes.

**What NOT to cache**: user-specific data in system prompts breaks caching across users -- push personalisation into the message content, not the system prompt. Changing prompts frequently invalidates caches -- version prompts and measure cache hit rates before optimising.

**Practical example**: a 100K-token book analysis prompt drops from **11.5 seconds to 2.4 seconds** response time with caching enabled (Anthropic announcement data).

**The "Don't Break the Cache" paper (arXiv:2601.06007)**: evaluated prompt caching strategies for long-horizon agentic tasks across OpenAI (GPT-5.2), Anthropic (Claude Sonnet 4.5), and Google (Gemini 2.5 Pro). Key finding: the "best cache mode" varies per model. For Anthropic, explicit cache control with stable prefix maximisation achieves the highest cost reduction. The research confirms that agentic workloads with dynamic tool results benefit from structured prompt layout more than static QA workloads.

### Batch API for non-real-time workloads

The **Batch API** offers a **50% discount** on both input and output tokens for asynchronous processing (24-hour turnaround). Use for: running comprehensive test suites against your prompts and agent workflows, offline data processing pipelines, content generation at scale, and model evaluation runs. All Claude models support batch processing at consistent 50% discounts.

### Output length control

Each output token costs roughly **4x more than input tokens**. For intermediate agent reasoning:
- Use explicit length instructions: "Be concise. Respond in 2-3 sentences."
- Set `max_tokens` explicitly for intermediate steps
- Use structured output schemas that naturally constrain verbosity
- Apply differential verbosity: verbose for final user-facing output, ultra-concise for intermediate tool-use planning

Research (arXiv:2407.19825, Concise Chain of Thought): adding "limit the answer length to N words" to CoT prompts maintains accuracy while significantly reducing output tokens for intermediate reasoning steps.

### Reducing time-to-first-token

TTFT is the most important metric for perceived responsiveness in interactive CLI tools:
- Reduce prompt length (every token increases prefill time)
- Leverage prompt caching for repeated prefixes
- Stream responses by default
- Route simple queries to faster models (Haiku vs Sonnet has ~2-3x TTFT difference)
- Use Anthropic's response prefilling to start output with expected tokens
- For CLI tools: show a spinner immediately, stream partial results as they arrive, right-size the model for each task

### Microsoft LLMLingua: prompt compression

For very long prompts, Microsoft's **LLMLingua** uses a small language model to identify and remove unimportant tokens, achieving up to **20x compression** with minimal performance loss. Research shows extractive compression can actually improve accuracy by removing noise -- **+7.89 F1 improvement** on 2WikiMultihopQA at 4.5x compression. Use as a pre-processing step on retrieved documents before they enter the context window.

---

## 10. LiteLLM as the Model Abstraction Layer

LiteLLM provides a unified gateway to 100+ LLM providers with an OpenAI-compatible API. Use the **Proxy Server** deployment for centralised routing, cost tracking, load balancing, and multi-instance coordination.

### All four routing strategies: when to use each

LiteLLM supports four routing strategies. The selection matters significantly for production performance:

**`simple-shuffle` (default, RECOMMENDED for production)**: picks a deployment based on provided RPM/TPM weights; randomly selects if no weights are set. Best performance with minimal latency overhead. No external state required. This is the right choice for most production deployments.

**`least-busy`**: queue-based routing to the deployment with fewest in-flight requests. Good for reducing tail latency, but adds bookkeeping overhead.

**`usage-based-routing`**: routes to the deployment with the lowest usage relative to its limits. LiteLLM's own documentation **explicitly warns against using this in production** due to performance impacts from Redis operations on every request.

**`latency-based-routing`**: samples latency and routes to fastest deployment. Adds overhead from latency sampling. Useful only when deployments have significantly different latency characteristics and you can absorb the measurement cost.

### Complete router configuration

```yaml
model_list:
  # Orchestrator: Claude via Anthropic direct (primary)
  - model_name: orchestrator
    litellm_params:
      model: anthropic/claude-sonnet-4-5-latest
      api_key: os.environ/ANTHROPIC_API_KEY
      order: 1   # highest priority -- tried first

  # Orchestrator: Claude via Vertex AI (fallback for resilience)
  - model_name: orchestrator
    litellm_params:
      model: vertex_ai/claude-sonnet-4-20250514
      vertex_project: os.environ/GCP_PROJECT
      order: 2   # used when order=1 is unavailable

  # Worker: GPT-4o-mini (cost-efficient execution)
  - model_name: worker
    litellm_params:
      model: openai/gpt-4o-mini
      api_key: os.environ/OPENAI_API_KEY
      rpm: 500
      tpm: 200000

  # Validator: Haiku (fast, cheap quality checks)
  - model_name: validator
    litellm_params:
      model: anthropic/claude-haiku-4-5
      api_key: os.environ/ANTHROPIC_API_KEY

router_settings:
  routing_strategy: simple-shuffle          # recommended for production
  enable_pre_call_checks: true              # required for `order` parameter to work
  model_group_alias: {"gpt-4": "worker"}   # transparent alias routing
  fallbacks:
    - orchestrator: [worker]               # cross-provider fallback
  context_window_fallbacks:
    - orchestrator: [orchestrator-128k]    # escalate to larger context on overflow
  num_retries: 2
  timeout: 30
  allowed_fails: 3                         # cooldown a deployment after 3 failures
  cooldown_time: 30                        # seconds before retrying a cooled-down deployment

litellm_settings:
  cache: true
  cache_params:
    type: redis
    host: os.environ/REDIS_HOST
    port: os.environ/REDIS_PORT
    password: os.environ/REDIS_PASSWORD
```

### Hard rate limit enforcement

By default, RPM/TPM values are only used for routing decisions. To enforce them as hard limits (returning HTTP 429 when exceeded):

```yaml
router_settings:
  optional_pre_call_checks:
    - enforce_model_rate_limits   # turns RPM/TPM into hard limits
```

For multi-instance deployments, add Redis so all proxy instances share rate limit state.

### Integrating with LangGraph

```python
from langchain_openai import ChatOpenAI

PROXY_URL = "http://0.0.0.0:4000"
LITELLM_KEY = os.environ["LITELLM_API_KEY"]

def build_model(role: Literal["orchestrator", "worker", "validator"]) -> ChatOpenAI:
    return ChatOpenAI(
        openai_api_base=PROXY_URL,
        model=role,          # LiteLLM routes based on this model name
        api_key=LITELLM_KEY,
        streaming=True       # enable for CLI streaming
    )

# In graph nodes -- inject model factory, never hardcode
def plan_node(state: AgentState, llm: ChatOpenAI = None) -> dict:
    llm = llm or build_model("orchestrator")
    result = llm.with_structured_output(PlanSchema).invoke(state["messages"])
    return {"plan": result.steps}
```

### Cost tracking and budget enforcement

LiteLLM provides a **multi-tier hierarchical budget system**: Organisation -> Team -> User -> Key -> End User. Configure provider-level budgets to automatically route away from providers exceeding limits:

```yaml
router_settings:
  provider_budget_config:
    anthropic:
      budget_limit: 200.0
      time_period: 1d
    openai:
      budget_limit: 100.0
      time_period: 1d
```

Use **tag-based cost tracking** to attribute costs by feature, project, or team:

```python
response = litellm.completion(
    model="orchestrator",
    messages=[...],
    metadata={"tags": ["project:research", "feature:planning"]}
)
```

### Production deployment checklist

**Infrastructure:**
- Minimum **4 vCPU, 8 GB RAM**
- Match Uvicorn/Gunicorn workers to CPU count: `--num_workers $(nproc)`
- Use `--max_requests_before_restart 10000` with Gunicorn for stable worker recycling

**Redis configuration:**
- Use `redis_host`/`redis_port`/`redis_password` -- **NOT `redis_url`** (the `redis_url` parameter is 80 RPS slower due to connection overhead)
- Redis is required for multi-instance deployments to share rate limit state and cooldown tracking

**Performance settings:**
- `LITELLM_LOG="ERROR"` -- suppresses verbose request/response logging in production
- `set_verbose: False` in config -- disables debug output
- `proxy_batch_write_at: 60` -- batches spend updates to database every 60 seconds instead of per-request

**Security:**
- `LITELLM_SALT_KEY` -- encrypts API keys stored in the database
- Separate API keys for development, staging, and production environments
- Automated key rotation policy

**Kubernetes (if applicable):**
- Set `SEPARATE_HEALTH_APP=1` for a separate health check process that remains responsive even when the main proxy is under heavy load
- Set `LITELLM_MIGRATION_DIR` to a writable path
- `SUPERVISORD_STOPWAITSECS=3600` for graceful shutdown of in-flight requests

---

## 11. Observability with Langfuse

Langfuse is the recommended observability platform for agentic systems. It provides the full observability flywheel: trace production behaviour -> analyse errors -> build datasets -> run experiments -> deploy improvements -> trace again.

### Data model

Langfuse organises data into four levels:

**Observations**: individual steps within a trace. Types include `generation` (LLM calls with model, tokens, cost, latency), `span` (arbitrary computation steps), `tool_call` (tool invocations with arguments and return values), and `retrieval` (RAG operations). Observations can be nested to represent the hierarchy of an agent run.

**Traces**: a single end-to-end request or operation -- one complete agent invocation from user input to final output. Carries attributes (`user_id`, `session_id`, `tags`, `metadata`, `version`) that propagate to all nested observations. This is your primary unit for cost and latency analysis.

**Sessions**: groups of traces forming a multi-turn conversation. Enables analysis of conversation-level metrics (session cost, turns to resolution, abandonment).

**Scores**: evaluation results attached to traces or observations -- from LLM-as-a-judge, human annotation, user feedback (thumbs up/down), or custom programmatic evaluators.

### LangGraph integration

```python
from langfuse.langchain import CallbackHandler
from langfuse import Langfuse

# Basic integration: auto-traces all LangGraph nodes, LLM calls, tool calls
langfuse_handler = CallbackHandler()
result = compiled_graph.invoke(
    input={"messages": [HumanMessage(content="...")]},
    config={
        "callbacks": [langfuse_handler],
        "metadata": {
            "langfuse_session_id": session_id,
            "langfuse_user_id": user_id,
            "langfuse_version": skill_version  # link traces to prompt/skill versions
        }
    }
)
```

This automatically captures every LangGraph node execution as a span, LLM calls as generation observations (with model, tokens, cost, latency), tool calls with arguments and return values, and conditional routing decisions.

**Manual custom spans** for non-LangChain operations:

```python
from langfuse import get_client
langfuse = get_client()

with langfuse.start_as_current_observation(as_type="span", name="database_query") as span:
    result = db.query(sql)
    span.update(metadata={"rows_returned": len(result)})
```

**TTFT tracking**:

```python
with langfuse.start_as_current_observation(as_type="generation") as generation:
    first_token_time = None
    for chunk in llm.stream(messages):
        if first_token_time is None:
            generation.update(completion_start_time=datetime.now())
            first_token_time = datetime.now()
        yield chunk
```

**Sampling for high-volume workloads**: avoid instrumenting every trace at full volume in production:

```python
langfuse = Langfuse(sample_rate=0.2)  # instrument 20% of traces
```

### Diagnosing performance bottlenecks

**The trace timeline view** provides a Gantt-chart with colour-coded latency indicators:
- **Red**: a span consuming >=75% of total trace latency -- your primary bottleneck
- **Yellow**: a span consuming 50-75% of total trace latency

**The Agent Graphs view** (GA as of November 2025): automatically infers and visualises agentic workflow structure from observation timings, showing execution across agent frameworks and custom implementations.

Common bottleneck patterns and their diagnoses:
- **LLM generation calls dominating latency**: compare models using the generations table, filter by model
- **Slow external API calls**: add custom spans around external calls, measure against SLOs
- **Sequential operations that could be parallelised**: look for long chains of same-depth spans
- **Excessive reflection loops**: high node visit counts in Agent Graphs view indicate infinite or near-infinite loops
- **Context rot**: traces getting progressively slower in a session as context grows

Langfuse SDK overhead: approximately **0.1ms per decorated function** using background batching every ~2 seconds. The SDK is async-first and adds negligible latency.

### Three evaluation contexts

LLM-as-a-Judge evaluators can run on three scopes of data:

**Observation-level** (individual operations): evaluate specific LLM calls, retrieval operations, or tool calls in isolation. Use for: checking toxicity on every LLM output, scoring relevance of retrieved documents, validating tool call parameters. **"Dramatically faster execution: evaluations complete in seconds."** Best for compositional evaluation -- run toxicity on LLM outputs, relevance on retrievals, accuracy on generations simultaneously.

**Trace-level** (complete workflows): evaluate entire workflow executions from start to finish. Use for: scoring whether the agent completed the task correctly, evaluating the overall quality of a multi-step response, checking if the agent followed the right tool sequence.

**Experiment-level** (controlled test datasets): run evaluators on dataset items to compare model versions, prompt variations, or tool configurations in a reproducible environment. **Each experiment run generates traces that are automatically scored.**

**Production pattern**: use experiments during development to validate changes; deploy observation-level evaluators in production for scalable, real-time monitoring.

### Datasets and the evaluation flywheel

```python
from langfuse import Langfuse
langfuse = Langfuse()

# Create dataset from production failures -- the highest-value dataset source
langfuse.create_dataset(name="agent-regression-2025")

langfuse.create_dataset_item(
    dataset_name="agent-regression-2025",
    input={"query": "Schedule a meeting with Alice and Bob"},
    expected_output={"action": "create_calendar_event", "participants": ["alice", "bob"]},
    source_trace_id="<trace_id>",          # link to the production trace that failed
    source_observation_id="<obs_id>"       # optionally link to specific span
)
```

The recommended workflow:
1. Monitor production traces in Langfuse
2. Flag traces where scores indicate poor performance
3. Add those traces to a dataset as test cases (with expected outputs provided by domain experts)
4. Run experiments on the dataset when making changes
5. Deploy changes only when experiment scores exceed production baseline
6. Monitor that the improvement holds in production

**Synthetic dataset generation**: use LLMs to generate diverse test inputs including adversarial cases, amplifying test coverage without waiting for production failures. Particularly useful for bootstrapping evals before production traffic exists.

### Prompt and skill version management in Langfuse

Langfuse provides a **Prompt Management** system:
- Create and version prompts via UI, SDK, or API
- Deploy via labels: `production`, `staging`, `canary`
- No code changes required to update a deployed prompt
- Compare latency, cost, and evaluation metrics across prompt versions
- Test prompts directly in the Langfuse Playground
- Link traces to specific prompt versions for regression tracking

When a skill SKILL.md changes, pass the version in trace metadata so you can filter traces by skill version and measure the A/B impact:

```python
config={
    "metadata": {
        "langfuse_version": "research-skill-v1.2",
        "langfuse_tags": ["skill:research", "env:production"]
    }
}
```

### Cost tracking and spend alerts

Langfuse automatically aggregates costs from all nested generation observations, with colour-coded display (red/yellow). Use `session_id` and `user_id` propagation for per-session and per-user cost attribution.

**Spend Alerts**: configure alerts for when cost per trace, cost per session, or total daily cost exceeds thresholds. This is your defence against runaway agent loops -- a single loop incident can generate hundreds of dollars of API calls in minutes. Set alerts conservatively: if a normal agent task costs $0.50, alert at $5.00 (10x).

**Model pricing tiers**: Langfuse supports context-dependent pricing tiers for models like Claude Sonnet 4.5 and Gemini 2.5 Pro that charge different rates based on input token count. Configure via the Langfuse UI for accurate cost calculations on models with tiered pricing.

---

## 12. Complete Project Architecture

### The full system architecture

    +-------------------------------------------------------------+
    |                    CLI Interface (REPL)                     |
    |         Spinner + streaming display + interrupt handling    |
    +-------------------------------------------------------------+
    |              LangGraph State Machine                        |
    |   +------------------+  +----------------------------+     |
    |   | Orchestrator     |  | Reflection Loop            |     |
    |   | (Plan + Route)   |  | (Grade -> Reflect -> Retry)|     |
    |   +------------------+  +----------------------------+     |
    |   +------------------+  +----------------------------+     |
    |   | Worker Subgraphs |  | Guardrail Layer            |     |
    |   | (Execute tasks)  |  | (Pre-tool + Anomaly + HITL)|     |
    |   +------------------+  +----------------------------+     |
    +-------------------------------------------------------------+
    |              Inter-Agent Communication                      |
    |  Shared state (intra-graph) | A2A protocol (cross-process)  |
    +-------------------------------------------------------------+
    |              LiteLLM Abstraction Layer                      |
    |  simple-shuffle routing | Fallbacks | Budget enforcement    |
    +-------------------------------------------------------------+
    |              Skills & Tools Registry                        |
    |  SKILL.md standard | Tool impls | Strict schemas | Examples |
    +-------------------------------------------------------------+
    |              Memory and Persistence Layer                   |
    |  PostgresSaver (threads) | PostgresStore (cross-session)    |
    |  Vector store (semantic) | Episodic store (task records)    |
    +-------------------------------------------------------------+
    |              Observability                                  |
    |  Langfuse (traces, costs, evals, spend alerts, experiments) |
    +-------------------------------------------------------------+

### Multi-agent pattern decision framework

| Pattern | Use when | Token overhead | Control |
|---------|----------|---------------|---------|
| Single agent + tools | Task fits in one context; <5 steps | 1x | Highest |
| Orchestrator-worker | Dynamic decomposition; parallel subtasks | 3-5x | High |
| Supervisor | Fixed specialist domains; quality control needed | 3-5x | Highest |
| Swarm (handoffs) | Exploratory; agents decide scope autonomously | 3-5x | Lowest |
| Hierarchical teams | Multiple distinct domains with internal coordination | 10-15x | Medium |

Multi-agent systems use roughly **15x more tokens than single-agent**. The capability gain must justify this cost. Do not use multi-agent for tasks a well-prompted single agent can handle.

### Reasoning pattern selection

**ReAct**: alternate thought-action-observation. LLM call per step. Adaptive but sequential and expensive. Best for simple tasks (<5 steps) with unpredictable branching.

**Plan-and-execute**: generate a full plan with a frontier model; execute steps with a cheaper model; replan if execution diverges. Parallelisable. Better cost profile for complex multi-step tasks.

**Reflection (generate-critique-revise)**: best for quality-sensitive output. 2-5 iteration max. Use stronger model for critique, cheaper for generation.

**Hybrid (recommended for production)**: plan-and-execute as outer loop; ReAct agents as step executors; reflection within each step for quality-sensitive output; replanning node triggered by execution divergence. Bypass planning for simple single-step queries.

### Project structure

    my-agent-cli/
    +-- src/
    |   +-- cli/
    |   |   +-- repl.py              # REPL loop, streaming display, interrupt handling
    |   |   +-- formatter.py         # Output formatting
    |   +-- graphs/
    |   |   +-- main_graph.py        # Top-level graph definition
    |   |   +-- nodes/
    |   |   |   +-- plan.py          # Planning node (frontier model)
    |   |   |   +-- execute.py       # Execution node (mid-tier model)
    |   |   |   +-- validate.py      # Validation node -- first-class citizen
    |   |   |   +-- reflect.py       # Reflection node (strong model)
    |   |   +-- subgraphs/
    |   |   |   +-- research.py      # Research subgraph
    |   |   |   +-- analysis.py      # Analysis subgraph
    |   |   +-- routing.py           # All routing functions (pure, testable, no LLM calls)
    |   +-- state/
    |   |   +-- schema.py            # AgentState TypedDict, reducers, InputState, OutputState
    |   |   +-- checkpointing.py     # Checkpointer factory (SQLite dev, Postgres prod)
    |   |   +-- memory.py            # Store factory, memory load/save nodes
    |   +-- tools/
    |   |   +-- registry.py          # Tool registry + dynamic discovery
    |   |   +-- guardrails.py        # Pre-tool checks, risk classification, anomaly detection
    |   |   +-- <tool>.py            # Individual tool implementations
    |   +-- skills/
    |   |   +-- loader.py            # Framework-agnostic SKILL.md loader
    |   |   +-- research/
    |   |   |   +-- SKILL.md
    |   |   +-- analysis/
    |   |       +-- SKILL.md
    |   |       +-- scripts/
    |   +-- agents/
    |   |   +-- cards.py             # A2A Agent Card definitions
    |   |   +-- a2a_client.py        # A2A protocol client utilities
    |   +-- models/
    |   |   +-- config.py            # LiteLLM proxy URL, model name constants
    |   |   +-- factory.py           # LLM factory (returns model by role)
    |   +-- observability/
    |   |   +-- langfuse.py          # Handler setup, spend alerts, eval datasets
    |   +-- config/
    |       +-- settings.py          # Environment-aware config (dev/staging/prod)
    +-- tests/
    |   +-- unit/                    # Node functions, routing (pure), tools, guardrails
    |   +-- integration/             # Full graph runs with InMemorySaver + mock LLMs
    |   +-- evals/
    |       +-- skill_evals/         # Per-skill with_skill/without_skill evals
    |       +-- trajectory_evals/    # Full trajectory test cases
    |       +-- datasets/            # Golden datasets for regression testing
    +-- skills/                      # User-facing skills (outside src/ for easy editing)
        +-- <skill-name>/
            +-- SKILL.md

### Configuration and dependency injection

Avoid hardcoded model names, URLs, or thresholds in nodes. Inject via a model factory:

```python
class ModelFactory:
    def __init__(self, config: AgentConfig):
        self._proxy = f"http://{config.litellm_host}:{config.litellm_port}"
        self._config = config

    def for_role(self, role: Literal["orchestrator", "worker", "validator", "reflector"]) -> ChatOpenAI:
        return ChatOpenAI(
            openai_api_base=self._proxy,
            model=self._config.model_names[role],
            api_key=self._config.litellm_key,
            streaming=True
        )
```

This makes nodes independently testable (inject a mock factory) and makes model changes a config change, not a code change.

### Testing strategy

**Unit tests** (every commit, <1 second each): test node functions, routing functions, tool logic, and guardrail checks. Routing functions are pure functions on state -- test them without any LLM at all:

```python
def test_route_after_validation_escalates_at_max_errors():
    state = {"error_count": 3, "confidence_score": 0.5}
    assert route_after_validation(state) == "escalate"

def test_route_after_validation_retries_when_low_confidence():
    state = {"error_count": 1, "confidence_score": 0.5}
    assert route_after_validation(state) == "retry"
```

For LLM nodes, use `GenericFakeChatModel`:

```python
from langchain_core.language_models.fake_chat_models import GenericFakeChatModel

def test_plan_node_returns_steps():
    mock_llm = GenericFakeChatModel(messages=iter([
        AIMessage(content='{"steps": ["search", "analyse", "report"]}')
    ]))
    state = {"messages": [HumanMessage(content="Research AI trends")]}
    result = plan_node(state, model_factory=MockModelFactory(mock_llm))
    assert "plan" in result
    assert len(result["plan"]) == 3
```

**Integration tests** (per PR, ~10 seconds): full graph executions with `InMemorySaver` and mock LLMs. Verify state persistence, correct routing, and that reflection loops terminate within `MAX_REFLECTIONS`.

**Skill evaluations** (nightly): with_skill vs. without_skill runs using the agentskills.io methodology. Assertion grading, benchmark aggregation, delta tracking.

**Trajectory evaluations** (nightly): full multi-step runs with LLM-as-a-Judge scoring via Langfuse datasets. Measure task completion rate, tool call efficiency, and output quality.

**Agentic testing principles:**
- Handle non-determinism: run each test case 5-10 times, assert on statistical properties (pass rate >80%, not always-pass)
- **Eval-driven development**: define evaluations before building capabilities -- it is the agent equivalent of TDD
- Link all eval traces to specific skill/prompt versions for regression tracking
- The CLASSic framework (Cost, Latency, Accuracy, Stability, Security) is the right evaluation rubric for model changes

---

## Conclusion: Key Principles

**Flow engineering supersedes prompt engineering.** The question is not "how do I phrase this prompt?" but "what is the state machine governing this agent's behaviour? Where are the decision points, fallback paths, and termination conditions?" State schema design, node boundaries, routing logic, and loop guards are the primary quality levers.

**Self-validation is not optional for quality-sensitive tasks.** The generate-critique-revise loop with a dedicated validation node, model-differentiated reflection (cheap generator, strong reflector), and explicit loop guards transforms an agent from one-shot to iterative refinement. Use a cheaper model for initial drafts and a stronger model for critique -- this is the highest-leverage model-routing pattern in practice.

**Prompt caching is the single highest-leverage cost optimisation.** Anthropic's 90% reduction on cache reads (10% of base price) and up to 85% latency reduction for long prompts means that structuring prompts for caching should be the first optimisation applied to any production agent. The processing order (tools -> system -> messages) and stable-prefix discipline pay consistent dividends.

**Context engineering supersedes prompt engineering.** Observation masking (52% cost reduction, 2.6% solve rate improvement), proactive compaction at 70-80% capacity, and tiered memory architecture all produce larger gains than single model upgrades. Context rot is a real phenomenon -- performance degrades with context length, making proactive management a correctness requirement, not just cost control.

**The AgentSkills.io standard resolves the reuse question.** Skills to the SKILL.md spec are portable across 26+ platforms, dual-use in LangGraph and standalone contexts via a thin wrapper, systematically evaluatable, and iteratively improvable using empirical description optimisation. The investment in correct scope, effective description, tested scripts, and systematic eval pays dividends everywhere.

**Tool design is where agent reliability lives.** Strict schema enforcement, input examples (72% to 90% accuracy improvement), the Tool Search Tool for on-demand discovery, programmatic tool calling for context efficiency, and the response_format pattern for verbosity control are the ACI investments that compound across thousands of tool calls.

**Guardrails are architectural, not cosmetic.** Pre-tool checks, anomaly detection, output validation, and HITL escalation must be planned from the start. The defence-in-depth stack gives you controlled, auditable, predictable risk.

**Heterogeneous model routing is table stakes.** Three-tier routing with cross-provider fallback chains is the production standard. The CLASSic framework (Cost, Latency, Accuracy, Stability, Security) is the right evaluation methodology for model selection decisions -- not single-dimension benchmark scores.

**Observability is not optional.** Without tracing every node, tool call, and LLM generation with latency and cost attribution, compounding inefficiencies are invisible until a $0.05 call becomes a $5.00 runaway loop. Langfuse's observability flywheel -- trace -> error analysis -> datasets -> experiments -> deploy -> trace -- is the continuous improvement mechanism that makes agents better over time.

---

*Sources: agentskills.io (specification, best practices, evaluating skills, using scripts, client implementation), anthropic.com/engineering (Building Effective Agents, Writing Effective Tools, Advanced Tool Use, Effective Context Engineering, Equipping Agents for the Real World, Multi-Agent Research System), Anthropic platform docs (tool use, structured outputs, prompt caching, Agent Skills), Google A2A protocol specification, LangChain/LangGraph official documentation (workflows-agents, streaming, interrupts, multi-agent, reflection agents, self-correcting RAG), OpenAI Practical Guide to Building Agents, LiteLLM production docs (routing, load balancing, fallbacks, best practices), Langfuse documentation (data model, LLM-as-a-judge, datasets, experiments, SDK advanced features), Forrester AEGIS framework, OWASP Top 10 for LLM Applications v2025, CLASSic framework (Aisera, ICLR 2025), KDD 2025 Tutorial on LLM Agent Evaluation, JetBrains Research (efficient context management, 2025), Chroma Context-Rot research (2025), arXiv: Don't Break the Cache (2601.06007), Architectures for Building Agentic AI (2512.09458), MCP x A2A Framework (2506.01804), Concise Chain of Thought (2407.19825), LLMLingua (Microsoft Research), Evaluation and Benchmarking of LLM Agents KDD Survey (2507.21504).*

---

## 13. Workflows vs. Agents: The Most Important Architectural Decision

Before choosing between LangGraph, reflection patterns, multi-agent systems, or anything else in this guide, you must make a more fundamental choice. Anthropic's definition:

**Workflows**: systems where LLMs and tools are orchestrated through predefined code paths. The control flow is deterministic; the LLM fills in content within a fixed structure.

**Agents**: systems where the LLM dynamically directs its own processes and tool usage, maintaining control over how it accomplishes tasks. The path is not known at compile time.

This is not a spectrum — it is a genuine architectural fork with different tradeoffs.

Use a **workflow** when: the task has predictable, well-defined steps; you need consistency and auditability across many executions; failure modes are well understood; or the task can be broken into fixed stages (classify → retrieve → generate → validate). Most production AI today is workflows dressed up as agents.

Use an **agent** when: the number of steps cannot be predicted in advance; the task requires adapting to environmental feedback mid-execution; you need the model to make genuine decisions about what to try next; or the problem space is open-ended enough that hardcoding a path would miss most of it.

Anthropic's guidance is direct: "We recommend finding the simplest solution possible and only increasing complexity when needed. This might mean not building agentic systems at all." A single well-prompted LLM call with retrieval is often enough for the majority of real-world tasks.

The practical test: if a junior developer can write a flowchart for the task in advance, you need a workflow. If they can't because the right path depends on what the environment returns at each step, you need an agent.

**The key tradeoff**: agents trade latency and cost for flexibility. Every step requires an LLM call. Errors can compound — a wrong tool selection in step 2 corrupts the context for steps 3 through 10. Agents require sandboxed testing and guardrails that workflows do not.

Anthropic's five workflow building blocks, in order of complexity:

1. **Prompt chaining** — break a task into sequential LLM calls, with each step's output feeding the next. Use when each step is too long or complex for one call, or when you want verification gates between steps.
2. **Routing** — classify the input and route it to the appropriate specialised workflow. Use when tasks are clearly distinct (customer support routing, intent classification).
3. **Parallelisation** — run independent tasks simultaneously, then aggregate. Two variants: sectioning (different LLMs handle independent subtasks) and voting (same task run multiple times to reduce variance on high-stakes decisions).
4. **Orchestrator-workers** — a central LLM dynamically decomposes the task and delegates. Unlike fixed parallelisation, the orchestrator decides at runtime how to split. Use for tasks where the decomposition is not knowable in advance.
5. **Evaluator-optimizer** — one LLM generates, another evaluates and provides feedback in a loop. Use when quality can be judged iteratively and you have clear criteria for "good enough."

All five can be expressed in LangGraph, but several can also be implemented in a few lines of Python without any framework. Start with the simplest structure that handles your known failure modes. Add framework primitives only when you encounter a problem that requires them.

---

## 14. Context Engineering as a Discipline

Context engineering is Anthropic's term for the discipline that has superseded prompt engineering. Andrej Karpathy's definition: "the delicate art and science of filling the context window with just the right information for the next step."

The distinction from prompt engineering is architectural, not cosmetic. Prompt engineering asks: how do I write effective instructions? Context engineering asks: what is the optimal configuration of all tokens — system prompt, tools, examples, message history, retrieved data, tool results — at each inference step, given finite attention budget and degradation under load?

The core constraint is attention scarcity. The transformer architecture creates n² pairwise relationships for n tokens. As context length increases, the model's ability to maintain those relationships degrades. This is not a soft preference — it is an architectural reality that shows up as context rot: measurable degradation in recall and reasoning accuracy as the context window fills. Every token added depletes an attention budget with diminishing returns.

### The anatomy of effective context

**System prompts** operate in a Goldilocks zone. At one extreme: hardcoded if-else logic in the prompt, brittle and unmaintainable. At the other extreme: vague guidance that falsely assumes shared context. The right altitude is specific enough to guide behaviour, flexible enough to provide heuristics the model can apply to novel situations. Use XML or Markdown structure to delineate sections (`<background_information>`, `<instructions>`, `<output_format>`). Start with the minimal prompt that works on your best model, then add instructions and examples to fix specific failure modes. Do not pre-emptively add rules for edge cases you have not yet observed.

**Tools** define the agent's action space and consume context with every definition and result. The most common failure mode is a bloated tool set with overlapping functionality. If a human engineer cannot definitively say which tool to call in a given situation, the agent cannot either. Curate a minimal viable tool set. Tool results should return high-signal information only — see Section 7.

**Examples** (few-shot prompting) remain valuable. The error is stuffing every edge case into a prompt. Curate a diverse set of canonical examples that portray the expected behaviour; a well-chosen example is worth more than 20 rules.

**Message history** is the most dynamic and most dangerous component. It grows unboundedly if unmanaged, and old tool outputs consume context for information the model no longer needs. The standard approach: keep the last 10 turns verbatim; mask or summarise older tool observations (see Section 6 on memory architecture).

### The four context strategies

Anthropic's framework for context management in agents:

1. **Write** — save information outside the context window for later retrieval. Structured notes, progress files, external memory stores. The agent externalises what it cannot afford to keep in context. This is the key pattern in long-horizon agent harnesses (see Section 15).

2. **Select** — pull relevant information into the context window on demand. Agentic search (grep, glob, read) or semantic search (RAG). The distinction: agentic search is slower but more accurate, more transparent, and easier to maintain. Start with agentic search; add semantic search only when you need speed at scale.

3. **Compress** — summarise or filter information before it enters the context window. Tool output truncation, document summarisation, compaction of message history. Compression reduces tokens but risks losing subtle context whose importance only becomes apparent later. Apply conservatively.

4. **Isolate** — use subagents with their own context windows to process information that does not need to flow back to the orchestrator in full. Subagents return summaries, not full transcripts. This is the architectural basis for parallelisation and the primary way to break the O(n²) context cost for large information sets.

### Just-in-time context over pre-loaded context

The emerging production pattern is replacing pre-inference RAG (load everything relevant upfront) with just-in-time retrieval (load only what the agent decides it needs, when it needs it). Instead of chunking and embedding an entire knowledge base and hoping retrieval captures the right sections, the agent maintains lightweight references (file paths, stored queries, links) and loads them on demand using tools.

Claude Code demonstrates this: CLAUDE.md files load upfront, but files, search results, and documentation load just-in-time via grep, glob, and read. The folder structure, naming conventions, and timestamps become metadata the agent uses to decide what is worth loading. This mirrors human cognition — we do not memorise entire corpuses, we maintain indexing systems and retrieve on demand.

The tradeoff: just-in-time is slower than pre-loaded retrieval. The right balance depends on task dynamics. For slow-moving knowledge (legal documents, technical specs), pre-loaded semantic retrieval may be more efficient. For rapidly changing contexts (code, live data), just-in-time is more accurate.

---

## 15. Agent Harness Design for Long-Horizon Tasks

Anthropic's harness engineering guide (November 2025) addresses the core challenge of long-running agents: context windows are finite and discrete, but complex tasks span many sessions. Each new context window begins with no memory of what came before — like a software team where each engineer arrives for their shift with no recollection of the previous shift's work.

Compaction alone is insufficient. Even Opus 4.5 running in a loop with compaction enabled will fail to build a production-quality application from a single high-level prompt. Two failure modes emerge predictably: the agent tries to do everything at once (one-shotting), runs out of context mid-implementation, and leaves the environment in a broken state; or the agent, later in the project, looks around, sees prior work, and declares the project complete when most features remain unbuilt.

The solution is a two-agent harness split:

**Initializer agent** — runs exactly once on the first session. Its job is to set up the environment so that every subsequent agent can quickly understand the state of work without reading the full history. The initializer creates:
- A feature list file (structured JSON, not Markdown — models are less likely to inadvertently overwrite JSON) enumerating all required capabilities, all initially marked `"passes": false`
- A progress log file recording what has been done, what failed, and what decisions were made
- An `init.sh` script that starts the development environment and runs a basic end-to-end sanity check
- An initial git commit establishing a clean baseline

**Coding agent** — runs on every subsequent session. Its first actions are always: run `pwd`, read the progress log and git history to understand state, read the feature list to find the highest-priority incomplete feature, run `init.sh` to verify the environment is in a working state. It implements exactly one feature per session, tests it end-to-end (not just with unit tests — using browser automation or equivalent to verify as a real user would), commits with a descriptive message, and updates the progress log before the session ends. It is explicitly instructed: do not mark a feature as passing without running end-to-end verification; do not remove or edit tests to make them pass.

The key insight is that **external artifacts become the agent's memory**. The feature list, progress log, and git history persist across sessions. Each new agent reconstructs context from these artifacts rather than from compacted conversation history. This is more reliable than compaction because it captures structured, intentional state — not a summarisation of everything that happened.

### Generalising the harness pattern

While this harness was built for software development, the pattern generalises. Any long-horizon task benefits from the same structure:

- An **initialisation phase** that expands the user's goal into a structured, checkable list of sub-goals before any work begins
- A **progress artifact** (file, database record, external store) that persists state across sessions in a form the agent can read to understand where it is
- A **clean-state rule** that requires each session to end with work in a committed, documented, deployable state — never leaving a feature half-implemented
- **End-to-end verification** before marking any sub-goal complete, not just unit-level checks

The `init.sh` pattern specifically solves the "agent wastes time figuring out how to run the project" problem. Front-load the operational knowledge into a runnable script the agent reads at the start of every session.

### Future directions Anthropic identifies

Anthropic notes two open questions from this work. First: whether a single general-purpose agent outperforms a multi-agent harness with specialised roles (testing agent, QA agent, documentation agent). Second: how to generalise these findings beyond software engineering to other long-horizon domains — scientific research, financial modelling, content production. The underlying principles (structured progress tracking, incremental work, clean state between sessions, end-to-end verification) appear domain-agnostic.

---

## 16. MCP Integration Patterns

The Model Context Protocol (MCP) launched in November 2024 and reached rapid ecosystem adoption — thousands of community-built MCP servers across filesystems, databases, APIs, SaaS products, and internal tools. MCP provides a standardised way to connect agents to external systems without writing custom integration code for each pairing. Implement MCP once in your agent and it unlocks the entire ecosystem.

### What MCP is and what it is not

MCP is a JSON-RPC 2.0 protocol between a **host** (your agent application), a **client** (the MCP connection manager), and one or more **servers** (external systems exposing tools, resources, and prompts). Each MCP server exposes:
- **Tools** — callable functions (search Slack, create Jira issue, query a database)
- **Resources** — readable data sources (files, database records, API responses)
- **Prompts** — reusable prompt templates the agent can invoke by name

MCP is not a replacement for native LangGraph tools — it is a standardisation layer for integrations that would otherwise require bespoke code. Use native LangGraph tools for logic that is core to your agent's reasoning loop; use MCP for integrations with external systems where standardisation and the existing ecosystem add value.

### When to use MCP vs. native tools

**Use MCP** when: connecting to well-supported external services (GitHub, Slack, Google Drive, Asana, Jira, Salesforce) where a community MCP server already exists; when you want users to bring their own tools without modifying your agent code; when you need tool discovery at runtime across many integrations; or when you are building for cross-framework interoperability.

**Use native LangGraph tools** when: the tool implements core agent logic or state management; the tool needs access to LangGraph-specific context (graph state, the store, the checkpointer) that MCP servers cannot see; the tool requires tight control over error handling and retry logic; or when you are building a small, focused agent where the overhead of MCP server management is not worth the abstraction.

**Use both together** — the most common production pattern. Core reasoning tools are native; external integrations are MCP. LangChain's `langchain-mcp-adapters` package converts MCP tools into LangChain tool objects, making them indistinguishable from native tools within a LangGraph agent.

### Integrating MCP into a LangGraph agent

```python
from langchain_mcp_adapters.client import MultiServerMCPClient
from langgraph.prebuilt import create_react_agent

async def build_agent():
    async with MultiServerMCPClient({
        "github": {
            "command": "uvx",
            "args": ["mcp-server-github"],
            "transport": "stdio",
            "env": {"GITHUB_TOKEN": os.environ["GITHUB_TOKEN"]}
        },
        "slack": {
            "url": "https://mcp.slack.com/sse",
            "transport": "sse",
            "headers": {"Authorization": f"Bearer {os.environ['SLACK_TOKEN']}"}
        }
    }) as client:
        tools = await client.get_tools()  # MCP tools as LangChain tool objects
        agent = create_react_agent(llm, tools)
        return agent
```

### Interceptors: bridging MCP and LangGraph runtime context

MCP servers run as separate processes — they cannot see LangGraph state, the store, or the checkpointer. **Interceptors** in `langchain-mcp-adapters` bridge this gap, providing middleware-like control over tool calls:

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

Interceptors can also return `Command` objects to update agent state or route to a different graph node based on tool results — making MCP tools first-class participants in LangGraph control flow.

### Code execution with MCP for context efficiency

As agents connect to more MCP servers, loading all tool definitions upfront and passing intermediate results through the context window becomes expensive. Anthropic's solution: instead of making individual tool calls and accumulating results in context, the agent writes code that orchestrates multiple tool calls, processes intermediate results in the code environment, and returns only the final output to context.

This moves from: N tool calls × (definition tokens + result tokens) to: 1 code execution × (code tokens + summary tokens). For complex multi-tool tasks, this can reduce context consumption by an order of magnitude.

The pattern: configure code execution alongside MCP tools, instruct the agent to write Python scripts that call MCP tools, and configure the code execution environment with access to the MCP client. Anthropic (and independently Cloudflare, who calls this "Code Mode") found this to be one of the most impactful context efficiency improvements for agents with many integrations.

An additional technique: a `search_tools` tool that queries available MCP tool definitions on demand, rather than loading all definitions upfront. The agent searches for the tool it needs, loads only that definition, then calls it. At scale — hundreds of MCP servers, thousands of tools — this is necessary to keep context viable.

### Security considerations for MCP

MCP servers run with whatever permissions they are granted. A malicious or compromised MCP server can instruct the agent to take unintended actions. Apply the same trust tier model as for agent tools (Section 5): audit all MCP server code before use, treat third-party MCP servers as untrusted until verified, never grant MCP servers write access to sensitive systems without pre-execution checks, and use the harness to tokenise sensitive data before it flows through the model (passing tokens rather than real PII to the LLM, detokenising only when data flows between external systems).

---

## 17. Framework Selection

This guide assumes LangGraph because it is the right choice for the described use case: a complex, interactive CLI tool requiring durable execution, human-in-the-loop, memory across sessions, production observability, and explicit state management. But LangGraph is not always the right choice. The decision should be made deliberately.

### Decision framework

**Choose LangGraph when**: you need durable execution (agents that survive process failures); explicit, auditable state management across complex multi-step workflows; human-in-the-loop with state inspection; production observability via LangSmith; or you are already in the LangChain ecosystem. LangGraph 1.0 shipped in October 2025 — it is the first stable major release in this space and is now the default runtime for all LangChain agents. Best for: production-grade agents at companies like Klarna, Replit, and Elastic.

**Choose CrewAI when**: your workflow maps naturally onto human team metaphors (researcher, writer, reviewer); you want fast time-to-first-working-prototype; your team thinks in roles and tasks rather than graphs and state machines. CrewAI's abstraction is the easiest to reason about for business workflow automation. Not ideal for: complex state management, precise control over execution order, or production observability requirements.

**Choose AutoGen / AG2 when**: the workflow is fundamentally conversational — agents debating, negotiating, or refining through dialogue; you need multi-agent group chat patterns; or you have a mixed technical/non-technical team that will use AutoGen Studio's visual interface. AG2 (the community fork of AutoGen) offers declarative serialisation of agent configurations into JSON — a unique capability for reproducible agent definitions.

**Choose PydanticAI when**: type-safe, validated outputs are the primary requirement (financial services, healthcare, compliance-sensitive applications); you want tight integration with Pydantic validation that is already in your stack; or your use case is structured data extraction with guaranteed schema conformance. Fastest raw execution in benchmarks; best for structured task agents with clear output contracts.

**Choose OpenAI Agents SDK when**: you are committed to the OpenAI ecosystem; you want the simplest possible path to multi-agent orchestration with built-in tracing, guardrails, and handoffs; or provider flexibility across 100+ LLMs is more important than framework feature depth. Released March 2025; production-ready but advanced capabilities couple tightly to OpenAI's platform.

**Start with no framework at all when**: the task can be expressed in fewer than 50 lines of Python; you have a single LLM call with retrieval; or you are still in the problem discovery phase. Anthropic: "Many patterns can be implemented in a few lines of code. If you do use a framework, ensure you understand the underlying code — incorrect assumptions about what's under the hood are a common source of error."

### Framework-agnostic skills

A key architectural benefit of the AgentSkills.io standard (Section 8) is that skills are framework-agnostic by construction. Skills written for a LangGraph agent work unchanged in a CrewAI agent, an AutoGen agent, or a plain Python loop. If you later migrate frameworks, your skills migrate for free. This is one of the most concrete arguments for investing in the SKILL.md standard early.

---

## 18. Deployment, Versioning, and Change Management

How you promote changes from development to production for an agentic system differs from traditional software in one important way: the agent's behaviour is determined by the combination of code, model versions, skill/prompt versions, and tool configurations — all of which can change independently and all of which affect quality. A regression in any one of them can silently degrade the agent without any code change.

### The four things that change an agent's behaviour

1. **Code** — graph structure, node logic, routing functions, tool implementations. Track with git, test with unit and integration tests.
2. **Model versions** — when a provider releases a new model, behaviour may change even with identical prompts. Track the model string in LiteLLM config. Run regression evals on the eval dataset before updating model versions in production.
3. **Skill/prompt versions** — changes to SKILL.md files or system prompts. Track with git. Link Langfuse traces to the skill version via metadata (`langfuse_version`). Run dataset experiments in Langfuse before deploying skill changes to production.
4. **Tool configurations** — changes to tool schemas, descriptions, or API backends. Each change should be followed by a tool-calling accuracy check against a golden set of inputs.

### Deployment strategy

Treat agent deployments like staged software releases:

- **Development**: `InMemorySaver`, mock LLMs, `simple-shuffle` pointing to a dedicated dev LiteLLM instance. Fast iteration, no state persistence required.
- **Staging**: real models via LiteLLM, `SqliteSaver` or a staging Postgres instance, full Langfuse tracing with a staging project key. Run the full eval suite before promoting to production.
- **Production**: `PostgresSaver`, full LiteLLM with Redis, Langfuse production project, spend alerts active.

Environment-specific configuration should be a single `settings.py` or config file that the entire system reads. Nothing about which model, which checkpointer, or which Langfuse project should be hardcoded in nodes or tools.

### Rollback

The ability to roll back a bad change quickly is more important than the ability to deploy quickly. Ensure:

- **Skill rollback**: skills are files in git. A bad skill change rolls back with `git revert`. Because skills are loaded at runtime (not compiled into code), a revert is immediately effective without redeployment.
- **Prompt rollback**: if prompts are managed in Langfuse Prompt Management, the `production` label can be repointed to a previous version instantly, with no code change required.
- **Model rollback**: LiteLLM model configuration is a YAML file. Reverting a model version change is a config change, not a code deployment.
- **State migration**: if you change the `AgentState` TypedDict schema, existing checkpointed state may be incompatible. Plan schema migrations carefully — adding `total=False` fields is safe (existing state simply lacks them); removing or renaming fields requires migration logic.

### Monitoring for silent regressions

Because agent behaviour is probabilistic, regressions are often statistical rather than binary. A prompt change might reduce task completion rate from 87% to 79% — visible only if you are tracking the metric systematically. The Langfuse evaluation flywheel (Section 11) is the mechanism that catches this: LLM-as-a-Judge evaluators running continuously on production traces, with alerts when scores drop below threshold. Set a spend alert and a quality score alert from day one. A quality regression and a cost spike are the two failure modes most likely to go unnoticed without automated monitoring.

---

## 19. Agent Debugging: Diagnosis, Root Cause, and Recovery

Agent debugging is fundamentally different from traditional software debugging. In conventional software, a bug produces a deterministic, reproducible failure: the same input always produces the same wrong output. In agentic systems, most failures do not trigger visible errors at all — the system returns a successful status code while producing the wrong result. An agent may select the wrong tool, pass malformed parameters, misinterpret a tool's output, or reason incorrectly about state, and none of this surfaces as an exception. The execution trace completes; the output is simply wrong or subtly degraded.

This silent failure mode, combined with non-determinism (the same input may succeed on one run and fail on another), means that the debugging toolkit for agents must be fundamentally different. You cannot rely on stack traces. You must rely on traces.

### The MAST failure taxonomy (NeurIPS 2025)

The most rigorous empirical study of why multi-agent systems fail is MAST (Multi-Agent System Failure Taxonomy), from UC Berkeley and collaborators, published at NeurIPS 2025 Datasets and Benchmarks Track. Analysed 1,600+ annotated traces across 7 popular MAS frameworks. Identified 14 distinct failure modes with high inter-annotator agreement (κ = 0.88). Organised into three categories.

**Category 1: Specification and system design failures** — failures that originate from how the system was designed before runtime. Includes: underspecified agent roles (agents do not have a clear enough mandate to know what is within or outside their scope), missing or conflicting instructions, poor task decomposition that assigns subtasks no agent is equipped to handle, and ambiguous termination conditions. The key signal: the agent's behaviour is consistent but wrong — it is doing what its design tells it to do, just not what you intended. Fix is in design, not prompts.

**Category 2: Inter-agent misalignment** — failures arising from breakdown in information flow between agents during execution. The 6 sub-modes and their approximate frequencies in the MAST dataset:
- FM-2.1: Unexpected conversation resets (2.2%) — an agent restarts the task as if it has no memory of prior work
- FM-2.2: Proceeding with wrong assumptions instead of seeking clarification (6.8%) — an agent moves forward on an ambiguous handoff rather than asking the sender to clarify
- FM-2.3: Task derailment (7.4%) — the conversation between agents drifts away from the original goal
- FM-2.4: Information withholding (0.85%) — an agent fails to pass critical context to the next agent
- FM-2.5: Ignoring other agents' input (1.9%) — an agent proceeds as if it did not receive information that was sent
- FM-2.6: Mismatch between reasoning and action (13.2%) — the most common; an agent's stated plan does not match what it actually does

The MAST finding that matters most for practitioners: "improvements in base model capabilities will be insufficient to address FC2 failures, which demand deeper social reasoning abilities from agents." Better models do not fix coordination failures — better system design does.

**Category 3: Task verification and termination failures** — agents that complete prematurely, mark tasks done without proper verification, cannot detect their own errors, or loop indefinitely because they lack a clear done condition. This is the category the harness design in Section 15 directly addresses.

### The AgentErrorTaxonomy: single-agent failure attribution

For single-agent flows, the AgentErrorTaxonomy (arXiv:2509.25370) attributes failures to one of four operational modules:

- **Memory errors**: stale or missing context, incorrect retrieval, inability to track prior steps — the agent acts as if it does not know something it was told
- **Reflection errors**: poor self-evaluation, accepting incorrect output as valid, missing the relevance of error feedback
- **Planning errors**: incorrect task decomposition, choosing the wrong strategy, failing to adapt the plan when execution diverges
- **Action errors**: tool misuse, incorrect parameter construction, misinterpreting tool outputs

This attribution is useful for fixing the right thing. A memory error is fixed by improving context management or retrieval. A planning error is fixed by improving the orchestrator's reasoning or decomposition prompts. An action error is fixed by improving tool schemas, descriptions, or examples.

### Symptom-to-cause diagnosis map

The practical starting point when an agent produces bad output is to match the observable symptom to the likely failure category before reading traces. This narrows the search.

| Symptom | Likely category | Where to look first |
|---------|-----------------|---------------------|
| Agent declares task complete when it isn't | Verification/termination | Feature list / done condition / validation node |
| Agent repeats work already completed | Memory / harness | Progress artifacts, context compaction, session state |
| Agent calls the wrong tool | Action / specification | Tool descriptions, schema overlap, tool selection traces |
| Tool is called with wrong parameters | Action | Tool input examples, strict mode, parameter descriptions |
| Agent contradicts itself across turns | Memory / context rot | Context length, observation masking, compaction quality |
| Agent ignores a prior agent's output | Inter-agent (FM-2.5) | Handoff context transfer schema, A2A message structure |
| Agent proceeds on wrong assumption | Inter-agent (FM-2.2) | Clarification instructions, ambiguity handling in prompts |
| Good individual steps, bad overall outcome | Specification / planning | Task decomposition, orchestrator instructions, goal framing |
| Quality degrades as session grows longer | Context rot / memory | Token count per turn, compaction threshold, observation masking |
| High variance (works sometimes, fails others) | Non-determinism | Temperature settings, run k=5 to measure pass rate, inspect divergent traces |
| Cost spike without obvious cause | Loop / redundant calls | Langfuse span counts, node visit frequency, loop guard conditions |

### LangGraph time-travel debugging

LangGraph's checkpointing system is a flight recorder for agent execution. Every super-step saves a complete `StateSnapshot` to the checkpointer. This creates a replayable, branchable history — closer to git commit history than traditional log files.

**Three operations available for any checkpointed run:**

**1. Inspect state history**: retrieve the full execution timeline for a thread, in reverse chronological order

```python
config = {"configurable": {"thread_id": "session-abc"}}
history = list(graph.get_state_history(config))

for snapshot in history:
    print(f"node={snapshot.next}, checkpoint={snapshot.config['configurable']['checkpoint_id']}")
    print(f"state keys: {list(snapshot.values.keys())}")
```

Each `StateSnapshot` contains: the state values at that point, which node runs next, the config needed to resume or fork, the timestamp, and metadata including which node produced the update.

**2. Replay from a checkpoint**: re-execute the graph starting from a specific prior state without re-running earlier nodes. The checkpointer knows which steps have already been executed and skips them.

```python
# Find the checkpoint just before the failing node
before_validation = next(
    s for s in history if s.next == ("validate_node",)
)
# Replay from there -- only validate_node onwards re-executes
result = graph.invoke(None, before_validation.config)
```

Replay is the primary tool for confirming a hypothesis: "I think the failure happened in `validate_node`." Replay from just before that node with the same state and observe whether the failure reproduces.

**3. Fork with modified state**: inject corrected state at a checkpoint and re-execute forward. This is the fix-and-test loop:

```python
# Correct the state at the failing checkpoint
fork_config = graph.update_state(
    before_validation.config,
    {"confidence_score": 0.0, "validation_errors": ["missing summary"]},
    as_node="validate_node"  # attribute the update to this node
)
# Run forward from the corrected state
result = graph.invoke(None, fork_config)
```

The `as_node` parameter tells LangGraph which node produced this update, so it correctly determines which successors to run next. Specify `as_node` explicitly when: forking from a parallel branch (LangGraph cannot infer which of N parallel nodes was "last"), skipping nodes intentionally, or setting initial state on a fresh thread for testing.

**Forking is the "what if" tool**: change one variable — a tool result, a routing decision, a state field — and observe the downstream effect without rerunning the entire expensive flow.

### The binary search approach to root cause isolation

For long traces where the failure point is not obvious, the AgentFail paper (arXiv:2509.23735) demonstrates that a binary search strategy outperforms reading the full trace linearly. The approach:

1. Identify the failing terminal state (the wrong output at the end)
2. Find the checkpoint at the midpoint of the execution trace
3. Inspect that state: is it consistent with correct execution or already corrupted?
4. If already corrupted, the failure is in the first half — recurse there
5. If still consistent, the failure is in the second half — recurse there

In LangGraph, this translates directly to `get_state_history` + inspecting `snapshot.values` at the midpoint checkpoint. Two or three bisection steps typically isolate the failure to a span of 3-5 nodes, which is small enough to read manually.

### Systematic production debugging workflow

When a failure is reported from a production trace, the workflow is:

**Step 1: Classify the symptom** using the symptom-to-cause map above. This determines which section of the trace to read first.

**Step 2: Locate the trace in Langfuse**. Filter by `session_id`, `user_id`, or `trace_id`. Use the timeline view to identify which span consumed the most time (latency failures) or which node was visited anomalously many times (loop failures). Red spans (>75% of total latency) are the starting point for performance failures.

**Step 3: Read the execution transcript, not just the final output**. Anthropic's guidance from their advanced tool use research: "Read agent execution traces, not just final outputs. If the agent wastes time on unproductive steps, common causes include instructions that are too vague, instructions that don't apply to the current task, or too many options presented without a clear default." Look at tool call arguments — not just whether the tool was called, but what parameters it received and what it returned.

**Step 4: Use time-travel to reproduce**. Once you have a hypothesis from step 3, use `get_state_history` + replay to confirm it. A bug is not confirmed until you can reproduce it deterministically from a checkpoint.

**Step 5: Fork to test the fix**. Before changing production code, use `update_state` + fork to verify the fix produces the correct outcome on the failing trace.

**Step 6: Convert to a regression test**. Once fixed, add the failing trace as a dataset item in Langfuse (with the corrected output as expected output). This prevents the same bug from reappearing silently.

### Debugging non-determinism

Because LLMs are probabilistic, the same input may succeed on one run and fail on another. This makes traditional "reproduce the bug" debugging insufficient. The correct approach:

- Run the same input k=5 times and measure the pass rate. If pass rate is 100% or 0%, the failure is deterministic (routing bug, tool schema bug, state mutation bug) — investigate statically. If pass rate is 30-80%, the failure is stochastic — the system is working at the boundary of the model's capability.
- For stochastic failures, the fix is structural (better instructions, clearer tool descriptions, a validation loop that catches and corrects the occasional bad output) rather than prompt-level tweaking.
- Use the `pass@k` metric from the tau-bench evaluation methodology: measure what fraction of runs succeed over k trials. A target of pass@3 > 0.8 is a reasonable production bar for most agent tasks.

### Debugging skills specifically

Skills introduce a distinct failure mode: incorrect activation. The skill either fires when it should not (causing the agent to follow instructions irrelevant to the current task) or fails to fire when it should (causing the agent to work without relevant domain guidance).

The signal for incorrect activation: the agent's behaviour changes unexpectedly mid-conversation, or the agent produces outputs that match a skill's format but are applied to the wrong task. Check the Langfuse trace for `Skill` tool_use observations — these show which skills were loaded and when.

The signal for missed activation: the agent handles a task the skill was designed for but produces generic output, or makes avoidable mistakes that the skill's instructions would have prevented. Compare traces where the skill fires vs. does not fire for similar prompts — if quality is consistently lower without the skill, the description needs to be broader or more explicit.

Use the `skill-creator` eval loop (Section 8) to measure activation rate systematically. Do not attempt to diagnose skill triggering from individual traces — the pass rate across k=3+ runs per query is the relevant metric.

### The failure-to-improvement flywheel

The debugging loop only creates value if failures become future tests. The discipline is: every production failure that takes more than 15 minutes to diagnose gets converted to a Langfuse dataset item before it is closed. Over time, this builds a regression suite that catches the same failure class before it reaches users. The Langfuse evaluation flywheel (Section 11) is the mechanism; the discipline to close the loop after debugging is what makes it compound.

---
*Sources: MAST taxonomy (arXiv:2503.13657, NeurIPS 2025 Spotlight); AgentErrorTaxonomy (arXiv:2509.25370); AgentFail: Demystifying the Lifecycle of Failures in Platform-Orchestrated Agentic Workflows (arXiv:2509.23735); Characterizing Faults in Agentic AI: A Taxonomy of Types, Symptoms, and Root Causes (arXiv:2603.06847); Microsoft Taxonomy of Failure Modes in Agentic AI Systems (April 2025); LangGraph official docs: Use time-travel, Time-travel concepts; Anthropic engineering: Writing Effective Tools for Agents; Langfuse documentation: tracing data model, LLM-as-a-judge; Langchain State of Agent Engineering survey (n=1,340, Dec 2025).*
