# S22 — Schema v19 migration on heterogeneous mesh

## What this asserts

v0.6.3.1 ships schema v19 (was v15 on v0.6.3). Migration ladder is **v15 → v17 → v18 → v19** (release notes §"Schema"). Boot detects schema drift outside `[MIN_SUPPORTED_SCHEMA, MAX_SUPPORTED_SCHEMA]` and emits the **warn** variant: `# ai-memory boot: warn — db schema vN unsupported by binary X.Y.Z`.

This scenario asserts: (a) a heterogeneous mesh with some nodes at v15 and some at v19 produces the warn manifest variant on every node where the mismatch is detectable; (b) bringing all nodes to v19 closes the warn cleanly; (c) the migration ladder runs end-to-end from v15 with all 152 prior memories preserved (the release-notes acceptance bar).

## Surface under test

- Boot manifest `warn` variant
- CLI: `ai-memory boot` (exit 0 in every variant, but stdout differs)
- Migration runner (in-process on first start of v0.6.3.1 against an older DB)

## Setup

- 4-node mesh; phase 1 has nodes A and B at v0.6.3 (schema v15) and nodes C and D at v0.6.3.1 (schema v19).
- A and B have a representative pre-migration DB (152 memories, mixed namespaces, with some `tier="autonomous"` and some `tier="short"` rows; some with embeddings, some without).
- A snapshot of A's pre-migration DB is preserved for cardinality comparison.

## Steps

1. Phase 1: confirm schema_version on each node via `ai-memory boot --format json`. Expect `v15` on A/B and `v19` on C/D.
2. Phase 1: confirm A/B's boot status reports the documented `warn` variant when paired with a v0.6.3.1 binary against a v15 DB (or `info-fallback` if the binary refuses to attach — pin to whichever the release-notes contract specifies).
3. Phase 1: confirm C/D produce `ok` against their own v19 DB.
4. Phase 1: confirm C and D detect that their federation peers (A, B) are at a stale schema and surface that asymmetry via doctor (cross-link to S10).
5. Phase 2: migrate A and B to v19 by upgrading the binary and starting it. Confirm the migration ladder is invoked: v15 → v17 → v18 → v19 (each step traceable in audit log or migration log).
6. Phase 2: cardinality check — count of rows in `memories` after migration equals the pre-migration snapshot count. No silent loss.
7. Phase 2: re-run `ai-memory boot --format json` on A and B; assert `ok` and `schema_version=v19`.
8. Phase 2: re-run cross-mesh boot agreement (cross-link to S9); expect green.

## Pass criteria

- Phase 1: warn variant fires on the mismatched nodes, never silent.
- Phase 1: doctor surfaces the schema asymmetry from the v19 nodes' perspective.
- Phase 2: migration completes without error; intermediate steps v17 / v18 / v19 traceable.
- Phase 2: row-count equality across migration; release notes' "all 152 memories preserved" claim holds for the test fixture.
- Phase 2: post-migration boot status `ok` on every node; mesh-wide schema_version agreement (cross-link S9).

## Fail modes

- Mismatched node returns `ok` instead of `warn` (silent absorb of stale schema).
- Migration drops or duplicates rows.
- Migration skips a step in the ladder (e.g. v15 → v19 directly, leaving column defaults wrong).
- Doctor does not surface the asymmetry from the v19 nodes' view.

## Expected verdict on v0.6.3.1

`GREEN`. The migration ladder is acceptance-tested per release notes (49+ integration tests cover boot + lifecycle + dispatch).

## References

- Release notes — [`v0.6.3.1.md`](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/releases/v0.6.3.1.md) §"Schema" and §"Migration notes"
- ROADMAP2 §7.2 — [v0.6.3.1 scope](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#72-v0631--honesty-patch--recovered-commitments--doc-currency--q2-2026-4-weeks)
- Related: S9 (boot manifest agreement), S10 (doctor cross-node), S19 (archive preserves data on schema migration)
