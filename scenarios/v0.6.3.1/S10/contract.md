# S10 — `ai-memory doctor` cross-node section agreement

## What this asserts

`ai-memory doctor` is the v0.6.3.1 promotion of recovered-commitment **R7** (see [ROADMAP2 §7.2](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#72-v0631--honesty-patch--recovered-commitments--doc-currency--q2-2026-4-weeks)). The 7-section health dashboard (Storage / Index / Recall / Governance / Sync / Webhook / Capabilities) must produce consistent verdicts across a homogeneous mesh, modulo bounded in-flight delta on the live counters (`Storage` row count, `Sync` lag).

This scenario asserts: (a) every node's doctor output parses; (b) the *categorical* fields (severity, status flags) agree on Storage / Index / Recall / Sync; (c) when one node's capability set differs (e.g. embedder unloaded), the doctor surfaces it from every node — the cross-mesh honesty principle from §5.3 capabilities theater.

## Surface under test

- CLI: `ai-memory doctor --format json`
- Exit codes: `0` healthy / `1` warning / `2` critical (release notes §"What's new")

## Setup

- Default 4-node `ironclaw / mTLS` mesh, all v0.6.3.1.
- A short pre-step writes a few memories to give Storage / Index / Recall non-trivial state.
- One variant of this run: deliberately stop the embedder on node-D before invoking doctor on all four — the asymmetric-warning probe.

## Steps

1. Seed the mesh with a small fixture corpus (~20 memories across 3 namespaces).
2. Run `ai-memory doctor --format json` on each of A / B / C / D; capture stdout + exit code.
3. Parse the seven section blocks from each node's JSON.
4. Compare per-section severity across nodes. Tolerate row-count delta on `Storage`/`Sync` if `|delta| <= in_flight_tolerance` (default 5).
5. For the asymmetric-warning variant: assert that node-D's `Capabilities` section reports the embedder as down, and that A/B/C's `Sync` section flags D as degraded.
6. Emit per-node section table + agreement matrix as JSON.

## Pass criteria

- All nodes return exit code `0` or `1` (never `2`) in the baseline run.
- `Storage` / `Index` / `Recall` severity matches across all four nodes.
- `Sync` section reports the same peer set on every node.
- In the asymmetric-warning variant: node-D self-reports the missing embedder; peers flag node-D as degraded — nothing is silently absorbed.
- `Governance` / `Webhook` / `Capabilities` severity matches across nodes (excepting the deliberate asymmetry).

## Fail modes

- One node reports `Storage CRIT` while peers report `OK` (suggests Issue [#507](https://github.com/alphaonedev/ai-memory-mcp/issues/507) tilde-expansion failure on that node — cross-link to S23).
- Mesh has an embedder-down node but peers' `Sync` says `OK` (silent absorb — capabilities theater).
- Doctor section count != 7.
- JSON schema mismatch between nodes (suggests binary drift — cross-link to S9).

## Expected verdict on v0.6.3.1

`GREEN`. R7 is in the v0.6.3.1 cutline-keep set; cross-node consistency is the cert criterion.

## References

- Release notes — [`v0.6.3.1.md`](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/releases/v0.6.3.1.md)
- ROADMAP2 §7.2 R7 — [doctor recovery](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#72-v0631--honesty-patch--recovered-commitments--doc-currency--q2-2026-4-weeks)
- ROADMAP2 §5.3 — [Capabilities-JSON theater](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#53-capabilities-json-theater-advertised-not-implemented-in-v063)
- Related: S9 (boot manifest), S16 (capabilities honesty), S23 (#507 tilde failure)
