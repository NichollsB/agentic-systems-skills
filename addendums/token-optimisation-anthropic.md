# Token Optimisation: Provider-Specific Mechanics

Addendum to the community `context-optimization` skill. Covers Anthropic and OpenAI prompt caching specifics, Batch API, output length control, and LLMLingua compression.

---

## Anthropic Prompt Caching

Prompt caching reuses previously computed key-value (KV) tensors from attention layers, avoiding redundant computation on repeated prompt prefixes.

| Parameter | Value |
|-----------|-------|
| Cache write cost | **25% more** than base input token price (e.g., $3.75/M base -> $4.69/M cache write for Sonnet) |
| Cache read cost | **10% of base** input token price (= **90% savings** on reads) |
| TTL (default) | **5 minutes** (1.25x write cost) |
| TTL (extended) | **1 hour** (2x write cost) |
| Minimum tokens per cache checkpoint | **1,024 tokens** |
| Cache hit rate | **100%** when Anthropic receives a matching prefix |
| Cache entries | Refresh on each hit within the TTL window |

### Processing Order

Anthropic processes request components in this order. Structure prompts to match:

```
Tools -> System Message -> Message History
```

Static content (tool definitions, system instructions) goes first; dynamic content (user messages, tool results) appends at the end. This ensures the static prefix is maximally cached while the dynamic suffix changes across requests.

### TTL Selection Guidance

| Scenario | Recommended TTL | Rationale |
|----------|----------------|-----------|
| Interactive sessions (user responds quickly) | **5 minutes** (default) | Lower write cost; refreshes on each hit |
| Long-running tasks (agentic side-agents, long document analysis) | **1 hour** | Costs 2x more to write but pays back when the session continues beyond 5 minutes |

### What NOT to Cache

- **User-specific data in system prompts** -- breaks caching across users. Push personalisation into message content, not the system prompt.
- **Frequently changing prompts** -- invalidates caches. Version prompts and measure cache hit rates before optimising.

---

## OpenAI Prompt Caching

| Parameter | Value |
|-----------|-------|
| Activation | **Fully automatic** for prompts >= 1,024 tokens |
| Cost reduction | **50%** on cached tokens |
| Latency reduction | Up to **80%** |
| Explicit marking | Not required -- just ensure prompt prefix is stable |
| Cache hit rate | ~**50%** (vs Anthropic's 100%) |

---

## Batch API

| Parameter | Value |
|-----------|-------|
| Discount | **50%** on both input and output tokens |
| Turnaround | **24 hours** (asynchronous processing) |
| Supported models | All Claude models at consistent 50% discounts |

### Use Cases
- Running comprehensive test suites against prompts and agent workflows
- Offline data processing pipelines
- Content generation at scale
- Model evaluation runs

---

## Output Length Control

Each output token costs roughly **4x more** than input tokens. Techniques for intermediate agent reasoning:

- Use explicit length instructions: "Be concise. Respond in 2-3 sentences."
- Set `max_tokens` explicitly for intermediate steps
- Use structured output schemas that naturally constrain verbosity
- Apply **differential verbosity**: verbose for final user-facing output, ultra-concise for intermediate tool-use planning

Research (arXiv:2407.19825, Concise Chain of Thought): adding "limit the answer length to N words" to CoT prompts maintains accuracy while significantly reducing output tokens for intermediate reasoning steps.

---

## LLMLingua: Prompt Compression

Microsoft's LLMLingua uses a small language model to identify and remove unimportant tokens from long prompts.

| Metric | Result |
|--------|--------|
| Compression ratio | Up to **20x** |
| Accuracy improvement | **+7.89 F1** on 2WikiMultihopQA at 4.5x compression |

Extractive compression can actually **improve** accuracy by removing noise. Use as a pre-processing step on retrieved documents before they enter the context window.
