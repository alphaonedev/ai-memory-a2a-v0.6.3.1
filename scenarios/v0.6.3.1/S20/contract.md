# S20 — G6 `on_conflict` policy under concurrent writes

## What this asserts

Audit finding **G6** ([ROADMAP2 §5.4](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#54-substantive-gaps-and-bugs-priority-ordered)) — pre-v0.6.3.1, `UNIQUE(title, namespace)` plus an INSERT-on-conflict path **silently mutated** the existing row instead of erroring. v0.6.3.1 adds an `on_conflict: "error" | "merge" | "version"` parameter to `memory_store`. New-client default is `error`; legacy `merge` is opt-in ([ROADMAP2 §7.2](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#72-v0631--honesty-patch--recovered-commitments--doc-currency--q2-2026-4-weeks)).

This scenario asserts deterministic outcome under each policy when two agents on different mesh nodes concurrently write the same `(title, namespace)` key.

## Surface under test

- MCP tool: `memory_store(title, content, namespace, on_conflict)`
- Policies: `error` (default new clients), `merge` (legacy opt-in), `version` (new — append-as-new-version)
- Schema constraint: `UNIQUE(title, namespace)`

## Setup

- 4-node mesh, ironclaw / mTLS, schema v19.
- Two test agents pre-configured: agent-X on node-A, agent-Y on node-B.
- Synchronisation primitive (e.g. shared timestamp barrier) so the two writes hit roughly simultaneously.

## Steps

1. Probe `error` policy:
   - agent-X writes `(title="dup-key", namespace="probe")` first.
   - agent-Y attempts the same key with `on_conflict="error"`.
   - Assert exactly one write succeeds; the other returns a documented conflict error code.
2. Probe `merge` policy:
   - Reset state.
   - agent-X writes the key; agent-Y opts into `on_conflict="merge"` and writes a different content body.
   - Assert single row remains; content reflects merge semantics documented in release notes.
3. Probe `version` policy:
   - Reset state.
   - agent-X writes; agent-Y opts into `on_conflict="version"`.
   - Assert two rows visible (or one row + one versioned successor — per release-notes contract); `memory_list` shows both.
4. Probe **concurrent** writes:
   - Reset state.
   - agent-X and agent-Y race on the barrier with `on_conflict="error"`.
   - Assert exactly one succeeds, one fails — never both succeed silently, never both fail.
5. Repeat the concurrent race 50 times to gain statistical confidence in the determinism claim.

## Pass criteria

- `error` policy: second write fails with a conflict error code; first write's content unchanged.
- `merge` policy: documented merge semantics observed; single row.
- `version` policy: prior row preserved, new version recorded.
- Concurrent race: exactly one success, one failure across all 50 trials. Win-rate per node should not be skewed beyond plausible scheduler variance.
- Default for a new client (no `on_conflict` argument) behaves as `error` — the legacy silent-merge is no longer reachable without explicit opt-in.

## Fail modes

- Both writes silently succeed and one row's content is overwritten (legacy G6 behaviour).
- `error` policy returns 200 OK with a mutated row.
- `merge` policy creates two rows (constraint violation that DB caught — not what the policy promises).
- Concurrent race produces both-succeed or both-fail outcomes.
- Default policy is still `merge` (release patch incomplete on the default).

## Expected verdict on v0.6.3.1

`GREEN`. G6 is in the v0.6.3.1 cutline (slip-deferable but documented in-scope when cutline does not bite).

## References

- ROADMAP2 §5.4 G6 — [on_conflict gap](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#54-substantive-gaps-and-bugs-priority-ordered)
- ROADMAP2 §7.2 — [G6 absorption](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#72-v0631--honesty-patch--recovered-commitments--doc-currency--q2-2026-4-weeks)
- Release notes — [`v0.6.3.1.md`](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/releases/v0.6.3.1.md)
- Related: S18 (G4 dim integrity), S24 (#318 MCP-stdio fanout)
