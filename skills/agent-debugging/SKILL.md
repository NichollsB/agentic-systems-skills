---
name: agent-debugging
description: Diagnose and fix agent failures using the MAST taxonomy, symptom-to-cause mapping, LangGraph time-travel debugging, binary search isolation, and non-determinism handling. Use this skill when the user has an agent producing wrong outputs, silent failures, intermittent bugs, performance degradation, runaway loops, or any unexpected behaviour. Also use when the user says things like "my agent is broken", "it gives wrong answers sometimes", "the agent loops forever", "quality dropped after a change", "how do I debug this agent", "my agent calls the wrong tool", or is investigating any agent failure — whether single-agent or multi-agent.
---

# Agent Debugging

Agent debugging is fundamentally different from traditional software debugging. Most agent failures do not trigger visible errors — the system returns a successful status code while producing the wrong result. The agent selects the wrong tool, passes malformed parameters, misinterprets output, or reasons incorrectly about state, and none of this surfaces as an exception.

This silent failure mode, combined with non-determinism, means you cannot rely on stack traces. You must rely on traces.

## Step 1: Classify the symptom

Before reading any trace, match the observable symptom to narrow the search:

| Symptom | Likely category | Where to look first |
|---------|----------------|---------------------|
| Agent declares task complete when it isn't | Verification/termination | Done condition, validation node, feature list |
| Agent repeats work already completed | Memory / harness | Progress artifacts, context compaction, session state |
| Agent calls the wrong tool | Action / specification | Tool descriptions, schema overlap, tool selection traces |
| Tool called with wrong parameters | Action | Tool input examples, strict mode, parameter descriptions |
| Agent contradicts itself across turns | Memory / context rot | Context length, observation masking, compaction quality |
| Agent ignores a prior agent's output | Inter-agent (FM-2.5) | Handoff context transfer, A2A message structure |
| Agent proceeds on wrong assumption | Inter-agent (FM-2.2) | Clarification instructions, ambiguity handling |
| Good individual steps, bad overall outcome | Specification / planning | Task decomposition, orchestrator instructions, goal framing |
| Quality degrades as session grows | Context rot / memory | Token count per turn, compaction threshold |
| High variance (works sometimes, fails others) | Non-determinism | Temperature, run k=5, inspect divergent traces |
| Cost spike without obvious cause | Loop / redundant calls | Span counts, node visit frequency, loop guards |

## Step 2: Apply the failure taxonomy

### Multi-agent failures (MAST taxonomy, NeurIPS 2025)

Three categories from analysis of 1,600+ annotated traces:

**Category 1 — Specification and system design**: Agent behaviour is consistent but wrong. The agent does what its design tells it to, just not what you intended. Includes: underspecified roles, missing instructions, poor task decomposition, ambiguous termination. Fix is in design, not prompts.

**Category 2 — Inter-agent misalignment**: Breakdown in information flow between agents. Key sub-modes:
- Mismatch between reasoning and action (13.2%) — agent's plan doesn't match what it does
- Task derailment (7.4%) — conversation drifts from original goal
- Proceeding with wrong assumptions (6.8%) — moves forward on ambiguity instead of clarifying

Critical MAST finding: "improvements in base model capabilities will be insufficient to address these failures." Better models don't fix coordination problems — better system design does.

**Category 3 — Verification and termination**: Agents that complete prematurely, mark tasks done without verification, can't detect own errors, or loop indefinitely.

### Single-agent failures (AgentErrorTaxonomy)

Four operational modules to attribute failures:

| Module | Symptom | Fix approach |
|--------|---------|-------------|
| **Memory** | Acts as if it doesn't know something it was told | Improve context management or retrieval |
| **Reflection** | Accepts incorrect output as valid | Improve validation, add quality gates |
| **Planning** | Wrong strategy, bad decomposition | Improve orchestrator reasoning or prompts |
| **Action** | Tool misuse, wrong parameters | Improve tool schemas, descriptions, examples |

## Step 3: Locate and read the trace

**In Langfuse**: Filter by `session_id`, `user_id`, or `trace_id`. Use the timeline view — red spans (>75% latency) are the starting point for performance failures. Check node visit counts in the Agent Graphs view for loop failures.

**Read the execution transcript, not just the final output.** Look at tool call arguments — not just whether the tool was called, but what parameters it received and what it returned. Common causes of unproductive steps: instructions too vague, instructions that don't apply to the task, too many options without a clear default.

## Step 4: Use LangGraph time-travel to reproduce

Three operations on any checkpointed run:

### Inspect state history

```python
config = {"configurable": {"thread_id": "session-abc"}}
history = list(graph.get_state_history(config))

for snapshot in history:
    print(f"node={snapshot.next}, checkpoint={snapshot.config['configurable']['checkpoint_id']}")
    print(f"state keys: {list(snapshot.values.keys())}")
```

### Replay from a checkpoint

Re-execute from a specific prior state without re-running earlier nodes:

```python
before_validation = next(s for s in history if s.next == ("validate_node",))
result = graph.invoke(None, before_validation.config)
```

Use replay to confirm a hypothesis: "I think the failure happened in validate_node." Replay from just before and observe.

### Fork with modified state

Inject corrected state and re-execute forward — the fix-and-test loop:

```python
fork_config = graph.update_state(
    before_validation.config,
    {"confidence_score": 0.0, "validation_errors": ["missing summary"]},
    as_node="validate_node"
)
result = graph.invoke(None, fork_config)
```

Specify `as_node` when: forking from a parallel branch, skipping nodes, or setting initial state for testing.

### Binary search for long traces

For long traces where the failure point isn't obvious:

1. Identify the failing terminal state
2. Find the checkpoint at the midpoint
3. Inspect: is state already corrupted or still consistent?
4. If corrupted, recurse into the first half; if consistent, the second half
5. Two or three bisections typically isolate to 3-5 nodes

## Step 5: Debug non-determinism

LLMs are probabilistic — the same input may succeed on one run and fail on another.

- Run the same input **k=5 times** and measure pass rate
- **100% or 0%**: deterministic failure — routing bug, tool schema bug, state mutation bug. Investigate statically.
- **30-80%**: stochastic failure — system is at the boundary of model capability. Fix is structural (better instructions, clearer tool descriptions, validation loop) not prompt tweaking.
- Use **pass@k > 0.8** as a reasonable production bar (pass@3 meaning 3 runs, >80% succeed)

## Step 6: Close the loop

Every production failure that takes more than 15 minutes to diagnose gets converted to a Langfuse dataset item before it is closed:

```python
langfuse.create_dataset_item(
    dataset_name="agent-regression",
    input=failing_trace_input,
    expected_output=correct_output,
    source_trace_id=failing_trace_id
)
```

This builds a regression suite that catches the same failure class before it reaches users. The evaluation flywheel (see `langfuse-integration`) is the mechanism; the discipline to close the loop is what makes it compound.

## Step 7: Present the diagnosis

Output:

1. **Symptom classification** — which symptom, which likely category
2. **Taxonomy attribution** — MAST category or AgentErrorTaxonomy module
3. **Root cause** — what specifically went wrong, with trace evidence
4. **Fix** — what to change (design, prompt, tool schema, state, guard)
5. **Regression test** — the dataset item that prevents recurrence

**Supporting reference docs** (load if needed during diagnosis):
- `references/ref-mast-taxonomy.md` — full 14 failure modes with observable symptoms for quick lookup
