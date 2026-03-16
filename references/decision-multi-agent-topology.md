# Decision Table: Multi-Agent Topology and Reasoning Patterns

Quick-reference for selecting the right multi-agent topology and reasoning pattern.

---

## Multi-Agent Topology Selection

| Pattern | Use When | Token Overhead | Control Level |
|---------|----------|---------------|--------------|
| **Single agent + tools** | Task fits in one context; <5 steps | 1x | Highest |
| **Orchestrator-worker** | Dynamic decomposition; parallel subtasks | 3-5x | High |
| **Supervisor** | Fixed specialist domains; quality control needed | 3-5x | Highest |
| **Swarm (handoffs)** | Exploratory; agents decide scope autonomously | 3-5x | Lowest |
| **Hierarchical teams** | Multiple distinct domains with internal coordination | 10-15x | Medium |

### The 15x Token Cost Warning

> Multi-agent systems use roughly **15x more tokens than single-agent**. The capability gain must justify this cost. Do not use multi-agent for tasks a well-prompted single agent can handle.

---

## Reasoning Pattern Selection

| Pattern | Description | Best For |
|---------|-------------|----------|
| **ReAct** | Alternate thought-action-observation. LLM call per step. Adaptive but sequential and expensive. | Simple tasks (<5 steps) with unpredictable branching. |
| **Plan-and-execute** | Generate a full plan with a frontier model; execute steps with a cheaper model; replan if execution diverges. Parallelisable. | Complex multi-step tasks where cost profile matters. |
| **Reflection** | Generate-critique-revise loop. 2-5 iteration max. Use stronger model for critique, cheaper for generation. | Quality-sensitive output (code generation, long-form writing, structured data extraction). |
| **Hybrid** (recommended for production) | Plan-and-execute as outer loop; ReAct agents as step executors; reflection within each step for quality-sensitive output; replanning node triggered by execution divergence. Bypass planning for simple single-step queries. | Production systems requiring both quality and cost efficiency. |

---

## Decision Flow

1. **Start with a single agent + tools.** Only escalate to multi-agent when a single context cannot hold the task.
2. **Choose the reasoning pattern** based on task complexity: ReAct for simple, plan-and-execute for complex, reflection for quality-sensitive, hybrid for production.
3. **Choose the topology** based on coordination needs: supervisor for control, orchestrator-worker for parallelism, swarm for exploration.
4. **Validate the token cost** is justified by the capability gain.
