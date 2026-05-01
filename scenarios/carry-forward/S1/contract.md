# S1 — per-agent write + read

## Source

This scenario is carried forward unchanged from the umbrella testbook at
[`alphaonedev/ai-memory-ai2ai-gate`](https://github.com/alphaonedev/ai-memory-ai2ai-gate).
It is run on v0.6.3.1 to verify no regression. Spec authority: umbrella.
Evidence: this repo.

## What this asserts

Every agent on the 4-node mesh can write a memory in its own
`agent_id` namespace and every other agent can recall it through
the authoritative store. Exact payload equivalence holds across the
write → recall round-trip — no field truncation, no tag re-ordering,
no scope coercion. The `agent_id` is immutable: the recalled record
on B and C is stamped with the original author from A, never with
the recaller's identity.

## Surface under test

- MCP tool `memory_store`
- MCP tool `memory_recall`
- HTTP `POST /api/v1/memories` (batch write fallback)
- HTTP `GET /api/v1/memories?agent_id=<id>` (read-back assertion)

## Setup

- 4-node mesh: `${A2A_NODE_A}` (IronClaw, `ai:alice`),
  `${A2A_NODE_B}` (Hermes, `ai:bob`),
  `${A2A_NODE_C}` (IronClaw, `ai:charlie`),
  `${A2A_NODE_D}` (ai-memory authoritative store).
- Mesh in steady state, baseline probes green, mTLS engaged.

## Steps

1. Each of A, B, C calls `memory_store` with a unique payload
   carrying its own `agent_id` and a campaign-tagged content blob.
2. Wait for the federation settle window from the umbrella
   methodology spec.
3. Each agent calls `memory_recall` for the campaign tag and
   collects the returned set.
4. Diff each recalled record against the original payload; assert
   field-level equivalence and `agent_id` preservation.

## Pass criteria

- All three writes return 201 (or MCP `ok`).
- Each agent's recall set contains exactly three records — its own
  and the two peers'.
- Per-record equivalence: content, scope, tags, `agent_id`,
  `created_at` all match the source-of-truth payload.

## Fail modes

- Missing record on any peer (federation drop).
- `agent_id` rewritten to the recaller's id (identity bleed).
- Tag set differs between write and recall (canonicalization bug).
- Recall returns the record but with truncated content (schema
  migration regression — would re-open #v0.6.3 issue class).

## Expected verdict on v0.6.3.1

`GREEN` — regression. Was green on v0.6.3; must remain green here.

## References

- Umbrella spec: <https://github.com/alphaonedev/ai-memory-ai2ai-gate>
- Umbrella testbook entry: `testbook/S1/` in the umbrella repo
- Methodology: `methodology/` in the umbrella repo
