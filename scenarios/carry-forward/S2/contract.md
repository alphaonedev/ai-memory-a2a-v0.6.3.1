# S2 — shared-context handoff

## Source

This scenario is carried forward unchanged from the umbrella testbook at
[`alphaonedev/ai-memory-ai2ai-gate`](https://github.com/alphaonedev/ai-memory-ai2ai-gate).
It is run on v0.6.3.1 to verify no regression. Spec authority: umbrella.
Evidence: this repo.

## What this asserts

The canonical A2A handoff pattern works end-to-end: agent A writes
a memory tagged for B (e.g., `handoff-to-bob`) at scope `team`,
and agent B observes that handoff in its recall set within the
quorum-settle window. Agents never speak directly — the handoff
flows entirely through ai-memory as the shared substrate.

## Surface under test

- MCP tool `memory_store` (with `tags=[handoff-to-bob]`, `scope=team`)
- MCP tool `memory_recall` (filtered by `tags=handoff-*`)
- Federation settle behaviour against the v0.6.3.1 quorum config

## Setup

- 4-node mesh as defined in the umbrella topology spec.
- `${A2A_NODE_A}` runs IronClaw `ai:alice`.
- `${A2A_NODE_B}` runs Hermes `ai:bob`.
- `${A2A_NODE_D}` is the authoritative store.
- Inbox / no pre-existing `handoff-*` records for `ai:bob`.

## Steps

1. Agent A on node A calls `memory_store` with content describing
   the handoff payload, tagged `handoff-to-bob`, scope `team`.
2. Wait for the umbrella's quorum-settle window.
3. Agent B on node B calls `memory_recall` filtered by the
   `handoff-*` tag pattern.
4. Assert the recall set contains A's handoff record, with
   `agent_id=ai:alice` and the original tag preserved.

## Pass criteria

- B's recall returns at least one record matching `handoff-to-bob`.
- The record's `agent_id` is `ai:alice`, not `ai:bob`.
- Settlement happens within the umbrella-defined window.

## Fail modes

- B's recall is empty (federation drop or scope mis-enforcement).
- Settlement window exceeded (regression on quorum config).
- Handoff visible to C as well when C is not in the team scope
  (scope leak — would also implicate S7).

## Expected verdict on v0.6.3.1

`GREEN` — regression. Was green on v0.6.3; must remain green here.

## References

- Umbrella spec: <https://github.com/alphaonedev/ai-memory-ai2ai-gate>
- Umbrella testbook entry: `testbook/S2/`
