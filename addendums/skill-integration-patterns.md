# Skill Integration Patterns

Short reference for integrating AgentSkills.io skills into agentic systems. Extends the `skill-creator` Anthropic skill with architectural patterns.

## Skill vs Tool vs Inline Prompt

| Option | Use when | Key distinction |
|--------|----------|----------------|
| **Skill** | Reusable reasoning guidance; complex enough for structured steps; benefits from eval-driven iteration | Extends what the agent KNOWS how to do |
| **Tool** | Deterministic operation; structured I/O; called programmatically | Extends what the agent CAN do |
| **Inline prompt** | One-off, project-specific; simple enough for a system prompt section | No reuse, no progressive disclosure |

A search tool lets the agent search. A research skill teaches it how to conduct effective research.

## Dual-Use LangGraph Wrapper

The same SKILL.md works in LangGraph and standalone without duplication:

```python
def load_skill(skill_name: str) -> str:
    path = SKILLS_DIR / skill_name / "SKILL.md"
    return path.read_text().split("---", 2)[-1].strip()

# As a LangGraph node
def research_node(state: AgentState) -> dict:
    result = llm.invoke([
        SystemMessage(content=load_skill("deep-research")),
        HumanMessage(content=state["query"])
    ])
    return {"research_result": result.content}

# Standalone
def run_research(query: str) -> str:
    return llm.invoke([
        SystemMessage(content=load_skill("deep-research")),
        HumanMessage(content=query)
    ]).content
```

**Critical constraint: do not embed graph state assumptions in SKILL.md.** Keep skills declarative; let the execution wrapper handle state management. This is what makes the dual-use pattern possible.
