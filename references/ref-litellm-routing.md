# Quick-Reference: LiteLLM Routing Strategies

For use when configuring LiteLLM Proxy Server routing in production.

---

## Routing Strategy Decision Table

| Strategy | How It Works | Use When | Warnings |
|----------|-------------|----------|----------|
| **`simple-shuffle`** (default) | Picks a deployment based on provided RPM/TPM weights; randomly selects if no weights are set. | **RECOMMENDED for most production deployments.** Best performance with minimal latency overhead. No external state required. | None -- this is the safe default. |
| **`least-busy`** | Queue-based routing to the deployment with fewest in-flight requests. | Reducing tail latency when deployments have similar capabilities. | Adds bookkeeping overhead. |
| **`usage-based-routing`** | Routes to the deployment with the lowest usage relative to its limits. | Maximising utilisation across deployments with different rate limits. | **LiteLLM's own documentation explicitly warns against using this in production** due to performance impacts from Redis operations on every request. |
| **`latency-based-routing`** | Samples latency and routes to fastest deployment. | Deployments have significantly different latency characteristics and you can absorb the measurement cost. | Adds overhead from latency sampling. |

### The Recommendation

> Use **`simple-shuffle`** for production. It provides the best performance with minimal overhead and no external state requirements.

### The usage-based-routing Warning

From LiteLLM docs: this strategy performs Redis operations on every request to track and compare usage, which introduces latency at scale. Do not use in production unless you have a specific requirement that justifies the overhead.

---

## Redis Configuration

### When Redis Is Required

Redis is required for **multi-instance deployments** to share rate limit state and cooldown tracking across all proxy instances.

### redis_host vs redis_url Performance Difference

> Use `redis_host`/`redis_port`/`redis_password` -- **NOT `redis_url`**. The `redis_url` parameter is **80 RPS slower** due to connection overhead.

```yaml
# Correct -- use individual parameters
litellm_settings:
  cache: true
  cache_params:
    type: redis
    host: os.environ/REDIS_HOST
    port: os.environ/REDIS_PORT
    password: os.environ/REDIS_PASSWORD

# Avoid -- 80 RPS slower
# cache_params:
#   type: redis
#   url: os.environ/REDIS_URL
```

---

## Quick Config Reference

```yaml
router_settings:
  routing_strategy: simple-shuffle          # recommended for production
  enable_pre_call_checks: true              # required for order parameter to work
  num_retries: 2
  timeout: 30
  allowed_fails: 3                         # cooldown a deployment after 3 failures
  cooldown_time: 30                        # seconds before retrying a cooled-down deployment
```
