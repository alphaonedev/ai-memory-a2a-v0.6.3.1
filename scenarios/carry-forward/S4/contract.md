# S4 — federation-aware agents

## Source

This scenario is carried forward unchanged from the umbrella testbook at
[`alphaonedev/ai-memory-ai2ai-gate`](https://github.com/alphaonedev/ai-memory-ai2ai-gate).
It is run on v0.6.3.1 to verify no regression. Spec authority: umbrella.
Evidence: this repo.

## What this asserts

Quorum writes (W=2 of N=3) survive across writer-peer pairings.
Agent A writes to the authoritative store on node D; agent B reads
from its closest federation peer (node B's local replica). The
write converges to B's read path within the umbrella's settle
window with no `quorum_not_met` error under steady state. The
assertion is symmetric across writer choice — it must hold for any
writer-reader pairing on the mesh.

## Surface under test

- MCP tool `memory_store` (against node D's authoritative MCP)
- MCP tool `memory_recall` (against each peer's local replica)
- HTTP `GET /api/v1/health/quorum` (state inspection)
- Federation peer config from `[federation]` block

## Setup

- 4-node mesh, mTLS engaged, baseline probes green.
- N=3 federation peers (A, B, C share replicas; D is the
  authoritative coordinator).
- Quorum config: W=2.

## Steps

1. Agent A on `${A2A_NODE_A}` writes a memory directly to the
   coordinator on `${A2A_NODE_D}` via `memory_store`.
2. Capture `t0`.
3. Wait for the umbrella's settle window.
4. Agent B on `${A2A_NODE_B}` issues `memory_recall` against its
   local replica (not the coordinator).
5. Capture `t1`; settle = `t1 - t0`.
6. Repeat the matrix for the (writer, reader) pairings
   (A → B), (A → C), (B → A), (B → C), (C → A), (C → B).

## Pass criteria

- Every pairing converges within the settle window.
- No `quorum_not_met` is returned under steady state.
- The recalled record matches the original payload byte-for-byte.

## Fail modes

- Any pairing exceeds settle window (federation regression).
- `quorum_not_met` returned to a steady-state caller (regression
  on quorum config or peer health).
- Coordinator-only visibility — local replicas missing the record.

## Expected verdict on v0.6.3.1

`GREEN` — regression. Was green on v0.6.3; must remain green here.

## References

- Umbrella spec: <https://github.com/alphaonedev/ai-memory-ai2ai-gate>
- Umbrella testbook entry: `testbook/S4/`
- Upstream ship-gate Phase 2 (federation):
  <https://github.com/alphaonedev/ai-memory-ship-gate>
