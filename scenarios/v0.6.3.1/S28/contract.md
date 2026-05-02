# S28 — NHI agent_id immutability across update / dedup / sync / import

## What this asserts

ai-memory v0.6.3.1 ships **non-human-identity (NHI)** as a first-class
substrate concept: every memory carries `metadata.agent_id` set to the
writer-of-record at the moment of admission, and that value MUST be
immutable across the four mutation surfaces an attacker (or a buggy
peer) could plausibly use to rewrite history:

1. **`memory_update` / HTTP `PUT /api/v1/memories/<id>`** — a later
   writer (`ai:bob`) cannot overwrite the original writer's
   (`ai:alice`) `metadata.agent_id`. Content / title / tags MAY be
   updated; the NHI bind MUST stay sticky to the original. `updated_at`
   and `update_count` MAY bump.
2. **Dedup / `memory_consolidate`** — when two writes with identical
   content but different `agent_id` collide, the consolidated row MUST
   preserve **both** writers in the source-agent provenance (set or
   list of agent_ids). Neither agent loses attribution.
3. **Federation sync (fanout)** — when a memory replicates from
   node-1 to node-2, the relayed copy on node-2 MUST carry the
   original `agent_id`, not the relaying peer's identity. Otherwise
   "ai:alice wrote this" becomes "node-2 wrote this" after the next
   convergence cycle and provenance is lost.
4. **`memory_import` round-trip** — exporting a memory to JSON and
   reimporting it on a fresh ai-memory instance MUST preserve
   `metadata.agent_id` byte-for-byte. The import path is the canonical
   migration / restore-from-backup surface; if it strips agent_id,
   long-term forensic provenance is decoupled from the data.

These four invariants are defence-in-depth: if any single one fails,
an adversarial peer or a careless operator can rewrite NHI provenance
silently, and downstream governance (approval gate, audit trail,
prime-directive enforcement) loses its identity anchor.

## Surface under test

- HTTP: `POST /api/v1/memories` (write), `PUT /api/v1/memories/<id>` (update)
- HTTP: `GET /api/v1/memories?namespace=...` (recall), `GET /api/v1/memories/<id>` (single)
- HTTP: `POST /api/v1/memories/consolidate` (dedup)
- HTTP: `POST /api/v1/memories/export` + `POST /api/v1/memories/import` (round-trip)
- Header: `X-Agent-Id: <agent_id>` (writer-of-record identity)
- Federation: native fanout from node-1 to node-2..N (W=2/N=4 quorum)
- Field under invariance: `metadata.agent_id`

## Setup

- 4-node mesh, ironclaw / mTLS, all v0.6.3.1.
- Native fanout enabled (per S24 — write via HTTP, not MCP stdio,
  to avoid #318's MCP-bypass surface confounding the result).
- Probe namespace: `test/S28/<run_id>` to isolate from other canaries.
- Two NHI identities exercised: `ai:alice` (original writer),
  `ai:bob` (attempted-rewriter).

## Steps

1. **Update immutability** — on node-1, POST a memory `M1` with
   header `X-Agent-Id: ai:alice` and content `s28-original-payload`.
   Capture returned `id` and assert returned
   `metadata.agent_id == "ai:alice"`. Then PUT to
   `/api/v1/memories/<id>` with header `X-Agent-Id: ai:bob` updating
   the content. GET the memory back; assert the new content landed
   AND `metadata.agent_id` is still `"ai:alice"`.
2. **Dedup preserves both agents** — on node-1, POST two memories
   with identical content (`s28-dedup-collide`) but different
   `X-Agent-Id` headers (`ai:alice`, `ai:bob`). Trigger a
   consolidation pass (POST `/api/v1/memories/consolidate` against
   the namespace, or rely on the curator daemon's natural pass).
   Recall the namespace; assert exactly one consolidated row exists
   and that the source-agent provenance contains BOTH `ai:alice`
   and `ai:bob` (whether under `metadata.source_agents`,
   `metadata.consolidated_from_agents`, or any other field whose
   string value enumerates both ids).
3. **Sync preserves origin** — wait the federation settle window
   (8s). On node-2, GET the namespace; find `M1`; assert its
   `metadata.agent_id == "ai:alice"`, NOT the relaying peer's
   (node-1's) identity. Federation MUST carry origin NHI verbatim.
4. **Import round-trip** — on node-1, POST `M1`'s id to the
   export endpoint. Capture the JSON body. Then POST that body to
   the import endpoint on node-3 (or on node-1 under a fresh
   namespace `test/S28/<run_id>/imported`). GET the imported row;
   assert `metadata.agent_id == "ai:alice"`.

## Pass criteria

- All 4 sub-invariants hold on the live mesh:
  - `update_immutability == true`
  - `dedup_preserves == true`
  - `sync_preserves == true`
  - `import_preserves == true`
- `actual_verdict = GREEN` ⇒ `pass = true`.
- A single failed sub-invariant collapses to
  `actual_verdict = RED` and `pass = false`.

## Fail modes

- `update_immutability = false`: a `PUT` from `ai:bob` rewrote
  `metadata.agent_id`. NHI provenance is fungible. **Critical**.
- `dedup_preserves = false`: the consolidator collapsed two writers
  into a single attribution. **Critical** for governance —
  approve/deny decisions can't reference the lost writer.
- `sync_preserves = false`: federation rewrote agent_id on the wire.
  **Critical** — provenance flips after every convergence cycle.
- `import_preserves = false`: the import path zeros out / overwrites
  agent_id. **High** — long-term restore-from-backup loses NHI.

## Expected verdict on v0.6.3.1

`GREEN`. The NHI agent_id field is documented as defence-in-depth
immutable across all four surfaces. S28 is a substrate canary
asserting the documented behaviour holds on the live mesh.

If the runner cannot reach the federation surface (peers not
healthy, namespace returns errors before the probe even starts),
the runner emits `actual_verdict=UNKNOWN` and `pass=false` — never
silently green.

## References

- Capabilities inventory: [`docs/capabilities.md`](../../../docs/capabilities.md) §1 NHI / Agent identity
- Companion canary: S29 (governance approval gate uses `agent_id` for the approver record)
- Federation primitives: S24 (#318 — note that MCP stdio writes bypass fanout, so S28 uses HTTP)
- Audit trail: S25 / S26 / S27 (every NHI mutation lands a hash-chained line keyed by `agent_id`)
