# Quick-Reference: Prompt Caching (Anthropic vs. OpenAI)

Side-by-side comparison of provider caching mechanics, with practical guidance.

---

## Provider Comparison

| Feature | Anthropic | OpenAI |
|---------|-----------|--------|
| **Activation** | Explicit cache control markers | Fully automatic for prompts >= 1,024 tokens |
| **Minimum tokens** | 1,024 per cache checkpoint | 1,024 (implicit) |
| **Cache write cost** | **25% more** than base input price | No additional write cost |
| **Cache read cost** | **10% of base** (= 90% savings) | **50% of base** (= 50% savings) |
| **Hit rate** | **100%** when matching prefix received | ~**50%** |
| **TTL (default)** | **5 minutes** (1.25x write cost) | Automatic (varies) |
| **TTL (extended)** | **1 hour** (2x write cost) | Not configurable |
| **Cache refresh** | Refreshes on each hit within TTL | Automatic |
| **Latency reduction** | Up to **85%** for long prompts | Up to **80%** |

---

## Anthropic Processing Order

Structure prompts to match this processing order for maximum cache utilisation:

```
Tools -> System Message -> Message History
```

Static content (tool definitions, system instructions) goes first; dynamic content (user messages, tool results) appends at the end. The static prefix is maximally cached while the dynamic suffix changes across requests.

---

## The "Don't Break the Cache" Paper (arXiv:2601.06007)

Evaluated prompt caching strategies for long-horizon agentic tasks across OpenAI (GPT-5.2), Anthropic (Claude Sonnet 4.5), and Google (Gemini 2.5 Pro).

**Key findings**:
- The "best cache mode" varies per model
- For Anthropic: explicit cache control with stable prefix maximisation achieves the highest cost reduction
- Agentic workloads with dynamic tool results benefit from structured prompt layout more than static QA workloads

---

## TTL Selection Guidance

| Scenario | Recommended TTL | Rationale |
|----------|----------------|-----------|
| Interactive sessions (user responds quickly) | **5 minutes** (default) | Lower write cost; refreshes on each hit |
| Long-running tasks (agentic side-agents, document analysis) | **1 hour** | Costs 2x more to write but pays back when session continues beyond 5 minutes |

---

## What to Cache vs. What NOT to Cache

### Cache These (Stable Prefixes)
- Tool definitions
- System instructions / system prompts
- Skill content (SKILL.md body)
- Few-shot examples
- Large reference documents that don't change per-request

### Do NOT Cache These
- **User-specific data in system prompts** -- breaks caching across users. Push personalisation into message content, not the system prompt.
- **Frequently changing prompts** -- invalidates caches. Version prompts and measure cache hit rates before optimising.

---

## Practical Example

A 100K-token book analysis prompt:

| Metric | Without Caching | With Caching |
|--------|----------------|-------------|
| Response time | **11.5 seconds** | **2.4 seconds** |

Source: Anthropic announcement data.

---

## Key Takeaway

> Prompt caching is the **single highest-leverage cost optimisation** for production agents. Anthropic's 90% reduction on cache reads and up to 85% latency reduction means structuring prompts for caching should be the first optimisation applied. The processing order (Tools -> System -> Messages) and stable-prefix discipline pay consistent dividends.
