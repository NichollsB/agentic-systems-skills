---
name: agentic-architecture
description: Guide architectural decisions for agentic AI systems — choosing between workflows and agents, selecting multi-agent topologies, picking reasoning patterns, and evaluating frameworks. Use this skill when the user wants to design an agentic system, decide whether they need workflows or autonomous agents, choose between LangGraph/CrewAI/AutoGen/PydanticAI/OpenAI Agents SDK, select a multi-agent topology (orchestrator-worker, supervisor, swarm, hierarchical), or make any foundational architectural decision about how their AI system should be structured. Also use when the user says things like "how should I architect this agent", "do I even need agents for this", "should I use LangGraph or CrewAI", "help me design my AI pipeline", or is starting a new agentic project and hasn't settled on an approach yet.
---

# Agentic Architecture

This skill walks through the foundational architectural decisions for an agentic AI system, in the order they should be made. Each decision narrows the design space for the next.

Use the steps below to reason through the decisions, but present the output as an Architecture Decision Record (ADR) — conclusions and justifications, not the full thinking process. The user wants to see what was decided and why, not a log of every consideration along the way.

## Step 1: Understand the task

Before making any architectural choices, get clear on what the system needs to do. Ask the user:

- What is the core task? What does success look like?
- How many distinct steps or subtasks are involved?
- Are the steps predictable in advance, or do they depend on what happens at runtime?
- What are the failure modes that matter most?
- What are the constraints? (latency, cost, auditability, team familiarity)

If the user has already described the task in the conversation, extract answers from context first and confirm rather than re-asking.

## Step 2: Workflow or agent?

This is the most important architectural fork. Everything else follows from it.

**Workflow**: The LLM fills in content within a fixed, predefined control flow. The path through the system is known at compile time.

**Agent**: The LLM dynamically directs its own processes and tool usage. The path is not known in advance — it emerges from the model's decisions at each step.

### The practical test

Ask: *Can a junior developer draw a complete flowchart for this task before any input arrives?*

- **Yes** → workflow. The steps are predictable, the branching is finite, and the logic can be hardcoded.
- **No, because the right path depends on what the environment returns at each step** → agent.

Most production AI today is workflows. Anthropic's guidance: "find the simplest solution possible and only increase complexity when needed." A single well-prompted LLM call with retrieval handles the majority of real-world tasks.

### The key tradeoff

Agents trade latency and cost for flexibility. Every step requires an LLM call. Errors compound — a wrong tool selection in step 2 corrupts context for steps 3 through 10. Agents require sandboxed testing and guardrails that workflows do not.

If the answer is "workflow", proceed to Step 3a. If "agent", proceed to Step 3b.

## Step 3a: Select a workflow building block

Anthropic defines five workflow patterns, ordered by complexity. Choose the simplest one that handles the task's known failure modes.

| Pattern | What it does | Use when |
|---------|-------------|----------|
| **Prompt chaining** | Sequential LLM calls, each feeding the next | Task is too complex for one call, or you need verification gates between steps |
| **Routing** | Classify input, send to specialised handler | Tasks are clearly distinct categories (support routing, intent classification) |
| **Parallelisation** | Run independent subtasks simultaneously, aggregate | Subtasks are independent. Two variants: *sectioning* (different subtasks) and *voting* (same task repeated for variance reduction on high-stakes decisions) |
| **Orchestrator-workers** | Central LLM decomposes task and delegates at runtime | The decomposition itself can't be known in advance, but the execution of each subtask can |
| **Evaluator-optimizer** | One LLM generates, another evaluates in a loop | Quality can be judged iteratively and you have clear "good enough" criteria |

All five can be expressed in LangGraph, but several need nothing more than a few lines of Python. Start without a framework and add one only when you hit a problem that requires it.

After selecting, skip to Step 4.

## Step 3b: Single agent or multi-agent?

Not every agent task needs multiple agents. Multi-agent systems use roughly **15x more tokens** than single-agent. The capability gain must justify this cost.

### Start with single agent + tools when:
- The task fits in one context window
- Fewer than ~5 tool-use steps
- No independent subtasks that could run in parallel
- No distinct source types, retrieval domains, or specialist reasoning

### Move to multi-agent when:
- Subtasks are **independent and parallelisable** — e.g., searching multiple source types simultaneously. An orchestrator fans out to worker agents, each handling one source, then aggregates results. This is the scatter-gather pattern.
- Subtasks require **different specialist reasoning** — not just different API calls, but genuinely different approaches to the problem.
- The **context would be too large** for a single agent — splitting across workers keeps each agent's context focused.

The token overhead (3-15x) is real, but parallelisation can reduce wall-clock time significantly. The decision is not just about whether a single agent *could* do it, but whether workers would do it better — faster, more focused, with cleaner context.

### If multi-agent is justified, select a topology:

| Topology | Use when | Token overhead | Control level |
|----------|----------|---------------|---------------|
| **Orchestrator-worker** | Dynamic decomposition; parallel subtasks | 3-5x | High |
| **Supervisor** | Fixed specialist domains; quality control needed | 3-5x | Highest |
| **Swarm (handoffs)** | Exploratory; agents decide scope autonomously | 3-5x | Lowest |
| **Hierarchical teams** | Multiple distinct domains with internal coordination | 10-15x | Medium |

Key questions for topology selection:
- **Do you need a central controller?** → Orchestrator-worker or Supervisor
- **Do agents need to hand off to each other dynamically?** → Swarm
- **Are there multiple teams, each with their own internal coordination?** → Hierarchical
- **Is quality control the primary concern?** → Supervisor (it can reject and reassign)

The `multi-agent-patterns` skill covers topology implementation in detail — reference it when the user moves to implementation.

## Step 4: Select a reasoning pattern

This determines how individual agents (or the single agent) approach multi-step work.

| Pattern | How it works | Best for | Cost profile |
|---------|-------------|----------|-------------|
| **ReAct** | Thought → action → observation loop, one LLM call per step | Simple tasks (<5 steps) with unpredictable branching | High per-step |
| **Plan-and-execute** | Frontier model plans; cheaper model executes steps. Includes a replanning node that triggers when execution diverges from the plan | Complex multi-step tasks; parallelisable steps | Better — cheap execution |
| **Reflection** | Generate → critique → revise loop (2-5 iterations max). Use a stronger model for critique, cheaper for generation — the reflector is where intelligence is most valuable | Quality-sensitive output | 2-5x generation cost |
| **Hybrid** | Plan-and-execute outer loop; ReAct executors; reflection where quality matters | Production systems with mixed requirements | Variable, well-controlled |

The hybrid pattern is recommended for production because it lets you apply the right pattern at the right granularity — plan the overall work cheaply, execute steps adaptively, and reflect only where output quality justifies the cost.

For simple single-step queries, bypass planning entirely and respond directly.

## Step 5: Select a framework (or don't)

Match the framework to the actual requirements, not to hype.

| Framework | Choose when |
|-----------|------------|
| **No framework** | Task is <50 lines of Python; single LLM call with retrieval; still in problem discovery phase |
| **LangGraph** | Durable execution needed; explicit state management; human-in-the-loop with state inspection; production observability; already in LangChain ecosystem. LangGraph 1.0 (Oct 2025) is the first stable release and default runtime for all LangChain agents. Used by Klarna, Replit, Elastic |
| **CrewAI** | Workflow maps to human team metaphors; fast prototyping; team thinks in roles/tasks not graphs. Not ideal for: complex state management, precise execution order control, or production observability |
| **AutoGen / AG2** | Fundamentally conversational — agents debating or negotiating; multi-agent group chat; need visual interface (AutoGen Studio). AG2 offers declarative JSON serialisation of agent configs |
| **PydanticAI** | Type-safe validated outputs are the primary requirement (finance, healthcare, compliance); tight Pydantic integration already in stack |
| **OpenAI Agents SDK** | Committed to OpenAI ecosystem; want simplest path to multi-agent with built-in tracing/guardrails; provider flexibility across 100+ LLMs. Production-ready but advanced capabilities couple tightly to OpenAI's platform |

Anthropic's advice: "If you do use a framework, ensure you understand the underlying code — incorrect assumptions about what's under the hood are a common source of error."

Skills written to the AgentSkills.io standard are framework-agnostic — they work unchanged across LangGraph, CrewAI, AutoGen, or plain Python. This is one of the strongest arguments for investing in the SKILL.md standard early.

## Step 6: Complexity check

Before finalising, apply the simplicity test:

1. **Could a single LLM call with good retrieval handle this?** If yes, do that. No framework, no agents.
2. **Could the simplest workflow pattern (prompt chaining) handle this?** If yes, don't use orchestrator-workers or agents.
3. **Does the multi-agent topology actually earn its 3-15x token cost?** If you can't articulate the concrete capability gain, simplify.
4. **Are you adding a framework because the task requires it, or because it feels more "serious"?** Frameworks add indirection. They should solve a real problem (state persistence, interrupts, durable execution).

It's always cheaper and more reliable to start simple and add complexity when you hit a wall than to start complex and try to debug your way to reliability.

## Step 7: Present the ADR

Present the decisions as a clean Architecture Decision Record. Each decision gets a short section with the conclusion, the reasoning, and what was ruled out. Close with a consequences section — what this architecture makes easy and what it makes hard.

```
# Architecture Decision Record: [System Name]

## Context
[1-2 sentences: what the system does and the key constraints]

## Decision: Workflow vs Agent
[Conclusion + reasoning]

## Decision: Pattern / Topology
[Conclusion + reasoning + what was ruled out]

## Decision: Reasoning Pattern
[Conclusion + reasoning]

## Decision: Framework
[Conclusion + reasoning + what was ruled out]

## Complexity Assessment
[What was considered and rejected as unnecessary]

## Consequences
[What this makes easy; what this makes hard; known risks]
```

Ask the user if the decisions look right before considering this complete.

**Supporting reference docs** (load if needed for deeper detail on a specific decision):
- `references/decision-workflows-vs-agents.md` — detailed workflow vs agent criteria
- `references/decision-multi-agent-topology.md` — topology comparison with token overhead
- `references/decision-framework-selection.md` — framework comparison with limitations
