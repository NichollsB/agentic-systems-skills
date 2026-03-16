# Agentic Systems Skills

A skill collection for designing and building production-grade agentic AI systems. Built on the [AgentSkills.io](https://agentskills.io) standard, compatible with Claude Code, Cursor, GitHub Copilot, and any agent that supports SKILL.md files.

## What this is

Building an agentic system without structured guidance risks choosing the wrong architecture and having to rebuild, missing guardrails that become expensive to retrofit, ignoring persistence patterns that cause production failures, or skipping observability that makes debugging impossible.

This collection addresses those risks. It provides 13 skills covering the full development lifecycle — from initial architecture decisions through implementation, production hardening, deployment, and maintenance. Each skill encodes best practices from Anthropic, LangChain, and current research (NeurIPS 2025, ICLR 2025, JetBrains 2025, Chroma 2025) so they're applied consistently rather than rediscovered per project.

The skills produce **design artifacts** (architecture decision records, guardrail maps, model assignment tables, persistence configs) that serve as the specification for implementation. They don't write your system for you — they ensure you've thought about the things that are costly to get wrong.

## Installation

### Clone

Third-party skills are included in the repo under `vendor/` via [git subtree](https://www.atlassian.com/git/tutorials/git-subtree). No special clone flags needed — a standard clone gets everything:

```bash
git clone https://github.com/[your-username]/agentic-systems-skills.git ~/skills/agentic-systems-skills
```

### Symlink into your project

Symlink the collection and vendor skills into your project's `.claude/skills/` directory:

```bash
# The main collection
ln -s ~/skills/agentic-systems-skills .claude/skills/agentic-systems

# Context engineering skills (community — by Murat Can Koylan)
for skill in context-fundamentals context-degradation context-compression context-optimization filesystem-context multi-agent-patterns memory-systems tool-design evaluation advanced-evaluation project-development; do
  ln -s ~/skills/agentic-systems-skills/vendor/context-engineering/skills/$skill .claude/skills/$skill
done

# Langfuse skill (by Langfuse)
ln -s ~/skills/agentic-systems-skills/vendor/langfuse-skills/skills/langfuse .claude/skills/langfuse

# Anthropic skill-creator (by Anthropic)
ln -s ~/skills/agentic-systems-skills/vendor/anthropic-skills/skills/skill-creator .claude/skills/skill-creator
```

Or symlink globally into `~/.claude/skills/` for use across all projects.

### Updating vendor skills

The vendor skills are included as git subtrees. To pull the latest from upstream:

```bash
cd ~/skills/agentic-systems-skills
git subtree pull --prefix vendor/context-engineering https://github.com/muratcankoylan/Agent-Skills-for-Context-Engineering.git main --squash
git subtree pull --prefix vendor/langfuse-skills https://github.com/langfuse/skills.git main --squash
git subtree pull --prefix vendor/anthropic-skills https://github.com/anthropics/skills.git main --squash
```

## How to use

### Building from scratch

Work through the phases in order. Each produces design artifacts that feed the next:

1. **Architecture** — `agentic-architecture`, `model-selection`
2. **Implementation** — `langgraph-fundamentals`, `reflection-and-validation`, `inter-agent-communication`
3. **Reliability** — `guardrails-and-security`, `memory-and-persistence`
4. **Operations** — `litellm-configuration`, `project-setup`, `deployment-and-versioning`, `langfuse-integration`
5. **Maintenance** — `agent-debugging`, `agent-harness-design`

When design phases are complete, you'll have a comprehensive specification to build against — architecture decisions, graph stubs, guardrail maps, persistence config, deployment plans, and observability setup.

### Targeted use

Each skill works independently. Go directly to what you need:

- "My agent calls the wrong tool" → `agent-debugging`
- "Add human-in-the-loop" → `langgraph-fundamentals`
- "Set up Langfuse" → `langfuse-integration`
- "Which model for which role" → `model-selection`
- "My agent loops forever" → `langgraph-fundamentals` (loop guards)
- "Prepare for production" → `guardrails-and-security`, `memory-and-persistence`, `deployment-and-versioning`

### Mid-project audit

Scan the skill list. Any phase you haven't considered is a potential gap. Common gaps discovered late: guardrails (Phase 3), observation masking for context rot (Phase 3), the four change vectors for deployment (Phase 4), and spend alerts (Phase 4).

## Repository structure

```
agentic-systems-skills/
+-- SKILL.md                        # Collection entry point — skill map, phases, handoff
+-- README.md
+-- skills/                         # 13 sub-skills
|   +-- agentic-architecture/
|   +-- langgraph-fundamentals/
|   +-- reflection-and-validation/
|   +-- inter-agent-communication/
|   +-- guardrails-and-security/
|   +-- memory-and-persistence/
|   +-- model-selection/
|   +-- litellm-configuration/
|   +-- project-setup/
|   +-- deployment-and-versioning/
|   +-- langfuse-integration/
|   +-- agent-debugging/
|   +-- agent-harness-design/
+-- references/                     # Decision tables and quick-reference cards
|   +-- decision-workflows-vs-agents.md
|   +-- decision-multi-agent-topology.md
|   +-- decision-framework-selection.md
|   +-- decision-memory-tier.md
|   +-- ref-mast-taxonomy.md
|   +-- ref-litellm-routing.md
|   +-- ref-prompt-caching.md
+-- addendums/                      # Extensions to community skills
    +-- tool-design-anthropic-api.md
    +-- token-optimisation-anthropic.md
    +-- context-engineering-strategies.md
    +-- mcp-langgraph-patterns.md
    +-- skill-integration-patterns.md
```

## Skills overview

| Skill | What it produces | Key value |
|-------|-----------------|-----------|
| `agentic-architecture` | Architecture Decision Record | Prevents wrong pattern choice |
| `model-selection` | Model assignment table | CLASSic framework, tier discipline |
| `langgraph-fundamentals` | Complete graph implementation | State schema, nodes, wiring, loop guards |
| `reflection-and-validation` | Validation strategy | CRAG, reflection loops, quality gates |
| `inter-agent-communication` | Communication contract | Telephone game fix, HandoffContext |
| `guardrails-and-security` | Guardrail map | Four-layer defence, trust tiers |
| `memory-and-persistence` | Persistence configuration | Checkpointer selection, context rot |
| `litellm-configuration` | LiteLLM config | Routing, fallbacks, budgets |
| `project-setup` | Project scaffold | Folder structure, DI, testing strategy |
| `deployment-and-versioning` | Versioning plan | Four change vectors, rollback |
| `langfuse-integration` | Observability config | Evaluation flywheel, spend alerts |
| `agent-debugging` | Root cause diagnosis | MAST taxonomy, time-travel debugging |
| `agent-harness-design` | Harness scaffold | Two-agent split, long-horizon tasks |

## Source material

The skills are derived from `references/agentic-systems-reference-guide.md`, which synthesises:

- Anthropic engineering guides (Building Effective Agents, Writing Effective Tools, Context Engineering, Equipping Agents)
- LangGraph official documentation
- Google A2A protocol specification
- MAST taxonomy (NeurIPS 2025)
- CLASSic framework (ICLR 2025)
- JetBrains research on context management (2025)
- Chroma Context-Rot research (2025)
- LiteLLM production documentation
- Langfuse documentation
- AgentSkills.io specification

## Vendor skills (third-party)

The `vendor/` directory contains third-party skill libraries included via [git subtree](https://www.atlassian.com/git/tutorials/git-subtree). These are not our work — they are maintained by their respective authors and included here for convenience so the complete framework works out of the box.

| Directory | Source | Author | License |
|-----------|--------|--------|---------|
| `vendor/context-engineering/` | [Agent-Skills-for-Context-Engineering](https://github.com/muratcankoylan/Agent-Skills-for-Context-Engineering) | Murat Can Koylan | See repo |
| `vendor/langfuse-skills/` | [langfuse/skills](https://github.com/langfuse/skills) | Langfuse | See repo |
| `vendor/anthropic-skills/` | [anthropics/skills](https://github.com/anthropics/skills) | Anthropic | See repo |

