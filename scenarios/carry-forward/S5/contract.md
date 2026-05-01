# S5 — consolidation + curation

## Source

This scenario is carried forward unchanged from the umbrella testbook at
[`alphaonedev/ai-memory-ai2ai-gate`](https://github.com/alphaonedev/ai-memory-ai2ai-gate).
It is run on v0.6.3.1 to verify no regression. Spec authority: umbrella.
Evidence: this repo.

## What this asserts

When agents collectively write many similar memories and the
consolidation pipeline runs, the resulting consolidated record
preserves the full set of contributing authors. Specifically:
`metadata.consolidated_from_agents` is the *set* of contributing
agent ids — not overwritten by the most recent author, not
collapsed to the consolidator's id. The promote step preserves
the same provenance.

## Surface under test

- MCP tool `memory_store` (seed corpus)
- MCP tool `memory_consolidate`
- MCP tool `memory_promote`
- MCP tool `memory_recall` (verification)

## Setup

- 4-node mesh in steady state.
- Agents A, B, C will each contribute roughly equal slices of a
  100-memory corpus on the same topic.
- Curator runs from node D.

## Steps

1. Each of A, B, C calls `memory_store` ~33 times against the
   shared topic, distinguishing payloads only by trivia.
2. Wait for the umbrella settle window.
3. Curator on `${A2A_NODE_D}` invokes `memory_consolidate` over
   the topic.
4. Curator invokes `memory_promote` on the consolidated record.
5. Agent A calls `memory_recall` for the topic and inspects the
   `metadata.consolidated_from_agents` set on the consolidated
   record.

## Pass criteria

- Exactly one consolidated record (or the umbrella-defined
  consolidation cardinality) is produced.
- `metadata.consolidated_from_agents` equals
  `{ai:alice, ai:bob, ai:charlie}` as a set.
- Promote does not collapse the set to a single id.

## Fail modes

- `consolidated_from_agents` is overwritten with only the last
  writer (regression — this was the v0.6.3 fix).
- Set contains the curator's id rather than the contributors'.
- Consolidation produces zero records (pipeline regression).

## Expected verdict on v0.6.3.1

`GREEN` — regression. Was green on v0.6.3; must remain green here.

## References

- Umbrella spec: <https://github.com/alphaonedev/ai-memory-ai2ai-gate>
- Umbrella testbook entry: `testbook/S5/`
