---
name: deployment-and-versioning
description: Plan deployment, versioning, and change management for agentic systems — the four change vectors, three-environment strategy, rollback procedures, and statistical quality monitoring. Use this skill when the user needs to deploy an agent to production, plan how to version and roll back changes, set up environments (dev/staging/prod), monitor for silent regressions, handle model version updates, or manage the unique challenge that agent behaviour depends on code AND models AND prompts AND tools changing independently. Also use when the user says things like "how do I deploy this agent", "how do I roll back a bad model change", "my agent got worse after a prompt update", "how do I version my agent", or is moving an agentic system from development to production.
---

# Deployment and Versioning

Agentic systems differ from traditional software in one critical way: the agent's behaviour is determined by the combination of code, model versions, skill/prompt versions, and tool configurations — all of which can change independently and all of which affect quality. A regression in any one of them can silently degrade the agent without any code change.

This skill produces a versioning and rollback plan for the agent system.

## Step 1: Identify the change vectors

Four things change an agent's behaviour. Map which ones apply to this system:

| Change vector | What changes | How to track | How to validate |
|--------------|-------------|-------------|----------------|
| **Code** | Graph structure, node logic, routing functions, tool implementations | Git | Unit + integration tests |
| **Model versions** | Provider releases new model, behaviour shifts with identical prompts | Model string in LiteLLM config | Regression evals on eval dataset before updating |
| **Skill/prompt versions** | SKILL.md files, system prompts | Git + Langfuse metadata (`langfuse_version`) | Dataset experiments in Langfuse before deploying |
| **Tool configurations** | Tool schemas, descriptions, API backends | Git or config management | Tool-calling accuracy check against golden inputs |

The key insight: a "code freeze" does not freeze agent behaviour. A model provider can release an update that changes your agent's output without any change on your side.

## Step 2: Design the environment strategy

Three environments, each with appropriate infrastructure:

| Environment | Checkpointer | Models | Observability | Purpose |
|-------------|-------------|--------|--------------|---------|
| **Development** | `MemorySaver` | Mock LLMs or direct API | None or local logging | Fast iteration |
| **Staging** | `SqliteSaver` or staging Postgres | Real models via LiteLLM | Langfuse staging project, full tracing | Validate before production |
| **Production** | `PostgresSaver` | Full LiteLLM with Redis | Langfuse production project, spend alerts active | Live traffic |

Environment-specific configuration should be a single config file. Nothing about which model, checkpointer, or Langfuse project should be hardcoded in nodes or tools.

The staging gate: run the full eval suite on staging before promoting to production. This catches regressions from all four change vectors.

## Step 3: Plan rollback procedures

The ability to roll back quickly is more important than the ability to deploy quickly. Each change vector has its own rollback mechanism:

**Skill/prompt rollback** — Skills are files in git. `git revert` is immediately effective because skills are loaded at runtime, not compiled. No redeployment needed.

**Prompt rollback (Langfuse)** — If prompts are managed in Langfuse Prompt Management, repoint the `production` label to a previous version instantly. No code change required.

**Model rollback** — LiteLLM config is a YAML file. Reverting a model version is a config change, not a code deployment.

**State migration** — The hardest rollback. If you change the `AgentState` TypedDict schema, existing checkpointed state may be incompatible:
- Adding `total=False` fields is safe — existing state simply lacks them
- Removing or renaming fields requires migration logic
- Plan schema migrations carefully and test against existing checkpoints before deploying

## Step 4: Design monitoring for silent regressions

Agent behaviour is probabilistic. Regressions are often statistical, not binary. A prompt change might reduce task completion from 87% to 79% — visible only if you're tracking systematically.

**Two alerts from day one:**
1. **Quality score alert** — LLM-as-a-Judge evaluators running continuously on production traces, with alerts when scores drop below threshold
2. **Spend alert** — cost per task or daily spend exceeding expected bounds

These are the two failure modes most likely to go unnoticed without automated monitoring: quality degradation and cost spikes.

The mechanism: the Langfuse evaluation flywheel (trace -> error analysis -> datasets -> experiments -> deploy -> trace). For implementation details, see the `langfuse-integration` skill.

**Breaking vs non-breaking changes:**
- **Non-breaking**: adding a new node, adding a new tool, adding a `total=False` state field, changing a prompt
- **Breaking**: removing a state field, renaming a tool, changing a tool's schema, removing a node that other routing depends on

Non-breaking changes can be deployed with monitoring. Breaking changes require migration planning and coordinated rollout.

## Step 5: Present the versioning plan

Output:

1. **Change vector inventory** — which of the four vectors apply, how each is tracked and validated
2. **Environment strategy** — what infrastructure at each stage, what the staging gate checks
3. **Rollback procedures** — for each change vector, how to revert and how fast
4. **Monitoring setup** — quality and spend alerts, what thresholds trigger investigation
5. **Breaking change process** — how breaking changes are identified, migrated, and rolled out
