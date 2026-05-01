# S24 — Issue [#318](https://github.com/alphaonedev/ai-memory-mcp/issues/318) MCP stdio writes fan out

## What this asserts

[Issue #318](https://github.com/alphaonedev/ai-memory-mcp/issues/318) — On a federated node, two `ai-memory` processes run concurrently: the long-running `ai-memory serve` daemon (HTTP API + fanout coordinator) and the short-lived `ai-memory mcp` stdio child spawned per MCP JSON-RPC call. **Pre-Patch-2: writes via the MCP stdio path go directly to SQLite and are invisible to the fanout coordinator** — they persist locally but never replicate to peers.

This scenario asserts that on a federated mesh, `memory_store` / `memory_update` / `memory_delete` / `memory_link` / `memory_promote` / `memory_consolidate` / `memory_forget` invoked via the MCP stdio surface (not HTTP) trigger federation fanout to peers exactly as the HTTP path does.

This scenario is **expected RED on v0.6.3.1**: Issue #318 is open as of release tag, with the fix scheduled for **Patch 2 (`v0.6.3.2`)**. The complementary HTTP path is already green and is exercised by S17 (G9 webhook fanout).

## Surface under test

- MCP stdio transport: `ai-memory mcp` invoked as a JSON-RPC child by an agent CLI
- Tools probed: `memory_store`, `memory_update`, `memory_delete`, `memory_link`, `memory_promote`, `memory_consolidate`, `memory_forget`
- Federation coordinator: `ai-memory serve --quorum-writes 2 --quorum-peers ...`

## Setup

- 4-node mesh with W=2 / N=4 quorum, ironclaw / mTLS.
- Each node runs `ai-memory serve` continuously.
- A grok-CLI-equivalent stub (or any MCP-native agent runner) on node-A configured to spawn `ai-memory mcp` as its MCP server.
- Phase 1 (HTTP control): writes via `POST /api/v1/memories` on node-A — the green-path proof per #318 issue body.
- Phase 2 (MCP stdio test): same write payload via the MCP stdio surface.

## Steps

1. Phase 1 (control): on node-A, `POST /api/v1/memories` for ~10 memories; await fanout. Assert peers B/C/D each see the rows replicated. (Cross-link to S17 for the webhook side.)
2. Phase 2: on node-A, invoke `memory_store` via MCP stdio for ~10 memories with distinguishable content.
3. After expected fanout window: `memory_recall` on B/C/D for the Phase 2 content.
4. **On v0.6.3.1, expect zero rows on B/C/D** — the issue's documented behaviour. The phase-2 writes persist locally on node-A but never replicate.
5. Repeat the MCP-stdio probe for `memory_update`, `memory_delete`, `memory_link`, `memory_promote`, `memory_consolidate`, `memory_forget`. All seven event types are expected to be silent on the federation path on v0.6.3.1.
6. Capture audit log on node-A and confirm the writes happened locally; this rules out "the write didn't happen" as an alternative explanation for the fanout absence.
7. Capture serve daemon logs on B/C/D and confirm no inbound replication request from A for the Phase 2 batch.

## Pass criteria

**On v0.6.3.1 (RED, expected):**
- Phase 1 (HTTP) replication works to all peers — control case green.
- Phase 2 (MCP stdio) replication count to peers is **zero** for every probed tool.
- Local audit log on node-A shows the writes succeeded — rules out a non-bug explanation.
- Serve daemon logs on B/C/D show no replication request for Phase 2 traffic.

**On Patch 2 (GREEN, future):**
- Phase 2 (MCP stdio) replication matches Phase 1 (HTTP) — every tool produces fanout to peers.
- Replication count to peers ≥ W − 1 (i.e. quorum satisfied) for every probed tool.

The runner emits the same JSON shape in either case; the harness flips the verdict based on `expected_verdict` in `expected.json`. Patch 2 will close this; expected GREEN there.

## Fail modes

On v0.6.3.1:
- Phase 1 control fails (broader federation regression — would also break S17).
- Phase 2 silently *succeeds* on some probed tools (would mean #318 is partially fixed and the issue body needs amendment).
- Mixed signal across nodes (asymmetric failure — cross-link to S9 binary drift).

## Expected verdict on v0.6.3.1

`RED`. Issue #318 is open; the fix is scheduled for **Patch 2 (`v0.6.3.2`)**. Patch 2 will close this; expected GREEN there.

## References

- Issue [#318](https://github.com/alphaonedev/ai-memory-mcp/issues/318) — MCP stdio tool dispatch writes bypass federation fanout
- Release notes — [`v0.6.3.1.md`](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/releases/v0.6.3.1.md)
- Patch 2 funnel — umbrella tracking issue (TBD on `ai-memory-mcp`)
- Related: S17 (G9 webhook fanout — HTTP path is green), S9 (boot manifest)
