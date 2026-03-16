---
name: reflection-and-validation
description: Design self-validation, reflection, and self-correction patterns for agentic AI systems. Use this skill when the user needs to add quality loops to an agent, implement generate-critique-revise cycles, design validation nodes, build corrective RAG pipelines, add hallucination detection, structure plan-validate-execute workflows, choose between reflection architectures (basic, reflexion, LATS), decide where to place validation gates in a graph, or improve agent output quality through iterative refinement. Also use when the user says things like "how do I make my agent check its own work", "add self-correction", "validate before executing", "detect hallucinations", "my agent output quality is inconsistent", "add a review loop", or is building any agent where output correctness matters and can be assessed programmatically or by the LLM itself.
---

# Reflection and Validation

Self-correction is the single most powerful technique for elevating agent output quality. Reflection takes extra LLM calls but produces significantly higher quality outputs -- particularly for code generation, long-form writing, and structured data extraction where quality can be assessed programmatically or by the LLM itself.

This skill designs a validation strategy for an agentic system: which reflection architecture to use, where validation gates belong, and how to balance quality against compute cost.

Use the steps below to reason through the design, but present the output as a validation strategy with implementation guidance -- not a log of the thinking process.

## Step 1: Assess the task and quality requirements

Before choosing a reflection pattern, understand what quality means for this task. Either ask the user or extract from context:

- What does the agent produce? (code, text, structured data, decisions, plans)
- Can output quality be assessed programmatically? (schema validation, test execution, type checking)
- Can quality be assessed by an LLM? (coherence, relevance, factual accuracy)
- What are the stakes of a bad output? (user annoyance vs financial loss vs safety)
- Is there external ground truth to validate against? (databases, APIs, documents)
- What is the compute budget? (latency tolerance, cost sensitivity)

## Step 2: Choose the reflection architecture

Three architectures, in order of cost and power. Choose the cheapest one that meets quality requirements.

### Basic reflection (generate-critique-revise)

The simplest and most broadly applicable. A generator produces output; a reflector prompt critiques it; the generator revises based on the critique. Use this as the default when LLM-assessable quality improvement is needed.

Key design rules:
- 2-5 iteration max with a mandatory loop guard (never unbounded)
- Use a stronger model for critique and a cheaper model for initial generation -- the reflector is where intelligence is most valuable
- The critique prompt must be specific: what dimensions to evaluate, what "good enough" looks like
- Exit when quality passes OR max reflections reached (whichever comes first)

```
graph: generate -> grade -> [route_reflection]
    -> reflect -> generate (loop)
    -> finalise (exit when quality passes or MAX_REFLECTIONS reached)
```

When to use: code generation, long-form writing, structured data extraction, any task where the LLM can meaningfully critique its own output.

When NOT to use: tasks where the LLM cannot assess quality (factual claims without ground truth), tasks where latency is critical, simple classification tasks.

### Reflexion (reflection with external grounding)

Extends basic reflection by grounding the critique in external data -- tool observations, search results, retrieved facts. The actor explicitly enumerates what it got wrong, uses tools to verify claims, and provides citations.

```
graph: draft -> execute_tools -> revise -> [loop check] -> draft (loop) | END
The revisor receives: original query + draft + tool observations + reflection
```

Better than basic reflection for fact-sensitive tasks. The external grounding converts vague critique ("this is inaccurate") into specific corrections ("claim X is false -- search result Y says Z").

When to use: research tasks, fact-checking, any output that makes verifiable claims.

### LATS (Language Agent Tree Search)

The most powerful and expensive. Generates multiple candidate responses, evaluates each with a reward function (UCT score = value/visits + exploration bonus), uses MCTS-style search to select the best path. Saves the best trajectory to external memory.

When to use: high-stakes decisions where compute budget permits. 10-50x more expensive than basic reflection. Reserve for cases where the cost of a wrong answer far exceeds the cost of compute.

### Decision guide

| Task type | Stakes | Ground truth available? | Pattern |
|-----------|--------|------------------------|---------|
| Code generation | Medium | Yes (tests, type checks) | Basic reflection with programmatic grading |
| Long-form writing | Low-medium | No | Basic reflection with LLM grading |
| Research / fact claims | Medium-high | Yes (search, databases) | Reflexion |
| RAG output | Medium | Yes (source documents) | Corrective RAG (see Step 3) |
| Complex planning | High | Partial | Plan-validate-execute (see Step 4) |
| Critical decisions | Very high | Variable | LATS |
| Simple classification | Low | Sometimes | No reflection needed |

## Step 3: Design validation nodes

Validation nodes are first-class graph citizens. A dedicated validate_node runs programmatic checks before LLM-based quality checks. This separation is critical:

- Programmatic checks are instant and free
- LLM checks are expensive and slow
- Never combine both in the generator node

### Validation node structure

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

Design principles:
- Programmatic checks gate LLM checks (fail fast, save cost)
- Track error_count in state for loop guard decisions
- Return confidence_score for routing decisions
- Use a cheaper model for the semantic check than for generation

### Programmatic checks to consider

| Check type | What it validates | Cost |
|-----------|------------------|------|
| Schema validation | Output structure matches expected format | Free |
| Required fields | All mandatory fields present and non-empty | Free |
| Type checking | Values are correct types (dates, numbers, enums) | Free |
| Length bounds | Output within min/max length constraints | Free |
| Code syntax | Generated code parses without errors | Free |
| Test execution | Generated code passes test suite | Cheap (compute) |
| Link validation | URLs resolve, references exist | Cheap (network) |

### LLM-based checks to consider

| Check type | What it validates | When to use |
|-----------|------------------|-------------|
| Coherence | Output is internally consistent | Writing tasks |
| Relevance | Output addresses the original question | All tasks |
| Factual grounding | Claims supported by provided context | RAG, research |
| Completeness | All aspects of the request addressed | Complex tasks |
| Tone/style | Output matches required voice | Customer-facing |

## Step 4: Design the Corrective RAG pattern (if applicable)

For retrieval-augmented flows, add grading nodes that evaluate documents and outputs before proceeding. This is the self-correcting RAG (CRAG) pattern:

```
retrieve -> grade_documents -> [route]
    -> "relevant" -> generate -> grade_output -> [route]
        -> "hallucination_detected" -> transform_query -> retrieve (retry)
        -> "useful" -> END
    -> "irrelevant" -> transform_query -> web_search -> generate
```

Three quality gates:
1. **Grade documents for relevance** before generating -- catches poor retrieval early
2. **Grade output against documents** (hallucination check) -- detects fabricated claims
3. **Grade output against the question** (usefulness check) -- ensures the answer is actually helpful

Each gate prevents errors from compounding through subsequent steps. Without these gates, a bad retrieval produces a confident-sounding but wrong answer.

The hallucination check is the most valuable: compare each claim in the generated output against the source documents. If a claim cannot be traced to a source, flag it.

## Step 5: Design the plan-validate-execute pattern (if applicable)

For complex multi-step tasks, structure the graph around a validation gate between planning and execution:

```
parse_request -> plan -> validate_plan -> [route]
    -> "plan_invalid" -> replan -> validate_plan (loop with guard)
    -> "plan_valid" -> execute_steps (parallel) -> aggregate -> validate_output
        -> "output_invalid" -> reflect -> execute_steps (retry)
        -> "output_valid" -> format -> END
```

The validation node between plan and execution is the most valuable investment -- it catches structural problems before expensive execution happens.

Plan validation checks:
- Does the plan cover all aspects of the request?
- Are the steps in a feasible order?
- Are resource requirements within budget?
- Does the plan avoid known failure modes?

Output validation checks:
- Does the aggregated output satisfy the original request?
- Are there contradictions between outputs of parallel steps?
- Does the output pass programmatic quality checks?

## Step 6: Design loop guards and exit conditions

Every reflection loop MUST have bounded iteration. Unbounded loops are the most common failure mode in self-correcting agents.

```python
MAX_REFLECTIONS = 3  # or 5 for high-stakes tasks

def route_reflection(state: AgentState) -> str:
    if state["confidence_score"] >= QUALITY_THRESHOLD:
        return "finalise"      # quality achieved
    if state["error_count"] >= MAX_REFLECTIONS:
        return "finalise"      # budget exhausted -- return best effort
    return "reflect"           # try again
```

Design rules:
- Set MAX_REFLECTIONS based on task complexity (2-3 for simple, up to 5 for complex)
- Always have two exit paths: quality achieved OR budget exhausted
- When budget is exhausted, return the best attempt so far (do not fail silently)
- Log when loops exhaust their budget -- this signals the reflection prompt needs improvement
- Track iteration count in state, not as a closure variable (so it survives checkpointing)

## Step 7: Configure model selection for reflection

Model assignment within reflection loops matters. The reference architecture:

| Role | Model tier | Rationale |
|------|-----------|-----------|
| Initial generation | Mid-tier (capable, cheaper) | First draft does not need to be perfect |
| Critique / grading | Frontier (strongest available) | Quality of critique determines quality of final output |
| Revision | Mid-tier or frontier | Depends on task complexity |
| Programmatic validation | N/A (no model needed) | Code-based checks |

The critique step is where intelligence is most valuable. A weak critic produces vague feedback that does not improve the next iteration.

For model selection details and the CLASSic framework, see the `model-selection` skill.

## Step 8: Present the validation strategy

Output a validation strategy for the system:

1. **Quality requirements** -- what "good enough" means for this task, measurable criteria
2. **Reflection architecture** -- which pattern (basic, reflexion, LATS, CRAG, plan-validate-execute) and why
3. **Validation nodes** -- programmatic checks (with code), LLM checks (with grading prompts), ordering
4. **Graph integration** -- where validation nodes sit in the graph, routing logic, state fields needed
5. **Loop guards** -- MAX_REFLECTIONS, QUALITY_THRESHOLD, exit behaviour on budget exhaustion
6. **Model assignment** -- which model tier for generation vs critique vs validation
7. **Cost-quality tradeoff** -- estimated additional latency and cost, what quality improvement is expected

### Cross-references

- For graph primitives (state schema, nodes, edges, routing): see `langgraph-fundamentals`
- For tool-level error handling and retry logic: see the community `tool-design` skill
- For output guardrails (PII scanning, policy compliance): see `guardrails-and-security`
- For model selection and cost optimization: see `model-selection`
- For memory persistence of reflection outcomes: see `memory-and-persistence`
