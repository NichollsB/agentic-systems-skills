# Context Engineering Strategies

Addendum to the community `context-fundamentals` skill. Covers Anthropic's four context strategies, just-in-time context patterns, and the speed/accuracy tradeoff.

---

## Context Engineering vs. Prompt Engineering

Context engineering is Anthropic's term for the discipline that has superseded prompt engineering. Andrej Karpathy's definition: "the delicate art and science of filling the context window with just the right information for the next step."

The distinction is architectural, not cosmetic:
- **Prompt engineering** asks: how do I write effective instructions?
- **Context engineering** asks: what is the optimal configuration of **all tokens** -- system prompt, tools, examples, message history, retrieved data, tool results -- at each inference step, given finite attention budget and degradation under load?

The core constraint is **attention scarcity**. The transformer architecture creates n-squared pairwise relationships for n tokens. As context length increases, the model's ability to maintain those relationships degrades. This is not a soft preference -- it is an architectural reality that shows up as **context rot**: measurable degradation in recall and reasoning accuracy as the context window fills.

---

## Anthropic's Four Context Strategies

### 1. Write

**Save information outside the context window for later retrieval.**

Structured notes, progress files, external memory stores. The agent externalises what it cannot afford to keep in context. This is the key pattern in long-horizon agent harnesses.

- **Speed**: Fast (write is cheap; retrieval adds latency later)
- **Accuracy**: High for structured, intentional state. More reliable than compacted conversation history.
- **Example**: Agent writes a JSON feature list and progress log to disk; reads them back at the start of each new session.

### 2. Select

**Pull relevant information into the context window on demand.**

Two approaches:
- **Agentic search** (grep, glob, read): slower but more accurate, more transparent, and easier to maintain.
- **Semantic search** (RAG): faster at scale but less precise and harder to debug.

- **Speed**: Agentic search is slower; semantic search is faster.
- **Accuracy**: Agentic search is more accurate; semantic search has variable fidelity.
- **Guidance**: Start with agentic search; add semantic search only when you need speed at scale.
- **Example**: Claude Code uses CLAUDE.md files loaded upfront, but files, search results, and documentation load just-in-time via grep, glob, and read.

### 3. Compress

**Summarise or filter information before it enters the context window.**

Tool output truncation, document summarisation, compaction of message history.

- **Speed**: Reduces downstream processing time by keeping context smaller.
- **Accuracy**: Risks losing subtle context whose importance only becomes apparent later.
- **Guidance**: Apply conservatively. Observation masking (52% cost reduction, +2.6% solve rate) is preferred over LLM summarisation.
- **Example**: Keep last 10 turns verbatim, mask older tool observations.

### 4. Isolate

**Use subagents with their own context windows to process information that does not need to flow back to the orchestrator in full.**

Subagents return summaries, not full transcripts. This is the architectural basis for parallelisation and the primary way to break the O(n-squared) context cost for large information sets.

- **Speed**: Adds latency from subagent invocation; enables parallelism.
- **Accuracy**: Dependent on subagent summary quality. Orchestrator sees less raw data.
- **Example**: Research subagent processes 50 documents and returns a 500-token synthesis, instead of the orchestrator reading all 50 documents directly.

---

## Just-in-Time Context vs. Pre-Loaded Context

The emerging production pattern is replacing **pre-inference RAG** (load everything relevant upfront) with **just-in-time retrieval** (load only what the agent decides it needs, when it needs it).

Instead of chunking and embedding an entire knowledge base and hoping retrieval captures the right sections, the agent maintains lightweight references (file paths, stored queries, links) and loads them on demand using tools.

### How Claude Code Demonstrates This

- `CLAUDE.md` files load upfront (stable, high-value context)
- Files, search results, and documentation load just-in-time via grep, glob, and read
- Folder structure, naming conventions, and timestamps become metadata the agent uses to decide what is worth loading
- Mirrors human cognition: we maintain indexing systems and retrieve on demand, not memorise entire corpuses

### The Tradeoff

| Context Type | Speed | Accuracy | Best For |
|-------------|-------|----------|----------|
| **Pre-loaded** (semantic retrieval) | Faster | Variable (depends on retrieval quality) | Slow-moving knowledge (legal documents, technical specs) |
| **Just-in-time** (agentic search) | Slower | Higher (agent selects precisely) | Rapidly changing contexts (code, live data) |

The right balance depends on task dynamics. For slow-moving knowledge, pre-loaded semantic retrieval may be more efficient. For rapidly changing contexts, just-in-time is more accurate.
