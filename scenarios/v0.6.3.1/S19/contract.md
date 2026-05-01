# S19 — G5 archive/restore preserves embeddings cross-agent

## What this asserts

Audit finding **G5** ([ROADMAP2 §5.4](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#54-substantive-gaps-and-bugs-priority-ordered)) — pre-v0.6.3.1, `archived_memories` had **no embedding column**, making archive lossy for vector search; restore reset `tier='long'` + `expires_at=NULL` regardless of the original values. v0.6.3.1 adds `embedding`, `original_tier`, `original_expires_at` columns to `archived_memories`; restore preserves the originals ([ROADMAP2 §7.2](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#72-v0631--honesty-patch--recovered-commitments--doc-currency--q2-2026-4-weeks)).

This scenario asserts the round-trip across the federation: archive on node-A, restore on node-B, and confirm the embedding vector, original tier, and original expiry are preserved byte-for-byte.

## Surface under test

- MCP tools: `memory_archive_*` (`memory_archive_list`, `memory_archive_purge`, `memory_archive_restore`, `memory_archive_stats`)
- Schema columns: `archived_memories.embedding`, `archived_memories.original_tier`, `archived_memories.original_expires_at`

## Setup

- 4-node mesh, ironclaw / mTLS, schema v19.
- Seed corpus with two memory shapes per namespace:
  - shape α: `tier="short"`, `expires_at=<now + 1d>`, embedding present
  - shape β: `tier="autonomous"`, `expires_at=NULL`, embedding present
- Each shape replicated to ~10 memories so we have a population to archive.

## Steps

1. On node-A: archive a known set of α and β memories (record their IDs, embeddings, tiers, expiry).
2. After federation sync, on node-B: `memory_archive_list`; assert the archived memories are visible from B.
3. On node-B: `memory_archive_restore <id>` for each archived ID.
4. After restore, fetch the restored row and:
   - Compare embedding bytewise to the pre-archive snapshot.
   - Confirm `tier` matches the original (`"short"` for α, `"autonomous"` for β).
   - Confirm `expires_at` matches the original.
5. Run `memory_recall` on node-B against a query that should match the restored embeddings; confirm they re-enter recall (lossless restore proof).
6. `memory_archive_stats` on every node; confirm counters consistent across the mesh (within in-flight tolerance).

## Pass criteria

- `archived_memories.embedding` column populated for every archived row.
- After restore on node-B, embedding equals the pre-archive snapshot byte-for-byte.
- `tier` round-trips correctly (no forced `tier='long'` on restore).
- `expires_at` round-trips correctly (no forced `NULL`).
- Recall on node-B retrieves the restored memory by semantic match.
- Mesh-wide stats consistent.

## Fail modes

- Embedding column NULL after archive (legacy lossy archive — fix incomplete).
- Tier reset to `long` on restore (legacy reset bug).
- `expires_at` reset to NULL on restore (legacy reset bug).
- Embedding bytes differ post-restore (encoding regression — cross-link to S21 endianness).
- Recall on node-B misses the restored memory.

## Expected verdict on v0.6.3.1

`GREEN`. G5 is in the v0.6.3.1 cutline (slip-deferable but documented as in-scope on the keep list when the cutline does not bite).

## References

- ROADMAP2 §5.4 G5 — [archive lossy](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#54-substantive-gaps-and-bugs-priority-ordered)
- ROADMAP2 §7.2 — [G5 absorption](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#72-v0631--honesty-patch--recovered-commitments--doc-currency--q2-2026-4-weeks)
- Release notes — [`v0.6.3.1.md`](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/releases/v0.6.3.1.md)
- Related: S18 (G4 dim integrity), S21 (G13 endianness)
