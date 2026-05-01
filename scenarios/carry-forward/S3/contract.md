# S3 — targeted share

## Source

This scenario is carried forward unchanged from the umbrella testbook at
[`alphaonedev/ai-memory-ai2ai-gate`](https://github.com/alphaonedev/ai-memory-ai2ai-gate).
It is run on v0.6.3.1 to verify no regression. Spec authority: umbrella.
Evidence: this repo.

## What this asserts

Agent A can hand-pick a specific subset of memories — by ids,
namespace, or last-N — and direct that subset to agent C. Only
that subset lands on C; nothing more, nothing less. The capability
covers issue-#311 in the upstream tracker and is the foundation of
the umbrella's "specific ids/namespace/last-N set that A invoked
lands on C" assertion.

## Surface under test

- MCP tool `memory_store` (to seed A's corpus)
- MCP tool `memory_link` (records the share edge)
- MCP tool `memory_recall` (C's verification)
- HTTP `POST /api/v1/memories/share` (when invoked over HTTP)

## Setup

- 4-node mesh in steady state.
- Agent A on `${A2A_NODE_A}` has 10 pre-seeded memories; 3 of them
  carry the campaign-specific share marker.
- Agent C on `${A2A_NODE_C}` starts with an empty inbox for the
  share marker.

## Steps

1. Agent A seeds 10 memories on its own namespace; 3 are tagged
   `share-target=charlie`.
2. Agent A invokes the targeted share with the explicit id list
   for those 3 records, addressed to `ai:charlie`.
3. Wait for the umbrella settle window.
4. Agent C calls `memory_recall` for the share marker.
5. Assert C sees exactly the 3 targeted records — not the other 7.

## Pass criteria

- C's recall set has cardinality 3.
- Each record in C's recall is one of the 3 explicitly shared ids.
- The 7 non-targeted records do not appear in C's recall.

## Fail modes

- Over-share: any of the 7 non-targeted records appears on C
  (privacy regression — release-blocker).
- Under-share: fewer than 3 targeted records on C (drop).
- Wrong author: record arrives but stamped with C's id rather
  than A's.

## Expected verdict on v0.6.3.1

`GREEN` — regression. Was green on v0.6.3; must remain green here.

## References

- Umbrella spec: <https://github.com/alphaonedev/ai-memory-ai2ai-gate>
- Umbrella testbook entry: `testbook/S3/`
- Upstream capability issue: `alphaonedev/ai-memory-mcp#311`
