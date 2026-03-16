# Agentic Systems Skills & Artifacts Plan

## Purpose

This document defines what needs to be built, what already exists and should be installed, and the strategy for each. It is the companion to `agentic-systems-reference-guide.md`, which is the source-of-truth for content.

A skill here means a `SKILL.md` folder that an agent loads on demand to execute a specific design task with step-by-step guidance, decision trees, working code patterns, and clear outputs. The target consumer is any agent (Claude Code, Cursor, or similar) helping design or build agentic systems. The agentic systems being designed are model-agnostic — nothing in these skills assumes a specific LLM provider.

---

## Prerequisites

Before building any skills, the following must be in place.

**1. Claude Code installed and configured**
The `skill-creator` eval loop runs through Claude Code — it spins up agent runs, captures transcripts, and grades them. Without Claude Code, you can't run the build process properly.

**2. `skill-creator` accessible via symlink**
`skill-creator` is Anthropic's official skill for building and evaluating skills. Clone the Anthropic skills repo and symlink it into your global Claude skills directory:

```bash
# Clone the Anthropic skills repo to a stable location
git clone https://github.com/anthropics/skills.git ~/skills/anthropic-skills

# Symlink skill-creator globally so it's available in all projects
ln -s ~/skills/anthropic-skills/skills/skill-creator ~/.claude/skills/skill-creator

# Optionally symlink mcp-builder as well
ln -s ~/skills/anthropic-skills/skills/mcp-builder ~/.claude/skills/mcp-builder
```

Verify Claude Code can see it:
```bash
ls ~/.claude/skills/
# should show skill-creator (and mcp-builder if symlinked)
```

**3. Third-party skills cloned and symlinked**
Before building skills that reference the community repo or Langfuse skills, clone and symlink them so Claude Code can access them during build sessions and so you can verify references don't duplicate content that already exists:

```bash
# Create the external skills directory
mkdir -p ~/skills/external

# Clone the community context engineering repo
git clone https://github.com/muratcankoylan/Agent-Skills-for-Context-Engineering.git ~/skills/external/context-engineering

# Clone the Langfuse skills repo
git clone https://github.com/langfuse/skills.git ~/skills/external/langfuse-skills

# Symlink each skill individually into ~/.claude/skills/
# Context engineering skills
ln -s ~/skills/external/context-engineering/skills/context-fundamentals ~/.claude/skills/context-fundamentals
ln -s ~/skills/external/context-engineering/skills/context-degradation ~/.claude/skills/context-degradation
ln -s ~/skills/external/context-engineering/skills/context-compression ~/.claude/skills/context-compression
ln -s ~/skills/external/context-engineering/skills/context-optimization ~/.claude/skills/context-optimization
ln -s ~/skills/external/context-engineering/skills/filesystem-context ~/.claude/skills/filesystem-context
ln -s ~/skills/external/context-engineering/skills/multi-agent-patterns ~/.claude/skills/multi-agent-patterns
ln -s ~/skills/external/context-engineering/skills/memory-systems ~/.claude/skills/memory-systems
ln -s ~/skills/external/context-engineering/skills/tool-design ~/.claude/skills/tool-design
ln -s ~/skills/external/context-engineering/skills/evaluation ~/.claude/skills/evaluation
ln -s ~/skills/external/context-engineering/skills/advanced-evaluation ~/.claude/skills/advanced-evaluation
ln -s ~/skills/external/context-engineering/skills/project-development ~/.claude/skills/project-development

# Langfuse skills
ln -s ~/skills/external/langfuse-skills/skills/langfuse ~/.claude/skills/langfuse
ln -s ~/skills/external/langfuse-skills/skills/langfuse-observability ~/.claude/skills/langfuse-observability
ln -s ~/skills/external/langfuse-skills/skills/langfuse-prompt-migration ~/.claude/skills/langfuse-prompt-migration
```

To update any third-party skill later, just pull in the cloned repo — symlinks pick up the changes automatically:
```bash
cd ~/skills/external/context-engineering && git pull
cd ~/skills/external/langfuse-skills && git pull
```

**4. Create the `agentic-systems-skills` repo**
Initialise the repo with the following structure before building any skills. This keeps everything self-contained — when you clone to a new machine, the content source for skill building comes with it.

```
agentic-systems-skills/
├── README.md
├── skills/                         # Skills you build — one folder per skill
│   ├── agentic-architecture/
│   │   └── SKILL.md
│   ├── langgraph-state-and-nodes/
│   │   └── SKILL.md
│   └── ...
├── references/                     # Ref doc and decision tables
│   ├── agentic-systems-reference-guide.md
│   ├── decision-workflows-vs-agents.md
│   ├── decision-multi-agent-topology.md
│   ├── decision-framework-selection.md
│   └── decision-memory-tier.md
└── addendums/                      # Short extensions to community skills
    ├── tool-design-anthropic-api.md
    └── token-optimisation-anthropic.md
```

Per-project installation once the repo exists:
```bash
git clone https://github.com/[your-username]/agentic-systems-skills.git ~/skills/agentic-systems-skills

# Symlink individual skills into a project
ln -s ~/skills/agentic-systems-skills/skills/agentic-architecture .claude/skills/agentic-architecture

# Or symlink globally for use across all projects
ln -s ~/skills/agentic-systems-skills/skills/agentic-architecture ~/.claude/skills/agentic-architecture
```

**6. Ref doc accessible to Claude Code**
The `agentic-systems-reference-guide.md` lives in `references/` within the repo. Point Claude Code to it by path when prompting `skill-creator` for each build session.

**7. Anthropic API key with sufficient quota**
`skill-creator` runs multiple agent eval passes per skill iteration. Each skill build will consume meaningful tokens — expect 50–200k per skill depending on eval iterations.

---

## Install Strategy

Skills fall into two categories:

**Third-party skills** — Clone to `~/.claude/skills/external/` once and symlink globally. These work across all projects without per-project setup. Update by pulling the upstream repo when needed.

**Your own skills** — Live in their own repository. Installable per-project by cloning and symlinking into `.claude/skills/`, or globally into `~/.claude/skills/`.

Skills in this library are designed to function independently. Third-party skills are enriching context — an agent using `inter-agent-communication` without `multi-agent-patterns` installed still gets complete, actionable guidance. No submodule coupling or version pinning required.

---

## What Already Exists — Install, Don't Build

### Anthropic official skills
Available at `/mnt/skills/examples/` in this environment, or from `github.com/anthropics/skills`.

| Skill | What it covers |
|---|---|
| `skill-creator` | Full skill authoring, eval loop, description optimisation, benchmarking |
| `mcp-builder` | MCP server building in Python (FastMCP) and TypeScript |

### Langfuse official skills
```
git clone https://github.com/langfuse/skills.git ~/.claude/skills/external/langfuse-skills
```

| Skill | What it covers |
|---|---|
| `langfuse` | General Langfuse operation: traces, prompts, datasets, scores via CLI and API |
| `langfuse-observability` | Instrumenting LLM applications: detects frameworks, sets up tracing correctly for each |
| `langfuse-prompt-migration` | Migrating hardcoded prompts to Langfuse prompt management |

### Community context engineering skills
```
git clone https://github.com/muratcankoylan/Agent-Skills-for-Context-Engineering.git ~/.claude/skills/external/context-engineering
```

These skills have been read in full. They are well-written, actively maintained (some updated Feb 2026), and directly relevant. Their focus is context engineering as a discipline — managing what enters the model's attention window. They complement the skills we build rather than duplicate them.

| Skill | What it covers | Effect on build list |
|---|---|---|
| `context-fundamentals` | Attention mechanics, progressive disclosure, context anatomy, context budgeting | Replaces planned `context-engineering` |
| `context-degradation` | Lost-in-middle, context poisoning, distraction, clash — patterns and mitigations | Replaces planned `context-engineering` |
| `context-compression` | Anchored iterative summarisation, tokens-per-task optimisation, probe-based eval | Replaces planned `context-engineering` |
| `context-optimization` | Compaction, observation masking, KV-cache optimisation, context partitioning | Replaces planned `context-engineering` and `token-and-latency-optimisation` |
| `filesystem-context` | Scratch pads, plan persistence, sub-agent file workspaces, dynamic skill loading | Not in original plan — install and use |
| `multi-agent-patterns` | Supervisor/swarm/hierarchical topologies, context isolation rationale, token economics, telephone game problem and fix | Referenced by `agentic-architecture` and `inter-agent-communication` |
| `memory-systems` | Memory backends: Mem0, Zep/Graphiti, Letta, Cognee — benchmarks, retrieval strategies, temporal graphs | Complements `memory-and-persistence`; covers backends, we cover LangGraph persistence |
| `tool-design` | Contracts, consolidation, architectural reduction, description engineering, response format, error messages, MCP naming, agent-optimisation loop | Replaces planned `tool-design` |
| `evaluation` | Multi-dimensional rubrics, LLM-as-judge, test set design, non-determinism handling, continuous evaluation | Referenced by `agent-debugging` |
| `advanced-evaluation` | Direct scoring vs pairwise, position bias mitigation, rubric generation, confidence calibration | Not in original plan — install and use |
| `project-development` | Task-model fit, pipeline architecture, file system as state machine, structured output, architectural reduction | Referenced by `project-setup` |
| `hosted-agents` | Sandboxed VM infrastructure, image registries, warm pools, multiplayer, multi-client | Not in current scope — install if building background agent infrastructure |
| `bdi-mental-states` | BDI ontology, belief-desire-intention modelling, RDF integration | Not relevant to current scope |

---

## Addendum Docs — Short Extensions to Community Skills

Not skills. Short reference documents that sit alongside the relevant community skill and cover gaps that exist only because the community skills are deliberately vendor-neutral.

### `tool-design-anthropic-api.md`
Extends the community `tool-design` skill with three Anthropic API-specific features:
- **Strict mode**: `"strict": True` in tool definition schema — guarantees schema conformance, prevents type coercion errors
- **Tool Use Examples**: the `input_examples` field — schemas can't express usage patterns; examples improved accuracy from 72% to 90% in Anthropic testing
- **Tool Search Tool**: `tool_search_tool_regex_20251119` type — on-demand tool discovery for agents with hundreds of tools, preventing 50,000+ token upfront loading
- **Programmatic Tool Calling**: Claude writes Python to orchestrate tool calls rather than natural language invocation — reduced context from 200KB to 1KB on complex tasks

### `token-optimisation-anthropic.md`
Extends the community `context-optimization` skill with provider-specific mechanics:
- Anthropic prompt caching: cache breakpoint placement, 5-minute TTL implication, what content is cacheable
- Observation masking data: JetBrains research — 52% cost reduction, 2.6% solve rate improvement
- Batch API: when to use it, tradeoffs vs real-time
- Output length control: specific techniques for preventing verbose completions

---

## Skills to Build

These 15 skills have no adequate equivalent in any existing resource. Each is designed to function independently.

All skills should be built using `skill-creator` at `/mnt/skills/examples/skill-creator/`. Content input for each comes from the indicated sections of `agentic-systems-reference-guide.md`.

**Before drafting any skill**, read the ref doc sections listed in the plan entry and derive the skill workflow from them — the sequence of steps, decision points, and order of operations the skill should guide an agent through. Use that derived workflow as the brief for `skill-creator`. Do not draft the skill without completing this step first.

---

### Tier 1 — Architecture and Design Decisions

---

#### `agentic-architecture`
**Ref doc sections:** 13 (Workflows vs Agents), 12 (Complete Project Architecture), 17 (Framework Selection)

**What it covers:**
- The workflows vs. agents decision: the five Anthropic workflow building blocks (prompt chaining, routing, parallelisation, orchestrator-subagents, evaluator-optimiser) and when each applies
- The practical decision test: is the task open-ended with unpredictable steps, or can it be hardcoded?
- Multi-agent pattern selection: which topology for which task characteristics, with decision table
- Framework selection: LangGraph vs CrewAI vs AutoGen vs PydanticAI vs OpenAI Agents SDK vs no framework
- When to add complexity vs. stay with a simple loop

**References:** `multi-agent-patterns` community skill for topology detail

**Output:** An architecture decision record with chosen pattern and rationale

---

#### `model-selection`
**Ref doc section:** 1

**What it covers:**
- Role-based model mapping: which model class (frontier reasoning / capable mid-tier / fast cheap) for which agent role
- The CLASSic framework for capability-cost tradeoffs
- Three-tier routing strategy with concrete cost and latency thresholds
- Agentic benchmarks worth trusting: BFCL for tool use, SWE-bench for coding
- How to update model assignments as the landscape shifts — the framework, not specific model names

**Output:** A model assignment table for the agent system being designed

---

### Tier 2 — LangGraph Implementation

---

#### `langgraph-fundamentals`
**Ref doc section:** 2 (all subsections)

**What it covers — primitives:**
- TypedDict state schema conventions: what belongs in state, what doesn't, reducer selection
- Node single-responsibility principle: one concern per node, what that means in practice
- Node return conventions: partial state updates, how reducers merge them
- Edge types: unconditional, conditional, and when to use each
- Routing function patterns: clean, testable routing logic
- Loop guards: detecting and preventing runaway loops

**What it covers — advanced features:**
- Subgraph boundaries: when to extract, how to wire, state isolation
- Parallelism: the Send API and fan-out/fan-in patterns
- Checkpointer wiring: `graph.compile(checkpointer=...)` syntax (selection decision owned by `memory-and-persistence`)
- Streaming: token streaming vs. node streaming vs. update streaming
- Human-in-the-loop interrupt API: `interrupt()`, `Command(resume=...)`, the caller loop (architectural HITL decisions owned by `guardrails-and-security`)
- Node testability: isolation patterns with mock LLMs (full testing strategy owned by `project-setup`)

**Output:** A complete LangGraph graph — state schema, node stubs, wiring, routing logic, and configuration

**Rationale for merge:** The ref doc presents section 2 as one continuous topic. State, nodes, and edges are always designed together in the same session. Splitting them forced two skill invocations for one design activity.

---

#### `reflection-and-validation`
**Ref doc section:** 3

**What it covers:**
- Generate-critique-revise loop: when it's worth the cost, when it isn't
- Reflexion pattern: persistent memory of past failures with external grounding
- CRAG: detecting low-confidence retrieval and triggering corrective search
- Validation nodes as first-class graph citizens: programmatic checks before LLM checks
- Plan-validate-execute: structuring long-horizon tasks to validate before committing

**Excludes:** Tool-level error handling — that belongs in the community `tool-design` skill

**Output:** A validation strategy appropriate to the task type and stakes

---

### Tier 3 — Reliability and Safety

---

#### `guardrails-and-security`
**Ref doc section:** 5

**What it covers:**
- Four-layer defence stack: input validation, pre-tool checks, output validation, anomaly detection
- Guardrail timing: which checks at which point in the graph
- Trust tier assignment: classifying principals, what each tier can do
- Human-in-the-loop as a guardrail: when HITL escalation is architecturally warranted (interrupt API mechanics owned by `langgraph-fundamentals`)
- Prompt injection defence: what it looks like in practice, detection patterns
- Memory hygiene: what to persist, what to discard, sanitisation before storage

**Output:** A guardrail map — what is checked where, and what happens on failure

---

#### `inter-agent-communication`
**Ref doc section:** 4

**What it covers:**
- Shared state communication: what goes in shared state vs. passed as tool arguments
- Tool-based handoffs: the swarm pattern, how agents transfer control
- The telephone game problem and the `forward_message` tool solution
- A2A protocol: when to use it over shared-state approaches, the context transfer contract
- Communication failure modes: what happens when a subagent returns bad output

**References:** `multi-agent-patterns` community skill for topology background

**Excludes:** Topology selection — that belongs in `agentic-architecture`

**Output:** A communication contract between agents in the system being designed

---

### Tier 4 — Data and State Management

---

#### `memory-and-persistence`
**Ref doc section:** 6

**What it covers:**
- Checkpointer selection decision: MemorySaver vs SqliteSaver vs PostgresSaver vs RedisSaver — when each is appropriate (this skill owns the selection; `langgraph-fundamentals` covers wiring syntax only)
- LangGraph checkpointing: PostgresSaver setup with connection pool configuration
- LangGraph cross-thread memory: PostgresStore setup with namespaced keys
- Load and save node patterns: how to wire memory in and out of graphs
- Context rot in long runs: LangGraph-specific compaction triggers (general context degradation covered by community `context-degradation` skill)

**Complements:** `memory-systems` community skill covers backends (Mem0, Zep, Letta, Cognee); this skill covers LangGraph-specific persistence wiring

**Excludes:** Memory backend selection — that belongs in the community `memory-systems` skill

**Output:** Working checkpointer/store setup code and a load/save node pattern for the graph

---

### Tier 5 — Integrations

---

#### `mcp-integration`
**Ref doc section:** 16

**What it covers:**
- `langchain-mcp-adapters`: converting MCP tools to LangChain-compatible tools for LangGraph
- MCP vs. native tools decision: latency, versioning, security tradeoffs
- Interceptor pattern: adding logging and validation between agent and MCP server
- Code execution with MCP for context efficiency
- Security considerations: tool annotations for open-world access and destructive operations

**Complements:** `mcp-builder` Anthropic skill covers server-side; this skill covers client-side integration

**Output:** A working MCP client integration in a LangGraph graph

---

### Tier 6 — Infrastructure and Operations

---

#### `litellm-configuration`
**Ref doc section:** 10

**What it covers:**
- Four routing strategies and which to choose: simple fallback, load balancing, latency-based, cost-based
- Complete working YAML configuration with fallback chains
- Hard rate limits and budget enforcement per model and per deployment
- LangGraph integration: wiring LiteLLM as the model abstraction layer
- Production checklist before deploying behind LiteLLM

**Output:** A working LiteLLM config for the deployment being built

---

#### `project-setup`
**Ref doc section:** 12

**What it covers:**
- Canonical folder structure for an agentic project
- Dependency injection via model factory: keeping model selection out of graph code
- Environment configuration: env vars vs. config files vs. code
- Testing strategy (this skill owns it): unit testing nodes, integration testing graphs, eval-based testing agents, non-determinism handling
- Deployment pipeline stages: what gets validated at each stage

**References:** `project-development` community skill for task-model fit and pipeline methodology

**Output:** A scaffolded project structure ready to build into

---

#### `deployment-and-versioning`
**Ref doc section:** 18

**What it covers:**
- Four change vectors: model updates, prompt changes, tool changes, graph structure changes
- Three-environment strategy: development, staging, production with rollback procedures
- Statistical quality monitoring: metrics to track, thresholds that trigger rollback
- Breaking vs. non-breaking changes in agentic systems

**Output:** A versioning and rollback plan for the agent system

---

#### `langfuse-integration`
**Ref doc section:** 11

**What it covers:**
- LangGraph integration: `CallbackHandler` setup for auto-tracing nodes, LLM calls, and tool calls
- Manual custom spans and TTFT tracking for fine-grained observability
- Sampling configuration for high-volume production workloads
- The evaluation flywheel: trace → error analysis → datasets → experiments → deploy → trace
- Three evaluation contexts: observation-level, trace-level, experiment-level
- Dataset creation from production failures — the highest-value dataset source
- Prompt/skill version management via Langfuse Prompt Management
- Cost tracking, spend alerts, and the bottleneck diagnosis methodology (trace timeline, Agent Graphs view)

**Complements:** `langfuse` community skill covers general Langfuse CLI and API access; this skill covers LangGraph-specific integration patterns and the evaluation flywheel workflow

**Excludes:** General Langfuse API usage — that belongs in the community `langfuse` skill

**Output:** Working Langfuse integration code, an evaluation flywheel setup, and spend alert configuration

---

### Tier 7 — Debugging and Quality

---

#### `agent-debugging`
**Ref doc section:** 19

**What it covers:**
- MAST taxonomy: the 14 failure modes in 3 categories — how to recognise each in traces
- Symptom-to-cause diagnosis map: observable failure → likely root causes
- LangGraph time-travel: `get_state_history`, replay, and fork — how to use them in practice
- Binary search isolation: systematically narrowing where in a multi-step run the failure occurs
- Non-determinism debugging: pass@k methodology for intermittent failures
- Failure-to-improvement flywheel: turning a diagnosed failure into a regression test

**References:** `evaluation` and `advanced-evaluation` community skills for LLM-as-judge patterns; Langfuse skills for trace navigation

**Output:** A root cause diagnosis and a regression test for the failure being investigated

---

#### `agentic-skill-patterns`
**Ref doc section:** 8

**What it covers:**
- When to use a skill vs. inline prompt instructions vs. a tool
- The dual-use wrapper pattern: a skill that is also invocable as a tool by an agent
- Wiring skills into LangGraph flows: skill as a node, skill as a subgraph
- SKILL.md body patterns for operational agent skills
- Progressive disclosure for large skills: MODULE.md pattern

**Excludes:** Skill authoring process — that belongs in `skill-creator`

**Output:** A decision on skill vs. inline prompt for each capability, with wiring code where skills are chosen

---

#### `agent-harness-design`
**Ref doc section:** 15

**What it covers:**
- Long-horizon task harness patterns: the Anthropic initialiser/coding agent split
- Feature list JSON: how to structure task decomposition for long runs
- Progress artifacts: what to write to disk and when, so the agent can resume cleanly
- The clean-state rule: what the harness must guarantee before handing off to the agent
- End-to-end verification: confirming the harness, not just the agent, is working correctly
- init.sh pattern: environment setup the agent should never have to redo

**Output:** A working harness scaffold for the long-horizon task being built

---

## Supporting Reference Docs

Short standalone documents extracted or derived from the ref doc. Not skills — these are loaded as references, linked from relevant skills, or used directly during design work.

### Decision tables (extracted from ref doc)
| Doc | Source section |
|---|---|
| `decision-workflows-vs-agents.md` | Section 13 |
| `decision-multi-agent-topology.md` | Section 12 |
| `decision-framework-selection.md` | Section 17 |
| `decision-memory-tier.md` | Section 6 |

### Addendum docs
| Doc | Extends |
|---|---|
| `tool-design-anthropic-api.md` | Community `tool-design` skill |
| `token-optimisation-anthropic.md` | Community `context-optimization` skill |
| `context-engineering-strategies.md` | Community `context-fundamentals` skill — adds Anthropic's four-strategy framework (Write/Select/Compress/Isolate) and just-in-time vs pre-loaded context patterns from ref doc section 14 |

### Quick-reference cards
| Doc | Content |
|---|---|
| `ref-mast-taxonomy.md` | 14 failure modes with observable symptoms — for use during debugging |
| `ref-litellm-routing.md` | Four routing strategies with decision criteria |
| `ref-prompt-caching.md` | Cache breakpoint mechanics for Anthropic and OpenAI |

---

## Build Order

1. **`agentic-architecture`** — sets the frame for everything else
2. **`langgraph-fundamentals`** — core LangGraph primitives and features
3. **`guardrails-and-security`** + **`memory-and-persistence`** — needed before any production work
4. **`inter-agent-communication`** — builds on architecture decisions
5. **`reflection-and-validation`** — self-contained, build when needed
6. **`model-selection`** + **`litellm-configuration`** — infrastructure foundation
7. **`mcp-integration`** + **`project-setup`** + **`deployment-and-versioning`** — operational layer
8. **`langfuse-integration`** — observability (after project-setup establishes the testing strategy it references)
9. **`agent-debugging`** + **`agentic-skill-patterns`** + **`agent-harness-design`** — quality and advanced patterns
9. Decision tables, addendum docs, and quick-reference cards — extract and format last

---

## Summary

| Category | Count | Action |
|---|---|---|
| Anthropic official skills | 2 | Already at `/mnt/skills/examples/` |
| Langfuse official skills | 3 | `git clone langfuse/skills` → symlink globally |
| Community context engineering skills | 11 relevant of 13 | `git clone muratcankoylan/Agent-Skills-for-Context-Engineering` → symlink globally |
| Skills to build | 15 | Build using `skill-creator` |
| Addendum docs | 3 | Short markdown, sit alongside community skills |
| Decision tables | 4 | Extract from ref doc |
| Quick-reference cards | 3 | Write new |
