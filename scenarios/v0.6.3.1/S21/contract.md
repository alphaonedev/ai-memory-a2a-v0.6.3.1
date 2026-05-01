# S21 — G13 endianness magic byte cross-arch

## What this asserts

Audit finding **G13** ([ROADMAP2 §5.4](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#54-substantive-gaps-and-bugs-priority-ordered)) — pre-v0.6.3.1, stored f32 BLOBs have no endianness marker. Cross-arch federation between x86_64 (little-endian) and arm64 (also little-endian on macOS / Linux but big-endian-capable in principle on other arms) silently corrupted vectors when a hypothetical big-endian peer joined. v0.6.3.1 prefixes stored f32 BLOBs with an endianness magic byte ([ROADMAP2 §7.2](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#72-v0631--honesty-patch--recovered-commitments--doc-currency--q2-2026-4-weeks)).

This scenario asserts that an x86_64 + arm64 mesh exchanges f32 BLOBs across federation without silent corruption: the magic byte is written, read, and respected on cosine compare. We do not require an actual big-endian platform — we exercise the contract by simulating big-endian payloads and asserting refuse-or-rewrite semantics.

This scenario's default cell is `mixed-arch / mTLS` (per `scenarios/v0.6.3.1/README.md`), not `ironclaw_mtls` — the test requires arch heterogeneity in the mesh.

## Surface under test

- Stored embedding BLOB format (with endianness magic byte prefix)
- Federation replication path
- `memory_stats` field surfacing magic-byte-mismatch counts (if surfaced; release notes do not mandate it but G13 absorption likely adds a counter)

## Setup

- 4-node mesh: 2 × x86_64, 2 × arm64. All v0.6.3.1.
- Shared corpus seeded on a single node.
- A test fixture that crafts a "wrong-endian" embedding payload and submits it via the HTTP path to simulate an alien-arch federation peer.

## Steps

1. Seed corpus on node-A (x86_64); let federation propagate to node-C (arm64).
2. On node-C: read a seeded memory; recompute cosine against the original on-host vector; assert magnitude-1 agreement (no corruption).
3. Inverse direction: seed corpus on node-C (arm64); replicate to node-A (x86_64); same cosine check.
4. Inspect raw BLOB on each side: confirm the leading magic byte is present and identical on both arches.
5. Inject a "wrong-endian" payload via the federation HTTP API: assert it is either (a) refused with a documented error, or (b) byte-rewritten to host endianness on ingest with a tracking counter incremented. Whichever the implementation chose is documented in release notes; the test pins to that contract.
6. Recall on each arch against a query that should hit the seed; assert results agree on memory IDs across arches.

## Pass criteria

- Magic byte present on every stored embedding BLOB.
- Cross-arch replication preserves cosine (no silent flip).
- Wrong-endian probe handled per documented contract (refuse or rewrite).
- Recall returns the same ranked head on x86_64 and arm64 nodes (cross-link to S15 determinism).

## Fail modes

- Magic byte absent (G13 fix incomplete).
- Cross-arch cosine returns garbage (silent corruption — the historical failure mode).
- Wrong-endian payload accepted and stored as-is (silent absorb).
- Recall ranking differs between arches (cross-link to S15 fail mode).

## Expected verdict on v0.6.3.1

`GREEN`. G13 is in the v0.6.3.1 audit-finding close-out set. The mesh cell is `mixed-arch / mTLS`; not blocking the standard ironclaw cell, but blocking the "cross-platform" claim in the release notes if it fails.

## References

- ROADMAP2 §5.4 G13 — [endianness gap](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#54-substantive-gaps-and-bugs-priority-ordered)
- ROADMAP2 §7.2 — [G13 absorption](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#72-v0631--honesty-patch--recovered-commitments--doc-currency--q2-2026-4-weeks)
- Release notes — [`v0.6.3.1.md`](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/releases/v0.6.3.1.md)
- Related: S15 (recall determinism), S19 (G5 archive byte-equality)
