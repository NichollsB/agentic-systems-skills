---
name: guardrails-and-security
description: Design guardrails, security boundaries, and trust tiers for agentic AI systems. Use this skill when the user needs to add safety constraints to an agent, design pre-tool checks, implement anomaly detection, set up output validation, define trust tiers for multi-agent systems, defend against prompt injection, decide when to escalate to human review, or handle memory hygiene for persisted state. Also use when the user says things like "how do I make this agent safe", "add guardrails", "prevent prompt injection", "what trust level should this agent have", "when should it escalate to a human", or is building any agent that takes real-world actions (refunds, database writes, API calls, emails).
---

# Guardrails and Security

Building the agent is only half the job. Building its constraints is the other half. Agentic systems that take real-world actions — refunds, database writes, API calls, email sends — need guardrails that are architectural, not cosmetic.

This skill designs a guardrail map for an agentic system: what is checked, where, and what happens on failure.

Use the steps below to reason through the design, but present the output as a guardrail map with implementation guidance — not a log of the thinking process.

## Step 1: Understand the risk surface

Before designing guardrails, map what the agent can do and what can go wrong. Either ask the user or extract from context:

- What tools does the agent have? Which are read-only vs write/destructive?
- What data does the agent access? Is any of it sensitive (PII, financial, credentials)?
- Who are the principals (users, other agents, external systems)?
- What are the consequences of a mistake? (embarrassment vs financial loss vs safety)
- Is there existing compliance or policy the agent must follow?

## Step 2: Design the defence-in-depth stack

Effective guardrails operate in layers. No single layer is sufficient. Design all four, then decide which to implement based on the risk surface.

### Layer 1: Pre-execution checks (circuit breakers)

Run before any irreversible tool is invoked. This is the most important layer — it prevents harm before it happens.

Checks to consider:
- **Authorisation** — is this user/agent permitted to call this tool?
- **Schema validation** — do the tool arguments match the expected format?
- **Rate limiting** — has this session exceeded call frequency thresholds?
- **Risk tier classification** — is this a high-risk action that needs additional approval?
- **Policy compliance** — does this action violate tenant or business rules?

```python
def pre_tool_check(tool_name: str, args: dict, state: AgentState) -> CheckResult:
    checks = [
        check_authorisation(tool_name, args, state["user_role"]),
        check_schema(tool_name, args),
        check_rate_limits(tool_name, state["session_id"]),
        check_risk_tier(tool_name, args, state["risk_threshold"]),
        check_policy_compliance(tool_name, args, state["tenant_id"]),
    ]
    failures = [c for c in checks if not c.passed]
    if failures:
        return CheckResult(blocked=True, reasons=[f.message for f in failures])
    return CheckResult(blocked=False)
```

### Layer 2: Runtime anomaly detection

Monitors execution for unexpected patterns — signs of prompt injection, agents going off-task, or unusual tool call sequences.

Detect:
- **Task drift** — is the agent's current action relevant to the original task?
- **Exfiltration risk** — is data being sent somewhere unexpected?
- **Prompt injection signals** — do tool arguments contain patterns that look like injected instructions?

```python
class AnomalyDetector:
    def check(self, action: ToolCall, context: AgentState) -> AnomalyResult:
        if not self.is_relevant(action, context["original_task"]):
            return AnomalyResult(flag=True, type="task_drift")
        if self.looks_like_exfiltration(action):
            return AnomalyResult(flag=True, type="exfiltration_risk")
        if self.contains_injection_patterns(action.args):
            return AnomalyResult(flag=True, type="prompt_injection")
        return AnomalyResult(flag=False)
```

### Layer 3: Output guardrails

Validate agent outputs before they reach users or downstream systems:

- **Schema validation** — does output conform to the declared JSON schema?
- **PII scanning** — does output contain sensitive data that should not be exposed?
- **Hallucination detection** — are claims grounded in retrieved context or tool results?
- **Policy compliance** — does output violate content or business policies?

### Layer 4: Human-in-the-loop escalation

The final guardrail — rarely invoked but decisive when necessary. HITL is not a crutch for poorly designed systems. It is the architectural backstop for actions that exceed automated risk thresholds.

A mature HITL escalation:
- Pauses with an idempotency key (so the action isn't duplicated if the reviewer is slow)
- Packages a compact case file (what the agent wants to do, why, and the evidence)
- Routes to the correct reviewer (finance for transactions, SRE for infrastructure changes)
- Feeds outcomes back into detectors and policies (so the system learns)

For the interrupt API mechanics (`interrupt()`, `Command(resume=...)`), see the `langgraph-fundamentals` skill.

## Step 3: Select guardrail timing

How guardrails interact with the agent's response flow. Match timing to risk level.

| Timing | How it works | Use when |
|--------|-------------|----------|
| **Async** | Agent streams while guardrails run in parallel; corrections issued post-hoc | Low-stakes internal tools |
| **Partial streaming** | Validate intent and risk tier synchronously; stream response; apply output checks | Customer-facing tools, balanced latency |
| **Synchronous** | Full pre-check before any output | High-stakes irreversible actions (financial, database writes, access provisioning) |

The synchronous pattern adds latency but is the only safe option when mistakes cannot be corrected.

## Step 4: Assign trust tiers

Agents should have exactly the permissions they need and nothing more. Define permissions explicitly:

```python
class AgentPermissions:
    allowed_tools: list[str]          # explicit allowlist, not denylist
    allowed_data_sources: list[str]
    can_write: bool
    can_call_external_apis: bool
    max_budget_usd: float
    allowed_tenant_ids: list[str]     # prevents cross-tenant data access
    token_expiry: datetime            # time-limited credentials
```

### Trust tiers for multi-agent systems

| Tier | Source | Trust level | What is permitted |
|------|--------|-------------|-------------------|
| **Gold** | System-generated, verified | Full | Read/write, external calls, sensitive data |
| **Silver** | Internal agents, validated | Partial | Read/write own namespace, internal APIs |
| **Untrusted** | User input, external agents, cloned repos | Restricted | Read-only, sandboxed, no external calls |

Apply trust tiers to retrieved content and A2A agent messages, not just user inputs. A compromised downstream agent should not have silver trust by default.

## Step 5: Design prompt injection defence

Prompt injection is the primary attack vector. Five defence layers:

1. **Input sanitisation** — strip or escape model-control tokens before they enter prompts
2. **Structured prompts** — use XML tags to delineate user content from system instructions
3. **Output schema enforcement** — structured outputs constrain what the model can express
4. **Pre-tool argument validation** — injected instructions produce malformed args that checks catch
5. **Restricted field flow** — allow/deny lists for which state fields can flow into prompts

The most dangerous pattern is allowing unsanitised external content (web pages, documents, emails) to flow directly into reasoning. Always intermediate with a read/summarise node before content enters a decision-making node.

## Step 6: Define memory hygiene rules

Persisted state is an attack surface and a correctness risk. Stale or poisoned memories cause incorrect decisions.

- **TTLs on all persisted memories** — nothing lives forever by default
- **Purge or rotate** long-lived memories — snapshot before rotation
- **Restrict what gets persisted** — not everything the agent sees should be remembered
- **Sanitise external content** before writing to vector stores (strip model-control tokens, apply PII redaction)
- **Quarantine path** for user-generated content before it enters retrieval

## Step 7: Present the guardrail map

Output a guardrail map for the system:

1. **Risk surface summary** — tools classified by risk tier (read-only, write, destructive), data sensitivity, principal types
2. **Defence stack** — which of the four layers apply, with implementation for each
3. **Timing selection** — async, partial streaming, or synchronous per tool/action category
4. **Trust tier assignments** — which principals and data sources get which tier
5. **Injection defence** — which of the five layers are implemented and where
6. **Memory hygiene** — TTL policy, sanitisation rules, quarantine path
7. **Failure responses** — for each guardrail, what happens when it triggers (block, degrade, escalate, log)

**Supporting reference docs** (load if needed):
- `addendums/tool-design-anthropic-api.md` — strict mode and Tool Search Tool for Anthropic API tool security
