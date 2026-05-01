# S13 — `ai-memory audit verify` tamper-evident hash chain

## What this asserts

The v0.6.3.1 audit log is hash-chained line-by-line: every event's `prev_hash` field equals the prior event's `self_hash`. `ai-memory audit verify` walks this chain and exits `0` on integrity, `2` on tamper detection (release notes §"What's new"). In a federated mesh, each node maintains its own audit chain; this scenario asserts that (a) every node's chain verifies independently, (b) deliberate corruption at one node is detected by that node's `audit verify`, and (c) peers refuse to absorb a contaminated audit (i.e. no cross-node "trust" makes a tampered chain appear clean).

## Surface under test

- CLI: `ai-memory audit verify` (exit `0` integrity / `2` tamper)
- CLI: `ai-memory audit tail [N]`, `ai-memory audit path`
- Audit schema v1 documented in [`docs/security/audit-trail.md`](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/security/audit-trail.md)
- Hash-chain fields on every event: `prev_hash`, `self_hash`, `sequence`

## Setup

- 4-node mesh, ironclaw / mTLS, `[audit] enabled = true` on every node.
- A small workload runs on each node generating ~50 audit events (mix of `recall` / `store` / `link` / `promote` / `delete`).
- A test fixture is prepared that knows how to corrupt a single line of an audit log file out-of-band (root access on a single node only).

## Steps

1. Run the seed workload on every node; let audit events accumulate.
2. On each node: `ai-memory audit verify`; capture exit code. Assert all four return `0`.
3. On each node: `ai-memory audit tail 10` and confirm `prev_hash` of line N == `self_hash` of line N-1 spot-check.
4. Take a snapshot of node-A's audit file size and last sequence number.
5. Tamper: mutate a single byte in the middle of node-A's audit log file (out-of-band root write).
6. Re-run `ai-memory audit verify` on node-A; assert exit code `2` and that error output names the affected sequence number.
7. On nodes B / C / D: re-run `audit verify`; assert each still exits `0` (their chains are independent of A's corruption).
8. Restore node-A's audit log from the snapshot (test cleanup).

## Pass criteria

- All four nodes' `audit verify` returns exit `0` before tampering.
- Spot-check of `prev_hash` chain holds at every node.
- After tampering node-A's log, `ai-memory audit verify` on node-A returns exit `2`.
- B / C / D continue returning `0` post-tamper (no cross-node contamination).
- The error output names the affected sequence number (operator-actionable signal).
- Round-trip restoration returns node-A to exit `0`.

## Fail modes

- Pre-tamper node returns `2` (chain already broken — release defect).
- Tampered node returns `0` (verifier ignores corruption — security-critical).
- Tamper on A causes B / C / D to also return `2` (peers absorbing A's chain — design violation).
- Exit-code contract not honoured (e.g. tamper produces exit `1` instead of `2`).

## Expected verdict on v0.6.3.1

`GREEN`. The audit verify exit-code contract is one of the strictest invariants in the v0.6.3.1 release.

## References

- Release notes — [`v0.6.3.1.md`](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/releases/v0.6.3.1.md)
- Audit trail spec — [`docs/security/audit-trail.md`](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/security/audit-trail.md)
- Related: S14 (operational logs), S17 (webhook fanout)
