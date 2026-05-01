# S9 — `ai-memory boot` multi-node manifest agreement

## What this asserts

Run `ai-memory boot --format json` on each of the four mesh nodes against the same shared store. The 5-field diagnostic manifest (`version`, `db`, `schema_version`, `tier`, `latency`) must agree on the three identity fields (`version`, `schema_version`, `tier`) across every node. `db` path is per-node by design and may differ. `latency` is per-node and not constrained by this scenario.

The boot primitive is documented as "always-visible, never silent" in the [v0.6.3.1 release notes](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/releases/v0.6.3.1.md). Disagreement on any of the three identity fields would mean a node is running a different binary than its peers — silent vendor drift in a mesh that is supposed to be homogeneous.

## Surface under test

- CLI: `ai-memory boot --format json --quiet`
- Status variants observed: `ok` / `info-fallback` / `info-empty` / `warn` (release notes §"What's new")

## Setup

- 4-node `ironclaw / mTLS` mesh (default cell). All nodes pinned to the [`v0.6.3.1`](https://github.com/alphaonedev/ai-memory-mcp/releases/tag/v0.6.3.1) tag.
- Each node initialised with the same `config.toml` profile (boot enabled, audit enabled).
- Schema migrated to `v19`.

## Steps

1. SSH (or `docker exec`) into each of the four nodes.
2. Run `ai-memory boot --format json --quiet` on every node; capture stdout.
3. Parse each JSON manifest and extract `version`, `schema_version`, `tier`.
4. Compute pairwise equality of the three identity fields across all four nodes.
5. Emit per-node manifest plus the agreement matrix to stdout as JSON.

## Pass criteria

- Every node returns exit code `0`.
- Every node's manifest parses as valid JSON.
- `version` field is identical on all four nodes.
- `schema_version` is identical on all four nodes (expected: `v19`).
- `tier` is identical on all four nodes (e.g. `autonomous`).
- Status variant on every node is `ok` or `info-empty` — never `warn`.

## Fail modes

- One node reports a different `schema_version` (suggests migration drift — see S22).
- `tier` differs between nodes (one node missing the embedder; cross-link to S16).
- Any node returns the `warn` variant (db unavailable — note Issue [#507](https://github.com/alphaonedev/ai-memory-mcp/issues/507) is the documented config-tilde failure that produces this; see S23).
- Non-zero exit (boot is contractually exit-0 in every state — release notes "never wedges an agent's first turn").

## Expected verdict on v0.6.3.1

`GREEN`. The boot primitive is the centerpiece of the v0.6.3.1 release; mesh-wide agreement is its baseline contract.

## References

- Release notes — [`v0.6.3.1.md`](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/releases/v0.6.3.1.md)
- ROADMAP2 §7.2 — [v0.6.3.1 scope](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#72-v0631--honesty-patch--recovered-commitments--doc-currency--q2-2026-4-weeks)
- Related: S10 (doctor cross-node), S22 (schema migration), S16 (capabilities honesty)
