---
name: agent-harness-design
description: Design harnesses for long-horizon agent tasks — the initializer/coding agent split, feature list JSON, progress artifacts, the clean-state rule, init.sh patterns, and end-to-end verification. Use this skill when the user needs to build an agent that works across multiple sessions on a large task, decompose a complex project into trackable sub-goals, persist progress between agent sessions, prevent agents from one-shotting or declaring premature completion, or design verification that catches incomplete work. Also use when the user says things like "my agent tries to do everything at once", "it declares done when it isn't", "how do I make my agent work across sessions", "build a long-running agent", or is designing any agent task that spans more than one context window.
---

# Agent Harness Design

Long-running agents face a fundamental challenge: context windows are finite and discrete, but complex tasks span many sessions. Each new context window begins with no memory of what came before. Compaction alone is insufficient — even frontier models running in a loop with compaction fail predictably on production-scale tasks.

Two failure modes emerge reliably:
1. The agent tries to do everything at once (one-shotting), runs out of context, and leaves the environment broken
2. The agent looks around late in a session, sees prior work, and declares the project complete when most features remain unbuilt

The solution is a two-agent harness with external artifacts as persistent memory.

## Step 1: Understand the task scope

Before designing a harness, confirm this is a long-horizon task:

- Can it be completed in a single context window? If yes, no harness needed.
- Does it have multiple distinct sub-goals? If not, it's a single task, not a project.
- Will it span multiple sessions? If yes, the harness pattern applies.

## Step 2: Design the initializer agent

The initializer runs exactly once on the first session. Its job is to set up the environment so every subsequent agent can quickly understand the state of work.

The initializer creates:

### Feature list (structured JSON, not Markdown)

JSON is critical — models are less likely to inadvertently overwrite JSON than Markdown. Each feature has a testable pass condition.

```json
{
  "features": [
    {
      "id": 1,
      "name": "User authentication",
      "description": "JWT-based auth with login/register endpoints",
      "passes": false,
      "verification": "POST /register creates user, POST /login returns valid JWT"
    },
    {
      "id": 2,
      "name": "Task CRUD",
      "description": "Create, read, update, delete tasks via REST API",
      "passes": false,
      "verification": "All CRUD operations work via API tests"
    }
  ]
}
```

### Progress log

Records what has been done, what failed, and what decisions were made. The coding agent reads this at the start of every session.

### init.sh script

Starts the development environment and runs a basic end-to-end sanity check. Solves the "agent wastes time figuring out how to run the project" problem. Front-load operational knowledge into a runnable script.

### Initial git commit

Establishes a clean baseline that any future agent can diff against.

## Step 3: Design the coding agent

Runs on every subsequent session. Its workflow is strict:

1. Run `pwd`, read the progress log and git history to understand state
2. Read the feature list to find the highest-priority incomplete feature
3. Run `init.sh` to verify the environment is working
4. Implement exactly **one feature per session**
5. Test end-to-end (not just unit tests — verify as a real user would)
6. Commit with a descriptive message
7. Update the progress log before the session ends

### Critical rules

- **Do not mark a feature as passing without running end-to-end verification**
- **Do not remove or edit tests to make them pass**
- **Do not attempt multiple features per session** — one feature, fully verified, is the target
- **Leave work in a committed, documented, deployable state** — never half-implemented (the clean-state rule)

## Step 4: Design the progress artifacts

External artifacts become the agent's memory. They persist across sessions and are more reliable than compacted conversation history because they capture structured, intentional state.

| Artifact | Format | Purpose | Updated by |
|----------|--------|---------|-----------|
| Feature list | JSON | What needs to be done, what's done | Initializer creates; coding agent updates `passes` |
| Progress log | Markdown or text | What happened, decisions, failures | Coding agent appends each session |
| Git history | Commits | What code changed and why | Coding agent commits each session |
| init.sh | Shell script | How to start and verify the environment | Initializer creates; coding agent may extend |

## Step 5: Design end-to-end verification

The most common failure mode is agents declaring completion without verification. The harness must enforce verification:

- **Unit tests are necessary but insufficient** — they test components, not user-visible behaviour
- **End-to-end verification** tests as a real user would: browser automation, API calls, CLI invocations
- The feature list's `verification` field defines what "passing" means for each feature
- The coding agent must run the verification and see it pass before updating the feature list

## Step 6: Generalise to non-software domains

The pattern is domain-agnostic. Any long-horizon task benefits from:

- An **initialisation phase** that expands the goal into a structured, checkable list of sub-goals
- A **progress artifact** that persists state across sessions in a readable form
- A **clean-state rule** requiring each session to end with work in a committed, documented state
- **End-to-end verification** before marking any sub-goal complete

Examples: scientific research (experiment list + lab notebook), financial modelling (model component list + assumption log), content production (outline + draft status tracker).

## Step 7: Present the harness design

Output:

1. **Task decomposition** — feature list JSON with verification conditions for each sub-goal
2. **Initializer agent instructions** — what it creates, what it leaves behind
3. **Coding agent instructions** — session workflow, rules, verification requirements
4. **Progress artifact design** — what files, what format, who updates them
5. **init.sh outline** — environment setup and sanity check steps
6. **Verification strategy** — how each sub-goal is tested end-to-end
