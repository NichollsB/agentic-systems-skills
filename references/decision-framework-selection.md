# Decision Table: Framework Selection

Quick-reference for choosing the right agent framework (or no framework).

---

## Framework Decision Table

| Framework | Choose When | Limitations |
|-----------|-------------|-------------|
| **No framework** | The task can be expressed in fewer than 50 lines of Python; you have a single LLM call with retrieval; or you are still in the problem discovery phase. | No built-in state management, checkpointing, or observability. |
| **LangGraph** | You need durable execution (agents that survive process failures); explicit, auditable state management across complex multi-step workflows; human-in-the-loop with state inspection; production observability via LangSmith; or you are already in the LangChain ecosystem. LangGraph 1.0 shipped October 2025 -- first stable major release. Default runtime for all LangChain agents. Best for production-grade agents (used by Klarna, Replit, Elastic). | Steeper learning curve than role-based frameworks. |
| **CrewAI** | Your workflow maps naturally onto human team metaphors (researcher, writer, reviewer); you want fast time-to-first-working-prototype; your team thinks in roles and tasks rather than graphs and state machines. Easiest abstraction for business workflow automation. | Not ideal for complex state management, precise control over execution order, or production observability requirements. |
| **AutoGen / AG2** | The workflow is fundamentally conversational -- agents debating, negotiating, or refining through dialogue; you need multi-agent group chat patterns; or you have a mixed technical/non-technical team that will use AutoGen Studio's visual interface. AG2 (community fork) offers declarative serialisation of agent configurations into JSON for reproducible definitions. | Conversation-centric model may not suit all workflows. |
| **PydanticAI** | Type-safe, validated outputs are the primary requirement (financial services, healthcare, compliance-sensitive applications); you want tight integration with Pydantic validation already in your stack; or your use case is structured data extraction with guaranteed schema conformance. Fastest raw execution in benchmarks. | Best for structured task agents with clear output contracts; less suited to open-ended agentic workflows. |
| **OpenAI Agents SDK** | You are committed to the OpenAI ecosystem; you want the simplest possible path to multi-agent orchestration with built-in tracing, guardrails, and handoffs; or provider flexibility across 100+ LLMs is more important than framework feature depth. Released March 2025; production-ready. | Advanced capabilities couple tightly to OpenAI's platform. |

---

## Anthropic's Guidance

> "Many patterns can be implemented in a few lines of code. If you do use a framework, ensure you understand the underlying code -- incorrect assumptions about what's under the hood are a common source of error."

---

## Framework-Agnostic Skills

A key architectural benefit of the AgentSkills.io standard is that **skills are framework-agnostic by construction**. Skills written for a LangGraph agent work unchanged in a CrewAI agent, an AutoGen agent, or a plain Python loop. If you later migrate frameworks, your skills migrate for free. This is one of the most concrete arguments for investing in the SKILL.md standard early.
