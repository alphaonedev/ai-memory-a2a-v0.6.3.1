# S29 — Governance approval gate (Allow / Deny / Pending across federation)

## What this asserts

ai-memory v0.6.3.1 ships a **governance approval gate** —  a
namespace-scoped policy that holds writes in `state=Pending` until an
approver (a distinct NHI agent_id, typically `ai:operator` or a
`role=admin` identity) explicitly Approves or Denies them. The full
matrix is **3 actions × 4 approval levels × 3 approver types = 36
verdict shapes**; S29 is the substrate canary that proves the
end-to-end happy path through the pipeline:

1. Configure a namespace with `approval_required = true`.
2. Write a memory to that namespace as a regular agent (`ai:alice`).
   The write MUST NOT immediately materialise on the recall surface —
   it MUST land in the pending queue with `state=Pending`. The HTTP
   response code SHOULD reflect deferred admission (`202 Accepted` or
   the build-equivalent — never `201 Created`).
3. The write MUST appear in `memory_pending_list` / the
   `/api/v1/memory/pending` queue on every node in the federation.
4. An approver (`ai:operator`) calls `memory_pending_approve`
   (or `POST /api/v1/memory/pending/<id>/approve`). The memory
   transitions to `state=Allow`, becomes recall-visible, and the
   approval propagates across federation: `memory_pending_list` on
   peer nodes no longer shows it.
5. Symmetric reject path: a parallel write is held pending, then
   denied. The memory MUST NOT appear in any node's recall surface,
   and the deny MUST propagate (peer pending lists clear too — the
   decision is recorded as Deny, not "still pending").

Together these two sub-flows assert the **approval gate is
federation-aware**: a single approver decision on node-1 settles
the queue across the entire mesh. Without that, an attacker could
race the approval by writing to a peer that hasn't seen the deny
propagate yet.

## Surface under test

- HTTP: `POST /api/v1/memories` against a governed namespace
- HTTP: `GET /api/v1/memory/pending` (alias of `memory_pending_list`)
- HTTP: `POST /api/v1/memory/pending/<id>/approve` (alias of `memory_pending_approve`)
- HTTP: `POST /api/v1/memory/pending/<id>/reject` (alias of `memory_pending_reject`)
- HTTP: namespace policy — `PUT /api/v1/namespaces/<ns>/policy` or `memory_namespace_set_standard`
- Headers: `X-Agent-Id` (writer + approver identity)
- Federation: native fanout of approval / deny decisions

## Setup

- 4-node mesh, ironclaw / mTLS, all v0.6.3.1.
- Native fanout enabled.
- Test namespace: `governed/test/<run_id>` to isolate from other
  canaries. Policy installed at start of run, restored at end (the
  whole namespace is run-scoped, so cleanup is namespace-deletion).
- Three NHI identities exercised:
  `ai:alice` (regular writer), `ai:bob` (regular writer, parallel
  reject path), `ai:operator` (approver, role=admin).

## Steps

1. **Configure governed namespace.** On node-1, install
   `approval_required = true` on `governed/test/<run_id>`.
   We try `PUT /api/v1/namespaces/<ns>/policy` first; if that
   surface is not exposed we fall back to
   `memory_namespace_set_standard` over MCP stdio. (Pre-existing
   namespace-standards machinery in v0.6.3.1 supports the
   `approval_required` flag per the user's brief; the fallback
   covers builds that haven't surfaced the HTTP form yet.)
2. **Write lands pending.** As `ai:alice`, POST a memory to the
   governed namespace. Assert HTTP `202 Accepted` (or
   build-equivalent indicating deferred admission). Capture the
   pending id. Assert the memory does NOT appear in a recall against
   the governed namespace immediately (`state=Pending` is invisible
   to the standard recall surface).
3. **Pending list shows it.** GET `/api/v1/memory/pending` on
   node-1. Assert the pending id is in the result.
4. **Approve + propagate.** As `ai:operator`, POST
   `/api/v1/memory/pending/<id>/approve`. Assert success. Wait the
   federation settle window. On node-2, recall the governed
   namespace; assert the memory IS now visible. On node-2, GET the
   pending list; assert the id is NO LONGER present (decision
   propagated, not just stored locally).
5. **Reject path (parallel).** Repeat steps 2–4 with `ai:bob` as
   writer and a reject decision: POST a second memory, capture
   pending id, then POST `/api/v1/memory/pending/<id>/reject` as
   `ai:operator`. Wait. On every peer, assert (a) the memory is
   NOT visible on the recall surface, and (b) the id is NOT in the
   pending list. The deny is decided, not still pending.

## Pass criteria

- `pending_state_correct = true`: the alice-write surfaces with
  state=Pending, is invisible to recall, and shows up in the pending
  list on at least the originating node.
- `approve_propagates = true`: after `ai:operator` approves, the
  memory is visible on the recall surface of node-2 and is gone
  from node-2's pending list.
- `deny_propagates = true`: after `ai:operator` rejects the
  parallel write, that memory is invisible on node-2's recall
  surface and is gone from node-2's pending list.
- All three ⇒ `actual_verdict = GREEN`, `pass = true`.

## Fail modes

- `pending_state_correct = false`: write went straight to
  `state=Allow` despite `approval_required=true`. **Critical** —
  the gate did not engage.
- `approve_propagates = false`: approval landed locally but peers
  never saw it; recall shows nothing on node-2 even after settle.
  **Critical** — the gate is not federation-aware.
- `deny_propagates = false`: deny was local-only; node-2 still
  has the memory pending. **Critical** — race-the-approval attack.
- A 4xx from either approve or reject (other than the expected
  pending-not-found-after-decision case) ⇒ harness or surface
  mismatch; emit `actual_verdict=UNKNOWN`.

## Expected verdict on v0.6.3.1

`GREEN`. The approval gate is documented as a first-class shipping
capability in v0.6.3.1's release notes. S29 is the substrate canary
that asserts the documented behaviour holds end-to-end on the live
mesh including federation propagation.

If the namespace-policy install surface (step 1) is not reachable
on EITHER endpoint (HTTP PUT or MCP stdio fallback), the runner
emits `actual_verdict=UNKNOWN` with a `policy_install_failed`
reason — never silently green.

## References

- Capabilities inventory: [`docs/capabilities.md`](../../../docs/capabilities.md) §2 Governance — approval gate
- Companion canary: S28 (NHI agent_id immutability — the approver record relies on agent_id stickiness)
- Companion canary: S30 (A2A messaging — approve/reject events are deliverable as inbox notifications)
- Audit trail: S25 / S26 / S27 (every approve/reject lands a hash-chained line keyed by approver agent_id)
