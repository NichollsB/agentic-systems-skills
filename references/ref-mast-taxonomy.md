# Quick-Reference: MAST Failure Taxonomy and Agent Error Diagnosis

For use during debugging. Covers multi-agent failure modes (MAST, NeurIPS 2025), single-agent error attribution (AgentErrorTaxonomy), and symptom-to-cause mapping.

---

## MAST Failure Taxonomy (NeurIPS 2025)

Source: UC Berkeley and collaborators. 1,600+ annotated traces across 7 MAS frameworks. 14 distinct failure modes. Inter-annotator agreement kappa = 0.88.

### Category 1: Specification and System Design Failures

Failures that originate from how the system was designed **before runtime**. The agent's behaviour is consistent but wrong -- it is doing what its design tells it to do, just not what you intended.

| Sub-mode | Description |
|----------|-------------|
| Underspecified agent roles | Agents do not have a clear enough mandate to know what is within or outside their scope |
| Missing or conflicting instructions | Agent instructions contradict each other or omit critical guidance |
| Poor task decomposition | Subtasks assigned that no agent is equipped to handle |
| Ambiguous termination conditions | No clear definition of "done" |

**Fix is in design, not prompts.**

### Category 2: Inter-Agent Misalignment

Failures arising from breakdown in information flow between agents during execution.

| Code | Sub-mode | Frequency | Description |
|------|----------|-----------|-------------|
| FM-2.1 | Unexpected conversation resets | 2.2% | An agent restarts the task as if it has no memory of prior work |
| FM-2.2 | Proceeding with wrong assumptions | 6.8% | An agent moves forward on an ambiguous handoff rather than asking the sender to clarify |
| FM-2.3 | Task derailment | 7.4% | The conversation between agents drifts away from the original goal |
| FM-2.4 | Information withholding | 0.85% | An agent fails to pass critical context to the next agent |
| FM-2.5 | Ignoring other agents' input | 1.9% | An agent proceeds as if it did not receive information that was sent |
| FM-2.6 | Mismatch between reasoning and action | **13.2%** | **Most common.** An agent's stated plan does not match what it actually does |

> **Key MAST finding**: "Improvements in base model capabilities will be insufficient to address Category 2 failures, which demand deeper social reasoning abilities from agents." Better models do not fix coordination failures -- better system design does.

### Category 3: Task Verification and Termination Failures

Agents that complete prematurely, mark tasks done without proper verification, cannot detect their own errors, or loop indefinitely because they lack a clear done condition.

---

## AgentErrorTaxonomy: Single-Agent Failure Attribution

Source: arXiv:2509.25370. For single-agent flows, attributes failures to one of four operational modules.

| Module | Description | Fix Strategy |
|--------|-------------|-------------|
| **Memory errors** | Stale or missing context, incorrect retrieval, inability to track prior steps. Agent acts as if it does not know something it was told. | Improve context management or retrieval. |
| **Reflection errors** | Poor self-evaluation, accepting incorrect output as valid, missing the relevance of error feedback. | Add/improve validation nodes, use stronger model for critique. |
| **Planning errors** | Incorrect task decomposition, choosing the wrong strategy, failing to adapt the plan when execution diverges. | Improve orchestrator reasoning or decomposition prompts. |
| **Action errors** | Tool misuse, incorrect parameter construction, misinterpreting tool outputs. | Improve tool schemas, descriptions, or add input_examples. |

---

## Symptom-to-Cause Diagnosis Map

Start here when an agent produces bad output. Match the observable symptom to narrow the search before reading traces.

| Symptom | Likely Category | Where to Look First |
|---------|-----------------|---------------------|
| Agent declares task complete when it isn't | Verification/termination (Cat 3) | Feature list / done condition / validation node |
| Agent repeats work already completed | Memory / harness | Progress artifacts, context compaction, session state |
| Agent calls the wrong tool | Action / specification (Cat 1) | Tool descriptions, schema overlap, tool selection traces |
| Tool is called with wrong parameters | Action | Tool input examples, strict mode, parameter descriptions |
| Agent contradicts itself across turns | Memory / context rot | Context length, observation masking, compaction quality |
| Agent ignores a prior agent's output | Inter-agent FM-2.5 | Handoff context transfer schema, A2A message structure |
| Agent proceeds on wrong assumption | Inter-agent FM-2.2 | Clarification instructions, ambiguity handling in prompts |
| Good individual steps, bad overall outcome | Specification / planning (Cat 1) | Task decomposition, orchestrator instructions, goal framing |
| Quality degrades as session grows longer | Context rot / memory | Token count per turn, compaction threshold, observation masking |
| High variance (works sometimes, fails others) | Non-determinism | Temperature settings, run k=5 to measure pass rate, inspect divergent traces |
| Cost spike without obvious cause | Loop / redundant calls | Langfuse span counts, node visit frequency, loop guard conditions |
