---
name: agentic-systems
description: A comprehensive skill collection for designing and building production-grade agentic AI systems. Use when building a new agentic system from scratch, making architectural decisions (workflow vs agent, multi-agent topology, framework selection), implementing LangGraph graphs, adding guardrails and security, configuring persistence and memory, setting up model routing and observability, deploying to production, or debugging agent failures. Also use when the user mentions agents, LangGraph, multi-agent, orchestrator, workflows, agentic architecture, or is working on any AI system that uses tools, has multiple steps, or needs to make decisions at runtime. This collection covers the full lifecycle from design through deployment and maintenance.
---

# Agentic Systems Skills

A framework for designing and building production-grade agentic AI systems, grounded in best practices and standards from Anthropic, LangChain, and current research. The goal is to ensure critical design decisions, security considerations, and architectural patterns are addressed before and during development — not discovered after the system is built.

Building an agentic system without this guidance risks: choosing the wrong architecture and having to rebuild, missing guardrails that become expensive to retrofit, ignoring persistence and memory patterns that cause production failures, or skipping observability that makes debugging impossible. Each skill in this collection addresses a specific concern that is easy to overlook and costly to fix later.

## How to use this collection

**Building from scratch** — work through the design phases below before writing implementation code. Each phase produces design artifacts (architecture decisions, model assignments, guardrail maps, persistence config) that become inputs to implementation. When the design phases are complete, you'll have a comprehensive specification to build against.

**Targeted concern** ("my agent calls the wrong tool" / "set up Langfuse" / "add human-in-the-loop") — go directly to the relevant skill. Each is self-contained.

**Mid-project audit** ("I have a working agent but I'm not sure what I've missed") — scan the skill map below. Any phase you haven't considered is a potential gap worth reviewing before production.

## Design-to-implementation handoff

After completing the relevant design phases, you will have produced some or all of:
- An Architecture Decision Record (pattern, topology, framework, reasoning)
- A model assignment table (which models for which roles, fallback chains)
- Graph stubs (state schema, node functions, wiring, routing)
- A guardrail map (defence layers, trust tiers, timing)
- Persistence configuration (checkpointer, cross-thread memory, compaction)
- A LiteLLM config (routing, fallbacks, budgets)
- A project scaffold (folder structure, DI, testing strategy, deployment pipeline)
- Observability setup (tracing, evaluations, spend alerts)

These are your implementation inputs. Use them as the specification when building the actual system — they encode the decisions and constraints that prevent costly rework.

## Skill map

### Phase 1: Architecture and Design
**What to decide before writing any code. Getting these wrong means rebuilding.**

**`agentic-architecture`**
The foundational decisions: workflow or agent? Which of Anthropic's five building blocks? Single agent or multi-agent, and if multi, which topology? Which framework (LangGraph, CrewAI, AutoGen, PydanticAI, OpenAI Agents SDK, or none)? Start here for any new system. Produces an Architecture Decision Record.
- Load `references/decision-workflows-vs-agents.md` for the workflow/agent criteria
- Load `references/decision-multi-agent-topology.md` for topology comparison with token overhead
- Load `references/decision-framework-selection.md` for framework comparison with limitations
- Complements the community `multi-agent-patterns` skill for topology implementation detail

**`model-selection`**
Which models for which agent roles. The CLASSic evaluation framework (Cost, Latency, Accuracy, Stability, Security). Three-tier routing strategy. Agentic benchmarks (BFCL, SWE-bench, AgentBench, tau-bench). Pass@k for consistency. Produces a model assignment table.
- Load `references/ref-prompt-caching.md` for Anthropic vs OpenAI cache mechanics
- Load `addendums/token-optimisation-anthropic.md` for Batch API, output control, LLMLingua

### Phase 2: Core Implementation
**The patterns and structures that shape the system. These produce graph stubs and design patterns, not final code — but they define what the final code must look like.**

**`langgraph-fundamentals`**
The complete LangGraph implementation: TypedDict state schemas, single-responsibility nodes, edges, routing functions, loop guards, subgraphs, parallelism (Send API), checkpointer wiring, streaming, and human-in-the-loop interrupts. Produces a complete graph.
- Load `addendums/skill-integration-patterns.md` for the dual-use skill-as-node wrapper pattern
- Load `addendums/mcp-langgraph-patterns.md` for MCP interceptors, code execution mode, and lazy tool discovery

**`reflection-and-validation`**
Self-correction patterns: basic reflection (generate-critique-revise), Reflexion with external grounding, Corrective RAG (CRAG) for hallucination detection, validation nodes as first-class graph citizens (programmatic checks before LLM checks), and plan-validate-execute for long-horizon tasks. Produces a validation strategy.

**`inter-agent-communication`**
Communication between agents: three tiers (shared state, tool-based handoffs, A2A protocol), the telephone game problem and the immutable original_request fix, HandoffContext contract, communication architecture patterns (pipeline, hub-and-spoke, swarm, scatter-gather), and failure modes. Produces a communication contract.
- Complements the community `multi-agent-patterns` skill for topology background

### Phase 3: Reliability and Data
**Concerns that are expensive to retrofit. Address before production, not after the first incident.**

**`guardrails-and-security`**
Four-layer defence stack: pre-execution checks (circuit breakers), runtime anomaly detection, output guardrails, and human-in-the-loop escalation. Guardrail timing (async, partial streaming, synchronous). Trust tiers (Gold/Silver/Untrusted). Prompt injection defence (five layers). Memory hygiene. Produces a guardrail map.
- Load `addendums/tool-design-anthropic-api.md` for strict mode and Tool Search Tool
- Complements the community `tool-design` skill for general tool design patterns

**`memory-and-persistence`**
Checkpointer selection (MemorySaver, SqliteSaver, PostgresSaver, RedisSaver). PostgresSaver setup with connection pooling. Cross-thread memory via PostgresStore with namespaced keys. Load/save node patterns. Context rot and three-tier compaction (observation masking first, then LLM summarisation). Produces persistence configuration.
- Load `references/decision-memory-tier.md` for memory type and compaction tier decision tables
- Load `addendums/context-engineering-strategies.md` for Anthropic's Write/Select/Compress/Isolate framework
- Complements the community `memory-systems` skill for backend selection (Mem0, Zep, Letta, Cognee)

### Phase 4: Infrastructure and Operations
**Configuration and scaffolding for the operational environment.**

**`litellm-configuration`**
LiteLLM proxy setup: four routing strategies (simple-shuffle recommended), YAML configuration with fallback chains, hard rate limit enforcement, provider budget caps, tag-based cost tracking, LangGraph integration via model factory, and production deployment checklist (infrastructure, Redis, Kubernetes). Produces a LiteLLM config.
- Load `references/ref-litellm-routing.md` for routing strategy quick-reference

**`project-setup`**
Canonical folder structure for agentic projects. Dependency injection via model factory. Environment-aware configuration (dev/staging/prod). Testing strategy (this skill owns it): unit tests with mock LLMs, integration tests, skill evaluations, trajectory evaluations, non-determinism handling with pass@k. Deployment pipeline stages. Produces a project scaffold.
- Complements the community `project-development` skill for task-model fit and pipeline methodology

**`deployment-and-versioning`**
The four change vectors that affect agent behaviour (code, model versions, skill/prompt versions, tool configurations). Three-environment strategy. Rollback procedures for each vector. State migration for schema changes (safe vs breaking). Statistical quality monitoring — quality score alerts and spend alerts from day one. Produces a versioning plan.

**`langfuse-integration`**
LangGraph-specific Langfuse setup: CallbackHandler integration, custom spans, TTFT tracking, sampling for production. Three evaluation contexts (observation-level, trace-level, experiment-level). The evaluation flywheel (trace -> dataset -> experiment -> deploy). Dataset creation from production failures. Prompt version management. Spend alerts. Produces observability configuration.
- Complements the community `langfuse` skill for general CLI and API access

### Phase 5: Maintenance and Advanced Patterns
**For when things go wrong or the task outgrows a single session.**

**`agent-debugging`**
MAST failure taxonomy (14 modes across 3 categories from NeurIPS 2025). AgentErrorTaxonomy for single-agent failures (memory, reflection, planning, action). Symptom-to-cause diagnosis map. LangGraph time-travel debugging (inspect, replay, fork). Binary search isolation for long traces. Non-determinism debugging with pass@k. The failure-to-improvement flywheel. Produces a root cause diagnosis and regression test.
- Load `references/ref-mast-taxonomy.md` for the full 14 failure modes quick-reference
- Complements the community `evaluation` and `advanced-evaluation` skills for LLM-as-judge patterns

**`agent-harness-design`**
Long-horizon task harnesses for work that spans multiple sessions. The two-agent split: initializer agent (creates feature list JSON, progress log, init.sh, initial commit) and coding agent (one feature per session, end-to-end verification, clean-state rule). Progress artifacts as external memory. Generalises to non-software domains. Produces a harness scaffold.

## Third-party skills

This collection is designed to work alongside these community and vendor skills. They trigger independently on their own descriptions.

**Context engineering** (community): `context-fundamentals`, `context-degradation`, `context-compression`, `context-optimization`, `filesystem-context` — cover context as a discipline, which this collection's implementation skills build on.

**Architecture and tools** (community): `multi-agent-patterns`, `memory-systems`, `tool-design` — cover topology implementation, memory backends, and tool design patterns that complement our architecture and reliability skills.

**Evaluation** (community): `evaluation`, `advanced-evaluation` — cover LLM-as-judge rubrics and evaluation methodology referenced by our debugging and testing skills.

**Project methodology** (community): `project-development` — covers task-model fit and pipeline methodology, complementing our `project-setup` skill.

**Observability** (vendor): `langfuse` — general Langfuse CLI/API access, complementing our LangGraph-specific `langfuse-integration` skill.

**Skill authoring** (vendor): `skill-creator` — full skill authoring, eval loop, and description optimisation.

## Reference docs and addendums

These are loaded by skills on demand — not upfront.

**Decision tables** (`references/`): `decision-workflows-vs-agents.md`, `decision-multi-agent-topology.md`, `decision-framework-selection.md`, `decision-memory-tier.md`

**Quick-reference cards** (`references/`): `ref-mast-taxonomy.md`, `ref-litellm-routing.md`, `ref-prompt-caching.md`

**Addendums** (`addendums/` — extend community skills with provider-specific content): `tool-design-anthropic-api.md`, `token-optimisation-anthropic.md`, `context-engineering-strategies.md`, `mcp-langgraph-patterns.md`, `skill-integration-patterns.md`
