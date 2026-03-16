# Agentic Systems Skills

A skill collection for designing and building production-grade agentic AI systems. Built on the [AgentSkills.io](https://agentskills.io) standard, compatible with Claude Code, Cursor, GitHub Copilot, and any agent that supports SKILL.md files.

## What this is

Building an agentic system without structured guidance risks choosing the wrong architecture and having to rebuild, missing guardrails that become expensive to retrofit, ignoring persistence patterns that cause production failures, or skipping observability that makes debugging impossible.

This collection addresses those risks. It provides 13 skills covering the full development lifecycle — from initial architecture decisions through implementation, production hardening, deployment, and maintenance. Each skill encodes best practices from Anthropic, LangChain, and current research (NeurIPS 2025, ICLR 2025, JetBrains 2025, Chroma 2025) so they're applied consistently rather than rediscovered per project.

The skills produce **design artifacts** (architecture decision records, guardrail maps, model assignment tables, persistence configs) that serve as the specification for implementation. They don't write your system for you — they ensure you've thought about the things that are costly to get wrong.

## Installation

### As a complete collection (recommended)

Clone the repo and symlink the root skill into your project:

```bash
git clone https://github.com/[your-username]/agentic-systems-skills.git ~/skills/agentic-systems-skills

# Symlink the collection into your project
ln -s ~/skills/agentic-systems-skills .claude/skills/agentic-systems
```

Or symlink globally for all projects:

```bash
ln -s ~/skills/agentic-systems-skills ~/.claude/skills/agentic-systems
```

### Complementary third-party skills

This collection is designed to work alongside these community and vendor skills. Install them for the complete framework:

```bash
# Context engineering (community)
git clone https://github.com/muratcankoylan/Agent-Skills-for-Context-Engineering.git ~/skills/context-engineering

# Langfuse (vendor)
git clone https://github.com/langfuse/skills.git ~/skills/langfuse-skills

# Anthropic skill-creator (vendor)
git clone https://github.com/anthropics/skills.git ~/skills/anthropic-skills

# Symlink individually into your project's .claude/skills/ or globally into ~/.claude/skills/
```

See the root `SKILL.md` for the full list of third-party skills and how they complement this collection.

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

## License

[Add your license here]
