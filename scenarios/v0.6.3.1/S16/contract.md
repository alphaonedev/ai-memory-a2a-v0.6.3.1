# S16 — Capabilities v2 honesty cross-mesh

## What this asserts

Capabilities v2 (closes the [§5.3 Capabilities-JSON theater](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#53-capabilities-json-theater-advertised-not-implemented-in-v063)) reports honest live state via `memory_capabilities`: `recall_mode_active: "hybrid" | "keyword_only" | "degraded"`, `reranker_active: "neural" | "lexical_fallback" | "off"`, `permissions.mode: "advisory"` (until v0.7), and drops the never-populated `subscribers` / `by_event` / `rule_summary` / `default_timeout_seconds` fields. v1 client compatibility preserved via `schema_version` discriminator.

In a 4-node mesh where one node has its embedder unloaded (or HF download fail), this scenario asserts the asymmetric capability is **surfaced from every node, never absorbed**. Querying capabilities of node-D from node-A must reveal node-D's degraded state — the exact opposite of the v0.6.3 theater behaviour where the `reranker_active` claim was hard-coded.

## Surface under test

- MCP tool: `memory_capabilities()`
- HTTP endpoint: `GET /api/v1/capabilities`
- Cross-node query: `GET /api/v1/peers/<node>/capabilities` (per federation API)

## Setup

- 4-node mesh, ironclaw / mTLS.
- Phase 1: all four nodes have embedder + reranker loaded; recall mode `hybrid`.
- Phase 2: node-D's embedder is deliberately unloaded (`OLLAMA_OFF=1` or moral equivalent).
- Phase 3: node-D's reranker model is deliberately removed from cache and HF download blocked.

## Steps

1. Phase 1: query `memory_capabilities` on every node; assert `recall_mode_active = "hybrid"` and `reranker_active = "neural"` everywhere.
2. Phase 1: assert `schema_version >= 2` on every node and that the deprecated v1-only keys (`subscribers`, `by_event`, `rule_summary`, `default_timeout_seconds`) are **absent** from the v2 response shape.
3. Phase 2: unload node-D's embedder; query `memory_capabilities` directly on D — assert `recall_mode_active = "keyword_only"`.
4. Phase 2: from node-A, query D's capabilities via the federation peer endpoint; assert the degraded value surfaces (no caching of stale capabilities).
5. Phase 3: block reranker on D; assert `reranker_active = "lexical_fallback"` from D and from A's view of D.
6. Restore node-D to healthy state; assert capabilities flip back across the mesh within the configured refresh interval.

## Pass criteria

- v2 schema discriminator present on every node.
- v1-theater fields removed from v2 response.
- Single-node degradation reflected in that node's own capabilities.
- Same degradation visible from peer nodes via federation peer endpoint (no silent absorb).
- Restoration round-trips capabilities cleanly across the mesh.
- `permissions.mode` reads `"advisory"` (per v0.6.3.1 honesty patch) on every node.

## Fail modes

- Node-D self-reports `hybrid` while embedder is unloaded (theater regression).
- Node-D's degradation invisible from A / B / C (stale capabilities cache, silent absorb).
- v1 theater fields still present (release patch incomplete).
- `permissions.mode` reads anything other than `"advisory"` (premature claim — v0.7 deliverable).

## Expected verdict on v0.6.3.1

`GREEN`. Capabilities v2 is in the v0.6.3.1 cutline-keep set and is the named close-out for §5.3 theater.

## References

- ROADMAP2 §5.3 — [Capabilities-JSON theater](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#53-capabilities-json-theater-advertised-not-implemented-in-v063)
- ROADMAP2 §7.2 — [Capabilities v2 honesty](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#72-v0631--honesty-patch--recovered-commitments--doc-currency--q2-2026-4-weeks)
- Release notes — [`v0.6.3.1.md`](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/releases/v0.6.3.1.md)
- Related: S10 (doctor cross-node), S15 (recall determinism)
