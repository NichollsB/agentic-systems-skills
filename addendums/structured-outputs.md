# Structured Outputs for Agentic Systems

Structured outputs constrain LLM responses to follow specific schemas, guaranteeing valid, parseable output. This eliminates `JSON.parse()` errors, type mismatches, and missing fields — critical for agent tool calls and inter-node communication.

This addendum covers provider-specific implementation. For general tool design patterns, see the community `tool-design` skill.

## When to use structured outputs in agents

- **Tool parameters** — guarantee the LLM sends correctly-typed arguments to tools (no `"2"` instead of `2`)
- **Inter-node communication** — enforce schemas at stage boundaries in pipelines (e.g., analyser → decision agent)
- **Data extraction** — pull structured data from documents, emails, or user input
- **Validation node output** — ensure quality scores, error lists, and classifications conform to expected shapes
- **Planning nodes** — enforce plan structure (step lists, dependency graphs) so downstream execution can parse reliably

## Two approaches (both providers)

| Approach | Use when | Anthropic | OpenAI |
|----------|----------|-----------|--------|
| **Structured response** | Controlling the LLM's direct output format | `output_config.format` with `json_schema` | `response_format` with `json_schema` |
| **Strict tool use** | Validating tool/function call parameters | `strict: True` on tool definition | `strict: true` on function definition |

Use both together when the agent needs to call tools with validated parameters AND return structured responses.

## Anthropic (Claude)

### Structured responses

```python
from pydantic import BaseModel
from anthropic import Anthropic

class PlanOutput(BaseModel):
    steps: list[str]
    estimated_duration: str
    confidence: float

client = Anthropic()
response = client.messages.parse(
    model="claude-sonnet-4-5-latest",
    max_tokens=1024,
    output_format=PlanOutput,
    messages=[{"role": "user", "content": "Plan a research approach for..."}],
)
plan = response.parsed_output  # typed PlanOutput, guaranteed valid
```

### Strict tool use

```python
tools = [{
    "name": "search_database",
    "description": "Query the internal knowledge base",
    "strict": True,  # guarantees schema conformance
    "input_schema": {
        "type": "object",
        "properties": {
            "query": {"type": "string"},
            "max_results": {"type": "integer"},
            "filters": {
                "type": "object",
                "properties": {
                    "date_after": {"type": "string", "format": "date"},
                    "category": {"type": "string", "enum": ["research", "engineering", "product"]}
                },
                "additionalProperties": False
            }
        },
        "required": ["query"],
        "additionalProperties": False
    }
}]
```

Without `strict: True`, a booking tool asking for `passengers: int` might receive `passengers: "two"`. With it, schema violations are impossible.

### LangGraph integration

```python
from langchain_anthropic import ChatAnthropic

llm = ChatAnthropic(model="claude-sonnet-4-5-latest")

# In a node — structured output via with_structured_output
def plan_node(state: AgentState) -> dict:
    result = llm.with_structured_output(PlanSchema).invoke(state["messages"])
    return {"plan": result}  # typed, validated
```

### Anthropic-specific notes

- Available on Claude Opus 4.6, Sonnet 4.6/4.5, Haiku 4.5
- JSON schemas are cached for 24 hours for optimisation (Zero Data Retention still applies to prompts/responses)
- SDKs automatically transform unsupported constraints (`minimum`, `maximum`, `minLength`) into descriptions while validating responses against the original schema
- `additionalProperties: false` is required on all objects

## OpenAI

### Structured responses

```python
from pydantic import BaseModel
from openai import OpenAI

class PlanOutput(BaseModel):
    steps: list[str]
    estimated_duration: str
    confidence: float

client = OpenAI()
response = client.responses.parse(
    model="gpt-4.1",
    input=[{"role": "user", "content": "Plan a research approach for..."}],
    text={"format": {"type": "json_schema", "schema": PlanOutput}},
)
plan = response.output_parsed  # typed PlanOutput
```

### Strict function calling

```python
tools = [{
    "type": "function",
    "function": {
        "name": "search_database",
        "description": "Query the internal knowledge base",
        "strict": True,
        "parameters": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "max_results": {"type": "integer"}
            },
            "required": ["query"],
            "additionalProperties": False
        }
    }
}]
```

### OpenAI-specific notes

- Available on GPT-4o, GPT-4o-mini, GPT-4.1 and later
- Older models (GPT-4-turbo, GPT-3.5) support JSON mode but not strict schema adherence
- Always prefer structured outputs over JSON mode when the model supports it
- Supports Zod schemas in TypeScript SDK

## Structured outputs vs JSON mode

| | Structured outputs | JSON mode |
|---|---|---|
| **Valid JSON** | Guaranteed | Guaranteed |
| **Schema adherence** | Guaranteed | Not guaranteed |
| **Type safety** | Full | None |
| **Retry needed** | Never for schema violations | Sometimes |

Always use structured outputs over JSON mode when available.

## Schema limitations (both providers)

Both providers support a subset of JSON Schema. Unsupported features:
- `minimum`, `maximum` — describe in field descriptions instead
- `minLength`, `maxLength` — describe in field descriptions instead
- `pattern` (regex validation)
- Circular references / `$ref`
- Complex format strings beyond common types (`date`, `date-time`, `email`)

SDKs handle this automatically — they strip unsupported constraints, add them to descriptions, and validate responses against the original schema client-side.

## Important considerations

### When using both structured responses AND strict tool use together
- Claude may call tools first (`stop_reason: "tool_use"`) or respond with JSON (`stop_reason: "end_turn"`)
- You must handle both content types — check `response.stop_reason` to determine which path was taken
- This is the most common pattern in agents: tools have strict schemas AND the final response has a structured format

### Data retention (Anthropic)
Prompts and responses use Zero Data Retention (ZDR), but **the JSON schema itself is cached for up to 24 hours** for optimisation. If your schema structure contains sensitive information (field names, enum values), be aware it persists briefly even with ZDR.

### `additionalProperties: false` is mandatory
Both providers require `additionalProperties: false` on all objects for strict mode. Without it, the model can add arbitrary fields. The SDKs add this automatically when using Pydantic/Zod, but if you write raw JSON schemas, include it explicitly on every object — including nested ones.

### SDK schema transformation
The SDKs do two things that matter:
1. **Strip unsupported constraints** from the schema sent to the API (e.g. `minimum: 100` becomes a plain integer)
2. **Validate responses client-side** against the original schema with all constraints

This means the API guarantees structural conformance (correct types, required fields, valid enums) but the SDK adds constraint validation (min/max values, string lengths). If you bypass the SDK and use raw API calls, you lose the constraint validation.

### Java-specific: generic type erasure
Type information works in class metadata but not in local variables. Use class references directly rather than generic types when defining output schemas.

### API migration (Anthropic)
`output_format` has moved to `output_config.format`. The old parameter still works during transition but should be migrated. Beta headers (`structured-outputs-2025-11-13`) are no longer required.

## Best practices for agents

1. **Use Pydantic models** (Python) or Zod schemas (TypeScript) — the SDKs handle JSON Schema conversion and client-side validation
2. **Define schemas for inter-node contracts** — not just tool calls. If node A's output feeds node B, define the shape
3. **Start strict, relax if needed** — `strict: True` on all tools by default. Only remove if you need flexibility
4. **Keep schemas focused** — one schema per concern. Don't merge unrelated outputs into one mega-schema
5. **Use enums for constrained choices** — `"category": {"type": "string", "enum": ["a", "b", "c"]}` prevents hallucinated categories
6. **Handle both stop reasons** when combining structured responses with tools — don't assume the response will always be one or the other

Sources:
- [Anthropic Structured Outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)
- [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
