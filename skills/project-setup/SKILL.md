---
name: project-setup
description: Scaffold an agentic project — folder structure, dependency injection, environment configuration, testing strategy, and deployment pipeline. Use this skill when the user needs to set up a new agentic project from scratch, organise their codebase, implement dependency injection via model factory, configure environments (dev/staging/prod), design a testing strategy (unit/integration/eval), or plan deployment pipeline stages. Also use when the user says things like "help me structure my agent project", "set up my project", "how should I organise my code", "what testing strategy for agents", "how do I deploy this", or is starting a new agentic project and needs the scaffolding before building.
---

# Project Setup

This skill scaffolds an agentic project with the canonical folder structure, dependency injection, environment configuration, testing strategy, and deployment pipeline stages.

## Step 1: Understand the project scope

Before scaffolding, get clear on what's being built:

- What architecture pattern? (single agent, orchestrator-worker, etc.)
- What framework? (LangGraph, CrewAI, no framework)
- What external integrations? (MCP servers, A2A agents, APIs)
- What persistence? (MemorySaver, SqliteSaver, PostgresSaver)
- What environments? (local dev only, or dev/staging/prod)

Use decisions from `agentic-architecture` if available.

## Step 2: Apply the canonical folder structure

```
my-agent/
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
|   |   +-- subgraphs/           # Only if subgraphs are justified
|   |   +-- routing.py           # All routing functions (pure, testable, no LLM calls)
|   +-- state/
|   |   +-- schema.py            # AgentState TypedDict, reducers, InputState, OutputState
|   |   +-- checkpointing.py     # Checkpointer factory (SQLite dev, Postgres prod)
|   |   +-- memory.py            # Store factory, memory load/save nodes
|   +-- tools/
|   |   +-- registry.py          # Tool registry + dynamic discovery
|   |   +-- guardrails.py        # Pre-tool checks, risk classification
|   |   +-- <tool>.py            # Individual tool implementations
|   +-- skills/
|   |   +-- loader.py            # Framework-agnostic SKILL.md loader
|   +-- agents/                  # Only if using A2A
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
```

Not every project needs every directory. Scale the structure to the project — a simple single-agent CLI doesn't need `agents/`, `subgraphs/`, or `skill_evals/`.

## Step 3: Implement dependency injection

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

## Step 4: Configure environments

Single config file, environment-aware:

```python
class AgentConfig:
    env: Literal["dev", "staging", "prod"]
    litellm_host: str
    litellm_port: int
    litellm_key: str
    model_names: dict[str, str]
    checkpointer_type: Literal["memory", "sqlite", "postgres"]
    db_url: str | None
    langfuse_project: str | None
```

What changes between environments:
- **Dev**: `MemorySaver`, mock LLMs or direct API, no Langfuse
- **Staging**: real models via LiteLLM, `SqliteSaver` or staging Postgres, Langfuse staging project
- **Prod**: `PostgresSaver`, full LiteLLM with Redis, Langfuse production project, spend alerts active

Nothing about which model, which checkpointer, or which Langfuse project should be hardcoded in nodes or tools.

## Step 5: Design the testing strategy (this skill owns it)

Four testing tiers:

**Unit tests** (every commit, <1 second each):
- Node functions with mock LLMs (`GenericFakeChatModel`)
- Routing functions — pure functions on state, no LLM needed
- Tool logic and guardrail checks

**Integration tests** (per PR, ~10 seconds):
- Full graph executions with `InMemorySaver` and mock LLMs
- Verify state persistence, correct routing, loop termination

**Skill evaluations** (nightly):
- with_skill vs without_skill runs
- Assertion grading, benchmark aggregation, delta tracking

**Trajectory evaluations** (nightly):
- Full multi-step runs with LLM-as-a-Judge via Langfuse datasets
- Measure task completion rate, tool call efficiency, output quality

**Agentic testing principles:**
- Handle non-determinism: run each test case 5-10 times, assert on statistical properties (pass rate >80%, not always-pass)
- **Eval-driven development**: define evaluations before building capabilities — the agent equivalent of TDD
- Link all eval traces to specific skill/prompt versions for regression tracking
- The CLASSic framework (Cost, Latency, Accuracy, Stability, Security) is the evaluation rubric for model changes

## Step 6: Define deployment pipeline stages

What gets validated at each stage:

| Stage | Validation | Gate |
|-------|-----------|------|
| **Commit** | Unit tests pass | Automated |
| **PR** | Unit + integration tests pass | Automated + reviewer |
| **Staging** | Full eval suite on staging models | Quality score threshold |
| **Production** | Canary deployment, quality monitoring | Statistical quality check |

## Step 7: Present the scaffold

Output:

1. **Folder structure** — adapted to the project's actual scope (not every directory if not needed)
2. **Model factory** — dependency injection code
3. **Config** — environment-aware settings with what changes per environment
4. **Testing strategy** — which tiers apply, example tests for each
5. **Deployment pipeline** — stages and gates appropriate to the project's maturity
