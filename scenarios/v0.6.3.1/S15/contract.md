# S15 — R1 `budget_tokens` recall determinism across the federation

## What this asserts

`memory_recall` gains a `budget_tokens` parameter in v0.6.3.1 — the recovered commitment **R1** from [ROADMAP2 §7.2](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#72-v0631--honesty-patch--recovered-commitments--doc-currency--q2-2026-4-weeks). Per [§9.1](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#9-the-three-highest-leverage-moves) it is "the killer feature, no competitor has this" and "the highest-leverage recovery in the plan." Token-counted greedy fill returns as many ranked memories as fit in `budget_tokens`.

This scenario asserts that the same `(query, budget_tokens, namespace)` triple submitted to any federated peer returns the same ranked head: same memory IDs in the same order. Drift between peers — even by a single position swap in the head — is a test fail. There is no similarity tolerance.

## Surface under test

- MCP tool: `memory_recall(query, budget_tokens, namespace)`
- HTTP endpoint: `POST /api/v1/recall` with the equivalent body
- Token counting: documented in v0.6.3.1 ROADMAP2 §7.2 ("token-counted greedy fill")

## Setup

- 4-node mesh, ironclaw / mTLS, schema v19.
- Shared corpus of ~200 memories of varied length (50–2000 tokens), seeded on node-A and propagated via federation. Wait for sync convergence before testing.
- Test budgets: 256, 1024, 4096 tokens. Test queries: a fixed set of 5 phrasings touching varied semantic targets.

## Steps

1. Seed the 200-memory fixture on node-A and let federation sync. Confirm cardinality on every node before recall.
2. For each `(query, budget)` pair (5 × 3 = 15 cases):
   - Run `memory_recall` on node-A; capture ranked head as `[(id, score), ...]`.
   - Repeat on B / C / D against the shared store.
3. Assert byte-equal head across all four nodes for every case.
4. Run a "below budget" sanity case: a budget so small only one memory fits; confirm only one memory is returned, and it is identical on all four nodes.
5. Run an "above corpus" case: a budget large enough to admit the entire corpus; confirm full ranked list is identical across nodes.

## Pass criteria

- For every `(query, budget)` case, all four nodes return the same ordered ID list.
- Cumulative token count of the returned set is `<= budget_tokens` on every node, every case.
- Score values agree (within float-equality tolerance documented for the recall path).
- Below-budget edge case returns exactly one memory, identical across nodes.
- Above-corpus edge case returns the full corpus in identical order.

## Fail modes

- Two nodes return the same memory IDs but in different order (greedy-fill non-determinism).
- One node returns fewer memories than another for the same budget (token-count drift).
- Returned set exceeds `budget_tokens` (contract violation).
- Federation sync incomplete at test start (cross-link to S22 schema migration).

## Expected verdict on v0.6.3.1

`GREEN`. R1 is in the v0.6.3.1 cutline-keep set and is the centerpiece of the release per ROADMAP2 §9.1.

## References

- ROADMAP2 §7.2 R1 — [`budget_tokens` recovery](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#72-v0631--honesty-patch--recovered-commitments--doc-currency--q2-2026-4-weeks)
- ROADMAP2 §9.1 — [highest-leverage moves](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#9-the-three-highest-leverage-moves)
- Release notes — [`v0.6.3.1.md`](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/releases/v0.6.3.1.md)
- Related: S12 (wrap consistency), S16 (capabilities honesty)
