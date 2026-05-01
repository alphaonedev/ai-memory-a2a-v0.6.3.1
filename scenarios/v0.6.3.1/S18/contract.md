# S18 — G4 embedding-dim integrity under cross-agent writes

## What this asserts

Audit finding **G4** ([ROADMAP2 §5.4](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#54-substantive-gaps-and-bugs-priority-ordered)) — pre-v0.6.3.1, mixed embedding dimensions (e.g. 384 vs 768) were silently tolerated at the schema level; cosine similarity returned `0.0` on mismatch. v0.6.3.1 adds an `embedding_dim` column to `memories`, refuses mixed-dim writes at the boundary, and surfaces a `dim_violations` count in `memory_stats` ([ROADMAP2 §7.2](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#72-v0631--honesty-patch--recovered-commitments--doc-currency--q2-2026-4-weeks)).

This scenario asserts that a cross-agent write attempting to insert a memory with a non-conforming embedding dimension is refused at every node in the mesh, that the refusal is consistent (same error code), and that the `dim_violations` counter is observable from any node.

## Surface under test

- MCP tool: `memory_store(content, embedding=[...])` with deliberate dim mismatch
- MCP tool: `memory_stats()` (reports `dim_violations`)
- HTTP endpoint: `POST /api/v1/memories` with non-conforming embedding payload
- Schema column: `memories.embedding_dim`

## Setup

- 4-node mesh, ironclaw / mTLS, schema v19.
- Mesh canonical embedding dim: 768 (nomic-embed-text-v1.5).
- Two test agents: agent-X (correctly produces 768-d vectors), agent-Y (deliberately produces 384-d vectors).
- Pre-seeded with ~10 valid 768-d memories per node.

## Steps

1. From agent-X on node-A: `memory_store` a 768-d vector; assert success and that the row's `embedding_dim` column reads `768`.
2. From agent-Y on node-A: `memory_store` a 384-d vector; assert refusal with a documented error (e.g. `dim_mismatch`) and that no row was written.
3. Repeat the agent-Y refusal probe on B / C / D; assert symmetric refusal everywhere.
4. After each refusal, query `memory_stats()` on the same node; assert `dim_violations` incremented by 1.
5. From node-A, query `memory_stats()` for *every* peer (via federation peer endpoint); assert the per-peer `dim_violations` count is exposed and matches each peer's local count.
6. Run a recall query that would naturally have rejected the 384-d row had it been inserted; confirm it returns the expected 768-d corpus (no silent inclusion).

## Pass criteria

- Refusal is symmetric across all four nodes for the 384-d write.
- Documented error code returned (no opaque 500).
- `embedding_dim` column populated correctly on accepted writes.
- `dim_violations` counter increments on every refusal; observable per-node and via federation peer view.
- No 384-d row appears in the database after the refusals.
- Recall corpus unchanged.

## Fail modes

- Any node accepts the 384-d write (G4 fix incomplete on that node).
- `dim_violations` counter does not increment.
- Counter exposed on local node but not via federation peer view (asymmetric surfacing — cross-link to S16 capabilities honesty).
- Cosine returns `0.0` instead of refusing (legacy silent-tolerate behaviour).
- 384-d row silently leaks into recall.

## Expected verdict on v0.6.3.1

`GREEN`. G4 is in the v0.6.3.1 cutline-keep set per ROADMAP2 §7.2 cutline.

## References

- ROADMAP2 §5.4 G4 — [embedding-dim gap](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#54-substantive-gaps-and-bugs-priority-ordered)
- ROADMAP2 §7.2 — [G4 absorption](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#72-v0631--honesty-patch--recovered-commitments--doc-currency--q2-2026-4-weeks)
- Release notes — [`v0.6.3.1.md`](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/releases/v0.6.3.1.md)
- Related: S19 (G5 archive/restore), S20 (G6 on_conflict), S21 (G13 endianness)
