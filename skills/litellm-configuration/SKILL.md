---
name: litellm-configuration
description: Configure LiteLLM as the model abstraction layer — routing strategies, YAML configuration, fallback chains, rate limits, budget enforcement, and LangGraph integration. Use this skill when the user needs to set up LiteLLM proxy, configure model routing, add fallback chains, enforce rate limits or budgets, integrate LiteLLM with LangGraph, or prepare for production deployment. Also use when the user says things like "set up LiteLLM", "configure model routing", "add fallback for my models", "enforce budget limits", "how do I use LiteLLM with LangGraph", or is deploying an agent system that needs a model abstraction layer.
---

# LiteLLM Configuration

LiteLLM provides a unified gateway to 100+ LLM providers with an OpenAI-compatible API. This skill produces a working LiteLLM configuration for the deployment being built.

## Step 1: Understand the deployment

Before configuring, get clear on requirements:

- What models and providers are being used? (Anthropic, OpenAI, Google, Azure, etc.)
- What roles need routing? (orchestrator, worker, validator — from `model-selection`)
- Is this local dev, staging, or production?
- Do you need rate limiting, budget enforcement, or cost tracking?
- Single instance or multi-instance deployment?

## Step 2: Select a routing strategy

| Strategy | How it works | Use when |
|----------|-------------|----------|
| **`simple-shuffle`** (recommended) | Picks deployment based on RPM/TPM weights; random if no weights | Most production deployments. Minimal overhead, no external state. |
| **`least-busy`** | Routes to deployment with fewest in-flight requests | Reducing tail latency matters more than throughput |
| **`usage-based-routing`** | Routes to lowest-usage deployment relative to limits | **Not recommended for production** — LiteLLM docs warn against it due to Redis overhead |
| **`latency-based-routing`** | Samples latency, routes to fastest | Deployments have significantly different latency characteristics |

Start with `simple-shuffle`. Only change if you have a measured problem it doesn't solve.

## Step 3: Build the YAML configuration

The configuration maps model roles to provider deployments with fallback chains:

```yaml
model_list:
  # Role: orchestrator (frontier model, primary + fallback)
  - model_name: orchestrator
    litellm_params:
      model: anthropic/claude-sonnet-4-5-latest
      api_key: os.environ/ANTHROPIC_API_KEY
      order: 1

  - model_name: orchestrator
    litellm_params:
      model: openai/gpt-4.1
      api_key: os.environ/OPENAI_API_KEY
      order: 2

  # Role: worker (mid-tier, cost-efficient)
  - model_name: worker
    litellm_params:
      model: openai/gpt-4o-mini
      api_key: os.environ/OPENAI_API_KEY
      rpm: 500
      tpm: 200000

  # Role: validator (fast, cheap)
  - model_name: validator
    litellm_params:
      model: anthropic/claude-haiku-4-5
      api_key: os.environ/ANTHROPIC_API_KEY

router_settings:
  routing_strategy: simple-shuffle
  enable_pre_call_checks: true       # required for order parameter
  fallbacks:
    - orchestrator: [worker]          # cross-provider fallback
  context_window_fallbacks:
    - orchestrator: [orchestrator-128k]
  num_retries: 2
  timeout: 30
  allowed_fails: 3
  cooldown_time: 30
```

Key configuration rules:
- Use `order` parameter with `enable_pre_call_checks: true` for priority-based failover
- Cross-provider fallbacks for resilience (don't fallback to the same provider)
- Set `rpm`/`tpm` on deployments for routing weight and optional hard limits
- Use `model_group_alias` for transparent alias routing

## Step 4: Configure rate limits and budgets

### Hard rate limits

By default, RPM/TPM values are only routing hints. To enforce as hard limits (HTTP 429 on exceed):

```yaml
router_settings:
  optional_pre_call_checks:
    - enforce_model_rate_limits
```

For multi-instance deployments, add Redis so all instances share rate limit state.

### Budget enforcement

Multi-tier hierarchical budgets: Organisation -> Team -> User -> Key -> End User.

```yaml
router_settings:
  provider_budget_config:
    anthropic:
      budget_limit: 200.0
      time_period: 1d
    openai:
      budget_limit: 100.0
      time_period: 1d
```

Use tag-based cost tracking to attribute costs by feature or project:
```python
response = litellm.completion(
    model="orchestrator",
    messages=[...],
    metadata={"tags": ["project:research", "feature:planning"]}
)
```

## Step 5: Wire into LangGraph

Use `ChatOpenAI` pointed at the LiteLLM proxy — all routing happens transparently:

```python
from langchain_openai import ChatOpenAI

PROXY_URL = "http://0.0.0.0:4000"
LITELLM_KEY = os.environ["LITELLM_API_KEY"]

def build_model(role: Literal["orchestrator", "worker", "validator"]) -> ChatOpenAI:
    return ChatOpenAI(
        openai_api_base=PROXY_URL,
        model=role,          # LiteLLM routes based on this model name
        api_key=LITELLM_KEY,
        streaming=True
    )
```

Inject via model factory — never hardcode model names in nodes. This makes model changes a config change, not a code change.

## Step 6: Production deployment checklist

**Infrastructure:**
- Minimum 4 vCPU, 8 GB RAM
- Match workers to CPU count: `--num_workers $(nproc)`
- Use `--max_requests_before_restart 10000` for stable worker recycling

**Redis (required for multi-instance):**
- Use `redis_host`/`redis_port`/`redis_password` — NOT `redis_url` (80 RPS slower due to connection overhead)
- Required for shared rate limit state and cooldown tracking

**Performance:**
- `LITELLM_LOG="ERROR"` — suppress verbose logging in production
- `set_verbose: False` in config
- `proxy_batch_write_at: 60` — batch spend updates every 60 seconds

**Security:**
- `LITELLM_SALT_KEY` — encrypt stored API keys
- Separate API keys for dev/staging/prod
- Automated key rotation policy

**Kubernetes:**
- `SEPARATE_HEALTH_APP=1` for responsive health checks under load
- `LITELLM_MIGRATION_DIR` to writable path
- `SUPERVISORD_STOPWAITSECS=3600` for graceful shutdown

**Supporting reference docs**: see `references/ref-litellm-routing.md` for a quick-lookup card comparing routing strategies.

## Step 7: Present the configuration

Output:

1. **Routing strategy selection** — which strategy and why
2. **Complete YAML configuration** — model list, router settings, litellm settings
3. **Rate limit and budget configuration** — if applicable
4. **LangGraph integration code** — model factory wired to the proxy
5. **Environment-specific notes** — what changes between dev/staging/prod
