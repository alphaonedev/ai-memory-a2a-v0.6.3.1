# S7 — scoping visibility

## Source

This scenario is carried forward unchanged from the umbrella testbook at
[`alphaonedev/ai-memory-ai2ai-gate`](https://github.com/alphaonedev/ai-memory-ai2ai-gate).
It is run on v0.6.3.1 to verify no regression. Spec authority: umbrella.
Evidence: this repo.

## What this asserts

The scope enforcement matrix holds across all (author scope,
caller agent) pairs. The five canonical scopes — `private`,
`team`, `unit`, `org`, `collective` — each have well-defined
visibility rules at recall time, and those rules are honoured
regardless of caller path (MCP vs HTTP) and federation peer.
A `private` write by A is invisible to B and C. A `team` write
is visible only within the configured team. A `collective` write
is visible everywhere on the mesh.

## Surface under test

- MCP tool `memory_store` (with explicit `scope` per record)
- MCP tool `memory_recall` (caller identity drives visibility)
- MCP tool `memory_get` (single-id fetch, must respect scope)
- HTTP `/api/v1/memories?scope=...` filter

## Setup

- 4-node mesh, mTLS engaged.
- Team config: `ai:alice` and `ai:bob` are in the same `team`,
  `ai:charlie` is not.
- Unit / org / collective groupings per umbrella topology spec.

## Steps

1. Agent A writes 5 memories — one per scope (`private`, `team`,
   `unit`, `org`, `collective`).
2. Wait for the umbrella settle window.
3. Each of A, B, C calls `memory_recall` for the campaign tag.
4. Build a 5 × 3 visibility matrix (scope × caller).
5. Compare against the umbrella's expected matrix.

## Pass criteria

- `private` record is visible only to A.
- `team` record is visible to A and B but not to C.
- `unit` record visibility matches the configured unit grouping.
- `org` and `collective` records are visible to all three.
- `memory_get` on a private id from a non-author returns
  not-found / 404, never the record body.

## Fail modes

- Any cell of the visibility matrix differs from the umbrella's
  expected matrix (scope leak — release-blocker).
- `memory_get` returns the record body to a caller that should
  see only "not found".
- HTTP and MCP paths disagree on visibility.

## Expected verdict on v0.6.3.1

`GREEN` — regression. Was green on v0.6.3; must remain green here.

## References

- Umbrella spec: <https://github.com/alphaonedev/ai-memory-ai2ai-gate>
- Umbrella testbook entry: `testbook/S7/`
- Umbrella scope matrix: `methodology/scopes.md` in the umbrella
