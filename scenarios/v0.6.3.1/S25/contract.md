# S25 — Audit hash-chain integrity over a populated log

## What this asserts

ai-memory v0.6.3.1 ships a forensic audit substrate (opt-in, default OFF). When
enabled via `[audit] enabled = true` in `config.toml`, every memory operation
lands a hash-chained JSONL line in `/var/log/ai-memory/audit.jsonl`. The chain
head hash is recomputed deterministically by `ai-memory audit verify` — the
property that makes the trail forensically reproducible.

S25 asserts that under normal operation the substrate works as advertised on a
populated log:

1. With audit enabled on every node (per `scripts/setup_node.sh`'s `[audit]`
   block), driving 25 HTTP writes per node produces a corresponding audit log
   with at least 25 lines on each node.
2. `ai-memory audit verify --format json` returns rc=0 with `ok=true` AND a
   non-empty `head_hash` AND `line_count >= 25` for every node.
3. The append-only flag (`chattr +a`, applied by setup_node.sh's audit-watcher)
   is observed if the filesystem supports it — but S25 does NOT enforce that;
   S27 covers append-only enforcement specifically. S25 is purely about
   hash-chain INTEGRITY over a non-empty log.

This scenario is **expected GREEN on v0.6.3.1**: the audit substrate is in
v0.6.3.1's release notes as a shipped feature. If S25 is RED, either the
substrate never wrote any lines (writes silently failing the audit hook), or
the chain failed to verify on a clean log (corruption at write time, not
tamper).

## Surface under test

- CLI: `ai-memory audit verify --format json`
- HTTP API: `POST /api/v1/memories` (write path that is supposed to land an audit line)
- File: `/var/log/ai-memory/audit.jsonl` (one JSONL line per op)
- Substrate property: hash-chain head reconstruction matches stored head

## Setup

- 4-node mesh, all v0.6.3.1, audit enabled on every node by `setup_node.sh`.
- Audit log lives at `/var/log/ai-memory/audit.jsonl` with mode 0700 on its
  parent dir.
- Each node's audit log SHOULD be empty before S25 runs (no F-probe writes
  have hit it yet at this stage of the workflow — F-probes happen during
  provisioning, but the audit-watcher applies `chattr +a` on first write).
  We don't depend on emptiness; we depend on `line_count >= 25` AFTER our
  driven writes.

## Steps

1. For each of the 4 nodes (over ssh):
   - Capture the audit log line count before our writes (informational only).
   - Issue 25 `POST /api/v1/memories` calls with synthetic content. Each
     write uses a unique S25 marker namespace + UUID body so the writes are
     visible in the audit log AND distinguishable from other campaign writes.
   - Run `ai-memory audit verify --format json`. Capture rc + the JSON
     payload (which includes `ok`, `line_count`, `head_hash`, optional
     `errors` array).
2. Aggregate per-node results into the `outputs.per_node_audit` map.
3. Pass = every node satisfies all of:
   - `verify_rc == 0`
   - `ok == true`
   - `line_count >= 25` (we wrote 25; floor on what audit must hold)
   - `head_hash` non-empty (presence test, not value comparison)

## Pass criteria

**On v0.6.3.1 (GREEN, expected):**
- Every node's audit verify exits 0.
- Every node's `ok == true`.
- Every node's `line_count >= 25`.
- Every node has a non-empty `head_hash`.

If any node fails any of those, the substrate is not delivering the chained
trail and S25 is RED.

## Fail modes

- Audit log absent or empty after 25 writes (audit hook not firing on the
  HTTP write path).
- `ai-memory audit verify` returns rc != 0 even though no tamper occurred
  (legitimate verify failure on a clean log = chain-write-time corruption).
- `head_hash` empty / null (substrate emitted lines but didn't compute the
  chain head).
- `line_count < 25` (some writes silently bypassed the audit hook —
  internally inconsistent with S24's MCP-stdio bypass scope, since S25 uses
  HTTP).

## Expected verdict on v0.6.3.1

`GREEN`. v0.6.3.1's release notes name the audit substrate as shipped; if
this scenario is RED, the campaign cannot trust ANY downstream audit
property test (S26 tamper detection, S27 append-only, Phase 3 I/J), so we
treat S25 as the integrity gate for the entire forensic-audit test suite.

## References

- `docs/forensic-audit.md` — campaign explainer for the 5 audit properties
- `scripts/setup_node.sh` — audit-config write + chattr watcher
- ai-memory release notes — `v0.6.3.1` audit substrate ship
- Related: S26 (tamper detection), S27 (append-only enforcement)
