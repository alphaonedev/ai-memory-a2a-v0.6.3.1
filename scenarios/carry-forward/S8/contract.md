# S8 — auto-tagging

## Source

This scenario is carried forward unchanged from the umbrella testbook at
[`alphaonedev/ai-memory-ai2ai-gate`](https://github.com/alphaonedev/ai-memory-ai2ai-gate).
It is run on v0.6.3.1 to verify no regression. Spec authority: umbrella.
Evidence: this repo.

## What this asserts

When an agent writes a memory with no tags, the auto-tag pipeline
runs and stamps it with topic-relevant tags drawn from the live
taxonomy. A different agent can then recall that record by one of
the auto-generated tags. The taxonomy itself is queryable, and
the tags applied are members of it — no off-taxonomy tags slip
through.

## Surface under test

- MCP tool `memory_store` (with empty `tags`)
- MCP tool `memory_auto_tag` (explicit invocation; the pipeline
  is also wired as a post-write hook per umbrella spec)
- MCP tool `memory_get_taxonomy` (taxonomy snapshot)
- MCP tool `memory_recall` (recall by auto-generated tag)

## Setup

- 4-node mesh in steady state.
- Auto-tag backend provisioned (Ollama / Gemma per umbrella
  baseline).
- Taxonomy seeded with the umbrella's standard list.

## Steps

1. Agent A on `${A2A_NODE_A}` calls `memory_store` with content
   on a recognisable topic and `tags=[]`.
2. Wait for the umbrella's auto-tag settle window.
3. Capture the taxonomy snapshot via `memory_get_taxonomy`.
4. Read back A's record; collect its applied tag set.
5. Assert tag set is non-empty and a subset of the taxonomy.
6. Agent B calls `memory_recall` filtered by one of the
   auto-applied tags; assert A's record appears.

## Pass criteria

- A's record has at least one auto-generated tag after settle.
- All applied tags are members of the queried taxonomy.
- B's tag-filtered recall contains A's record.

## Fail modes

- Empty tag set after settle (pipeline regression or backend
  outage).
- Tags applied that are not in the taxonomy (off-taxonomy leak).
- Auto-tag overwrites an unrelated field on the record.
- B cannot recall A's record by the auto-generated tag.

## Expected verdict on v0.6.3.1

`GREEN` — regression. Was green on v0.6.3; must remain green here.

## References

- Umbrella spec: <https://github.com/alphaonedev/ai-memory-ai2ai-gate>
- Umbrella testbook entry: `testbook/S8/`
- Umbrella baseline (auto-tag backend):
  `docs/baseline.md` in the umbrella repo
