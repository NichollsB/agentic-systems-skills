---
name: model-selection
description: Select and assign LLM models to agent roles using evaluation-driven methodology. Use this skill when the user needs to decide which models to use for different agent roles (orchestrator, worker, validator, reflector), evaluate models using the CLASSic framework, design a three-tier routing strategy, choose agentic benchmarks, or create a model assignment table. Also use when the user says things like "which model should I use", "how do I pick models for my agent", "should I use Opus or Sonnet for this", "how do I evaluate models for agents", or is assigning models to roles in a multi-model system.
---

# Model Selection

The dominant production pattern is **heterogeneous model routing** — different models for different roles. The core principle: start with your most capable model everywhere to establish a quality ceiling, then systematically downgrade roles where a cheaper model maintains acceptable quality. Never optimise costs before you have a working quality baseline.

This skill produces a model assignment table for the agent system being designed.

## Step 1: Identify the agent roles

Map every distinct role in the system. Either extract from existing architecture decisions or ask the user. Common roles:

| Role | What it does | Key requirement |
|------|-------------|-----------------|
| Orchestrator / Planner | Task decomposition, planning, coordination | Complex reasoning |
| Tool calling / Execution | Running tools, structured output | Reliable function calling |
| Reflection / Critique | Quality assessment, error detection | Nuanced judgment |
| Classification / Routing | Input categorisation, intent detection | Sub-second latency |
| Summarisation / Extraction | Condensing content, pulling data | High throughput |
| Validation / Grading | Pass/fail checks, scoring | Structural accuracy |
| Deep reasoning | Proofs, complex analysis | Extended thinking |

Not every system has all roles. A simple agent might have just one. Identify only the roles that exist.

## Step 2: Assign model tiers

Three tiers, matched to role requirements:

| Tier | Models | Assign to |
|------|--------|-----------|
| **Tier 1 (fast/cheap)** | Haiku 4.5, GPT-4o-mini | Routing, classification, validation, summaries |
| **Tier 2 (mid-range)** | Sonnet 4.5, GPT-4.1 | Standard tasks, tool calling, execution, reflection |
| **Tier 3 (frontier)** | Opus 4.6, o3 | Complex reasoning, planning, high-stakes decisions |

Key routing patterns:
- **Cheaper model for generation, stronger model for critique** — the highest-leverage model routing pattern. The reflector is where intelligence is most valuable; the generator can be fast and cheap.
- **Frontier models when**: reasoning requires more than three hops, task involves novel tool combinations, agent is planning a multi-agent workflow, or the decision is irreversible.
- **Smaller models everywhere else.**
- **Cross-provider fallback chains** for resilience: `claude-sonnet -> gpt-4.1 -> gpt-4o`.

Research from RouteLLM: routing 90% of traffic to small models yields ~86% cost savings. The operative metric is **cost-normalised accuracy** (CNA = accuracy / cost_per_task), not raw accuracy.

## Step 3: Evaluate with the CLASSic framework

The CLASSic framework (Aisera, ICLR 2025) assesses five dimensions for model selection:

- **C**ost — API usage, token consumption, infrastructure overhead
- **L**atency — end-to-end response times under realistic load
- **A**ccuracy — correctness in tool selection and execution
- **S**tability — consistency across diverse inputs (catches models with good averages but high variance)
- **S**ecurity — resilience against adversarial inputs and prompt injection

A model that scores highest on accuracy but lowest on stability is often the wrong choice for production. You need both.

## Step 4: Select benchmarks

Standard static benchmarks (MMLU, HELM) do not measure what agents do. Use agentic benchmarks:

| Benchmark | What it measures | Use for |
|-----------|-----------------|---------|
| **BFCL** (Berkeley Function-Calling) | Tool calling across thousands of APIs | Selecting models for tool-use roles |
| **SWE-bench Verified** | Real-world software engineering | Models that modify codebases |
| **AgentBench** | Multi-environment agent tasks | General agent capability |
| **tau-bench** | Retail/airline booking with pass@k | Consistency evaluation |

The **pass@k metric** is crucial: run the same task k times and measure what fraction succeed. A model with 80% average accuracy but high variance (60% of runs fail) is worse for production than 70% accuracy with near-zero variance.

**Infrastructure affects benchmarks**: Anthropic found that "infrastructure configuration can swing agentic coding benchmarks by several percentage points — sometimes more than the leaderboard gap between top models." Test in production-representative conditions.

## Step 5: Design the update process

Models change faster than code. The assignment table needs a framework for updates, not just current model names:

- When a provider releases a new model, run regression evals on your eval dataset before updating
- Use the CLASSic framework to compare old vs new on all five dimensions
- Keep the model assignment in config (via LiteLLM or a model factory), not in code
- Track model versions in observability (Langfuse metadata) so you can correlate quality changes with model updates

For LiteLLM configuration to implement the routing, see the `litellm-configuration` skill.

## Step 6: Present the model assignment table

Output:

1. **Role-to-tier mapping** — each role with its assigned tier and rationale
2. **Specific model assignments** — current recommended models per role (noting these will change)
3. **Fallback chains** — cross-provider fallbacks for each critical role
4. **Evaluation plan** — which CLASSic dimensions matter most for this system, which benchmarks to use
5. **Cost estimate** — rough per-task cost at the assigned tiers

**Supporting reference docs** (load if needed):
- `references/ref-prompt-caching.md` — cache mechanics for cost estimation (Anthropic vs OpenAI)
- `addendums/token-optimisation-anthropic.md` — provider-specific token efficiency techniques (Batch API, output length control, LLMLingua)
