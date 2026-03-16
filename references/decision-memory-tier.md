# Decision Table: Memory Tier Selection

Quick-reference for memory architecture, compaction strategy, and context management.

---

## The Four Memory Types

| Memory Type | What It Is | Persistence | Access Pattern |
|-------------|-----------|-------------|----------------|
| **In-context (working memory)** | Current state object and message history. What the agent is actively thinking about. | Finite, expensive, cleared between sessions unless checkpointed. | Always available in current context. |
| **Episodic memory** | Records of past interactions and outcomes. Supports reasoning like "last time I tried X, Y happened." | Persists in store (PostgresStore). | Key format: `task -> actions -> outcomes -> lessons_learned`. |
| **Semantic memory** | General facts, domain knowledge, user preferences. | Stored in vector database, persists indefinitely. | Accessed via RAG / semantic retrieval. |
| **Procedural memory** | Skills and how to use tools -- encoded in SKILL.md files and tool schemas. | Survives context compaction. | Transfers across sessions without retrieval overhead. |

---

## Three-Tier Compaction Strategy

| Tier | Storage | Retention | Trigger |
|------|---------|-----------|---------|
| **Hot** (active turns) | In-context state | Last 10 turns verbatim | Always present |
| **Warm** (session summary) | Checkpointer | LLM-generated summary | At **70-80% context capacity** |
| **Cold** (episodic archive) | PostgresStore | Structured task records | Per-session end |

### Compaction Trigger Guidance

> Trigger compaction at **70-80%** of context capacity, not at the limit. Waiting until the context window is full risks degraded quality before compaction kicks in.

---

## Observation Masking (Apply Before LLM Summarisation)

JetBrains research (2025) found that **observation masking** -- keeping the latest 10 turns verbatim and masking older tool observations -- delivers:

| Metric | Result |
|--------|--------|
| **Cost reduction** | 52% |
| **Solve rate improvement** | +2.6% on SWE-bench |

Use observation masking **before** resorting to LLM-based summarisation, which adds its own latency and cost. Observation masking is the first line of defence against context rot.

---

## Context Rot Warning

Chroma's research (Context-Rot, 2025) confirms that **all models experience performance degradation with long contexts**. The problem is not just cost -- quality degrades as context grows. This makes proactive compaction a **correctness requirement**, not just a cost optimisation.

---

## Decision Flow

1. **Start with observation masking** (mask older tool observations, keep last 10 turns). Free, instant, proven.
2. **Add warm-tier compaction** at 70-80% context capacity using LLM-generated summaries.
3. **Archive to cold storage** (structured task records) at session end for cross-session episodic memory.
4. **Use procedural memory** (SKILL.md) for knowledge that must survive compaction without retrieval cost.
5. **Use semantic memory** (vector store) for large knowledge bases requiring similarity search.
