# Decision Table: Workflows vs. Agents

Quick-reference for choosing between workflows and agents, based on Anthropic's definitions and guidance.

---

## Definitions

| Term | Definition |
|------|-----------|
| **Workflow** | Systems where LLMs and tools are orchestrated through **predefined code paths**. Control flow is deterministic; the LLM fills in content within a fixed structure. |
| **Agent** | Systems where the LLM **dynamically directs its own processes and tool usage**, maintaining control over how it accomplishes tasks. The path is not known at compile time. |

This is not a spectrum -- it is a genuine architectural fork with different tradeoffs.

---

## When to Use Each

| Use a **Workflow** when | Use an **Agent** when |
|-------------------------|----------------------|
| The task has predictable, well-defined steps | The number of steps cannot be predicted in advance |
| You need consistency and auditability across many executions | The task requires adapting to environmental feedback mid-execution |
| Failure modes are well understood | You need the model to make genuine decisions about what to try next |
| The task can be broken into fixed stages (classify -> retrieve -> generate -> validate) | The problem space is open-ended enough that hardcoding a path would miss most of it |

---

## The Junior Dev Flowchart Test

> If a junior developer can write a flowchart for the task in advance, you need a **workflow**. If they can't because the right path depends on what the environment returns at each step, you need an **agent**.

---

## The Key Tradeoff

Agents trade **latency and cost** for **flexibility**. Every step requires an LLM call. Errors can compound -- a wrong tool selection in step 2 corrupts the context for steps 3 through 10. Agents require sandboxed testing and guardrails that workflows do not.

Anthropic's guidance: "We recommend finding the simplest solution possible and only increasing complexity when needed. This might mean not building agentic systems at all." A single well-prompted LLM call with retrieval is often enough for the majority of real-world tasks.

---

## Anthropic's Five Workflow Building Blocks

In order of complexity. All five can be expressed in LangGraph, but several can also be implemented in a few lines of Python without any framework.

| # | Pattern | Description | Use When |
|---|---------|-------------|----------|
| 1 | **Prompt Chaining** | Break a task into sequential LLM calls, with each step's output feeding the next. | Each step is too long or complex for one call, or you want verification gates between steps. |
| 2 | **Routing** | Classify the input and route it to the appropriate specialised workflow. | Tasks are clearly distinct (customer support routing, intent classification). |
| 3 | **Parallelisation** | Run independent tasks simultaneously, then aggregate. Two variants: **sectioning** (different LLMs handle independent subtasks) and **voting** (same task run multiple times to reduce variance on high-stakes decisions). | Independent subtasks exist, or you need variance reduction on high-stakes decisions. |
| 4 | **Orchestrator-Workers** | A central LLM dynamically decomposes the task and delegates. Unlike fixed parallelisation, the orchestrator decides at runtime how to split. | The decomposition is not knowable in advance. |
| 5 | **Evaluator-Optimizer** | One LLM generates, another evaluates and provides feedback in a loop. | Quality can be judged iteratively and you have clear criteria for "good enough." |

---

## Decision Checklist

1. Start with the simplest structure that handles your known failure modes.
2. Add framework primitives only when you encounter a problem that requires them.
3. Most production AI today is workflows dressed up as agents.
