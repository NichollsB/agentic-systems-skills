---
name: langfuse-integration
description: Set up Langfuse observability for LangGraph agents — CallbackHandler integration, custom spans, TTFT tracking, sampling, the evaluation flywheel, datasets, experiments, prompt version management, cost tracking, and spend alerts. Use this skill when the user needs to add observability to their agent, trace LangGraph nodes and LLM calls, diagnose performance bottlenecks, set up LLM-as-a-Judge evaluators, build evaluation datasets from production failures, manage prompt versions, track costs, or configure spend alerts. Also use when the user says things like "add Langfuse to my agent", "I need observability", "how do I trace my LangGraph", "set up evaluations", "track my agent costs", "my agent is slow and I don't know why", or is moving an agent toward production and needs monitoring.
---

# Langfuse Integration

Langfuse provides the full observability flywheel for agentic systems: trace production behaviour -> analyse errors -> build datasets -> run experiments -> deploy improvements -> trace again.

This skill covers LangGraph-specific integration patterns. For general Langfuse API and CLI usage, see the community `langfuse` skill.

## Step 1: Understand the observability requirements

Before configuring, get clear on what's needed:

- Is this initial setup or adding to an existing integration?
- What needs tracing? (LLM calls, tool calls, custom operations, external APIs)
- Is this dev/staging or production? (sampling matters at scale)
- Do you need evaluations? (LLM-as-Judge, human annotation, programmatic)
- Do you need cost tracking and spend alerts?

## Step 2: Set up the LangGraph integration

### Basic integration

The `CallbackHandler` auto-traces all LangGraph nodes, LLM calls, and tool calls:

```python
from langfuse.langchain import CallbackHandler

langfuse_handler = CallbackHandler()
result = compiled_graph.invoke(
    input={"messages": [HumanMessage(content="...")]},
    config={
        "callbacks": [langfuse_handler],
        "metadata": {
            "langfuse_session_id": session_id,
            "langfuse_user_id": user_id,
            "langfuse_version": skill_version
        }
    }
)
```

This automatically captures: node executions as spans, LLM calls as generation observations (model, tokens, cost, latency), tool calls with arguments and return values, and routing decisions.

### Custom spans for non-LangChain operations

```python
from langfuse import get_client
langfuse = get_client()

with langfuse.start_as_current_observation(as_type="span", name="database_query") as span:
    result = db.query(sql)
    span.update(metadata={"rows_returned": len(result)})
```

### TTFT (Time to First Token) tracking

```python
with langfuse.start_as_current_observation(as_type="generation") as generation:
    first_token_time = None
    for chunk in llm.stream(messages):
        if first_token_time is None:
            generation.update(completion_start_time=datetime.now())
        yield chunk
```

### Sampling for production

Avoid instrumenting every trace at full volume:

```python
langfuse = Langfuse(sample_rate=0.2)  # instrument 20% of traces
```

SDK overhead is approximately 0.1ms per decorated function using background batching every ~2 seconds.

## Step 3: Understand the data model

| Level | What it represents | Key attributes |
|-------|-------------------|----------------|
| **Observation** | Individual step (LLM call, tool call, span) | Model, tokens, cost, latency, nested hierarchy |
| **Trace** | One complete agent invocation, start to finish | `user_id`, `session_id`, `tags`, `metadata`, `version` |
| **Session** | Multi-turn conversation (group of traces) | Session cost, turns to resolution, abandonment |
| **Score** | Evaluation result attached to trace or observation | From LLM-as-Judge, human annotation, user feedback, or programmatic |

## Step 4: Diagnose performance bottlenecks

### Trace timeline view

Colour-coded Gantt chart:
- **Red**: span consuming >=75% of total trace latency — primary bottleneck
- **Yellow**: span consuming 50-75% of total trace latency

### Agent Graphs view

Automatically infers and visualises agentic workflow structure from observation timings. Shows execution across agent frameworks.

### Common bottleneck patterns

| Pattern | Diagnosis | Where to look |
|---------|-----------|--------------|
| LLM calls dominating latency | Compare models in generations table, filter by model | Generations tab |
| Slow external API calls | Add custom spans, measure against SLOs | Custom spans |
| Sequential operations that could be parallelised | Long chains of same-depth spans | Timeline view |
| Excessive reflection loops | High node visit counts | Agent Graphs view |
| Context rot | Traces getting progressively slower in a session | Session view, token counts |

## Step 5: Set up evaluations

Three evaluation contexts, each for a different purpose:

### Observation-level (individual operations)

Evaluate specific LLM calls, retrieval ops, or tool calls in isolation. Dramatically faster execution — evaluations complete in seconds. Best for compositional evaluation: run toxicity on outputs, relevance on retrievals, accuracy on generations simultaneously.

### Trace-level (complete workflows)

Evaluate entire workflow executions. Use for: task completion scoring, multi-step response quality, tool sequence correctness.

### Experiment-level (controlled datasets)

Run evaluators on dataset items to compare model versions, prompt variations, or tool configurations reproducibly. Each experiment run generates traces that are automatically scored.

**Production pattern**: experiments during development to validate changes; observation-level evaluators in production for scalable real-time monitoring.

## Step 6: Build the evaluation flywheel

The highest-value workflow:

1. Monitor production traces in Langfuse
2. Flag traces where scores indicate poor performance
3. Add those traces to a dataset as test cases (with expected outputs from domain experts)
4. Run experiments on the dataset when making changes
5. Deploy changes only when experiment scores exceed production baseline
6. Monitor that the improvement holds in production

```python
from langfuse import Langfuse
langfuse = Langfuse()

# Create dataset from production failures — the highest-value source
langfuse.create_dataset(name="agent-regression-2025")

langfuse.create_dataset_item(
    dataset_name="agent-regression-2025",
    input={"query": "Schedule a meeting with Alice and Bob"},
    expected_output={"action": "create_calendar_event", "participants": ["alice", "bob"]},
    source_trace_id="<trace_id>",
    source_observation_id="<obs_id>"
)
```

Synthetic dataset generation: use LLMs to generate diverse test inputs including adversarial cases, amplifying coverage before production traffic exists.

## Step 7: Configure cost tracking and spend alerts

Langfuse automatically aggregates costs from all nested generation observations.

**Spend alerts**: configure for cost per trace, per session, or total daily cost exceeding thresholds. This defends against runaway loops — a single loop can generate hundreds of dollars in minutes. Set alerts conservatively: if a normal task costs $0.50, alert at $5.00 (10x).

**Version tracking**: pass skill/prompt versions in trace metadata for A/B impact measurement:

```python
config={
    "metadata": {
        "langfuse_version": "research-skill-v1.2",
        "langfuse_tags": ["skill:research", "env:production"]
    }
}
```

**Prompt Management**: create and version prompts via UI/SDK, deploy via labels (`production`, `staging`, `canary`), compare metrics across versions, no code changes to update deployed prompts.

## Step 8: Present the integration

Output:

1. **Integration setup** — CallbackHandler wiring, metadata configuration
2. **Custom spans** (if needed) — for non-LangChain operations
3. **Sampling configuration** (if production) — sample rate appropriate to volume
4. **Evaluation strategy** — which evaluation contexts apply, what evaluators to run
5. **Dataset plan** — how to bootstrap the evaluation flywheel
6. **Cost monitoring** — spend alert thresholds, version tracking metadata
