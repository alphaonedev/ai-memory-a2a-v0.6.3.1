# S14 — `ai-memory logs` operator surface

## What this asserts

The operational logging facility (release notes §"Operational logging facility") is a separate channel from the audit log. Its CLI front-end `ai-memory logs` exposes `tail` / `cat` / `archive` / `purge` with filters `--since`, `--until`, `--level`, `--namespace`, `--actor`, `--action`, `--format text|json`. It is **default-OFF** for privacy; opt-in via `[logging] enabled = true`.

This scenario asserts: (a) with logging disabled, no operational log file is created and `ai-memory logs tail` returns the default-OFF signal; (b) with logging enabled on every node, the same filter combination produces equivalent shape (same column set, same envelope) on every node; (c) the privacy default is honoured even after a config edit toggles only one node — neighbours that did not opt in stay silent.

## Surface under test

- CLI: `ai-memory logs {tail|cat|archive|purge}` with the documented filter set
- Config: `[logging]` section with `enabled` / `path` / `max_size_mb` / `max_files` / `retention_days` / `structured` / `level`
- Path resolution precedence: CLI > env (`AI_MEMORY_LOG_DIR`) > config.toml > platform default

## Setup

- 4-node mesh, ironclaw / mTLS.
- Phase 1: every node has `[logging] enabled = false` (factory default).
- Phase 2: every node flipped to `enabled = true` with identical retention config.
- Phase 3: only node-D enabled; A / B / C reverted to disabled.

## Steps

1. Phase 1: on every node, `ai-memory logs tail`; assert the OFF signal (informational message, no file dereference, exit `0`).
2. Phase 1: confirm no log file exists at the resolved path on any node.
3. Phase 2: enable logging on every node; run a small workload (recall / store / link).
4. Phase 2: on each node run `ai-memory logs tail --format json --since '5 minutes ago'`; capture lines.
5. Phase 2: assert envelope shape (key set) is identical across all four nodes.
6. Phase 2: filter by `--namespace` and `--actor` and `--action`; assert the cardinalities make sense (subset relationships hold).
7. Phase 3: revert A / B / C to disabled; confirm only D continues writing log lines.
8. Phase 3: confirm `AI_MEMORY_LOG_DIR` env var override beats config on a per-invocation basis on node-D.

## Pass criteria

- Phase 1: zero log files anywhere; `tail` exits `0` with a benign default-OFF message.
- Phase 2: every node's JSON envelope has the same key set.
- Phase 2: filter cardinalities respect subset semantics (`--namespace=X --actor=Y` subset of `--namespace=X`).
- Phase 3: A / B / C produce no new lines after revert; D continues.
- Env-var precedence honoured: a one-shot `AI_MEMORY_LOG_DIR=/tmp/elsewhere ai-memory logs tail` reads from `/tmp/elsewhere`, not the config.toml path.

## Fail modes

- Log file appears on a node that did not opt in (privacy-default regression).
- Envelope shape differs between nodes (binary drift — cross-link to S9).
- Filter combination silently widens (e.g. `--actor=X` returns rows for actor Y).
- Env-var precedence inverted.

## Expected verdict on v0.6.3.1

`GREEN`. The default-OFF privacy guarantee is a stated v0.6.3.1 contract.

## References

- Release notes — [`v0.6.3.1.md`](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/releases/v0.6.3.1.md)
- Related: S13 (audit), S17 (webhook fanout)
