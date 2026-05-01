# S6 — contradiction detection

## Source

This scenario is carried forward unchanged from the umbrella testbook at
[`alphaonedev/ai-memory-ai2ai-gate`](https://github.com/alphaonedev/ai-memory-ai2ai-gate).
It is run on v0.6.3.1 to verify no regression. Spec authority: umbrella.
Evidence: this repo.

## What this asserts

When two agents write directly contradictory statements about the
same topic, the contradiction-detection pipeline surfaces both
records and links them with a `contradicts` edge. A third agent's
recall on the topic returns both originals plus the
`contradicts` link — neither side is silently dropped or auto-
merged. The link is bidirectional in `memory_get_links` results.

## Surface under test

- MCP tool `memory_store`
- MCP tool `memory_detect_contradiction`
- MCP tool `memory_link` (the resulting `contradicts` edge)
- MCP tool `memory_recall`
- MCP tool `memory_get_links` (link inspection)

## Setup

- 4-node mesh in steady state.
- Topic chosen so that "X is true" and "X is false" form an
  unambiguous contradiction (e.g., "Mars has two moons" /
  "Mars has three moons").

## Steps

1. Agent A on `${A2A_NODE_A}` writes "X is true."
2. Agent B on `${A2A_NODE_B}` writes "X is false."
3. Wait for the umbrella settle window.
4. `memory_detect_contradiction` is invoked (from the curator on
   `${A2A_NODE_D}` or via the agent caller per umbrella spec).
5. Agent C on `${A2A_NODE_C}` calls `memory_recall` on the topic.
6. Inspect C's recall set + the link graph.

## Pass criteria

- `memory_detect_contradiction` returns at least one detected pair
  covering A's and B's records.
- A `contradicts` link exists between the two records.
- C's recall set contains both A's and B's records.
- A yes-no probe on the topic via the agent's recall surface
  acknowledges both stances rather than echoing only one.

## Fail modes

- Detection misses the pair (false negative — silent agreement).
- One record is auto-deleted in the name of "deduplication".
- Link is unidirectional or missing on `memory_get_links`.
- C sees only A or only B (federation drop masquerading as
  resolution).

## Expected verdict on v0.6.3.1

`GREEN` — regression. Was green on v0.6.3; must remain green here.

## References

- Umbrella spec: <https://github.com/alphaonedev/ai-memory-ai2ai-gate>
- Umbrella testbook entry: `testbook/S6/`
