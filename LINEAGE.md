# Lineage

Where this repo's spec comes from, where its results go, and how it connects to the rest of the ai-memory test ecosystem.

## Up the chain — what this repo depends on

- **Spec source.** [`alphaonedev/ai-memory-ai2ai-gate`](https://github.com/alphaonedev/ai-memory-ai2ai-gate) — the umbrella A2A repo. Owns:
  - `baseline/` — the canonical scenario contract.
  - `testbook/` — the eight base scenarios `S1 – S8`.
  - `topology/` — 4-node mesh topology spec.
  - `methodology/` — what counts as a pass / fail.
  - `v1-ga-criteria/` — the long-term contract this campaign rolls up into.
- **Subject under test.** [`alphaonedev/ai-memory-mcp`](https://github.com/alphaonedev/ai-memory-mcp) at tag [`v0.6.3.1`](https://github.com/alphaonedev/ai-memory-mcp/releases/tag/v0.6.3.1).
- **Pre-flight gate.** [`alphaonedev/ai-memory-ship-gate`](https://github.com/alphaonedev/ai-memory-ship-gate) — its 4 phases (functional, federation, migration, chaos) must be green at the same tag before this campaign starts.

## Down the chain — what depends on this repo

- **Aggregator.** [`alphaonedev.github.io/ai-memory-test-hub`](https://alphaonedev.github.io/ai-memory-test-hub/) — the *Per-Release Evidence* table on the test-hub binds a verdict cell to this repo's `releases/v0.6.3.1/summary.json`. The hub's `/releases/v0.6.3.1/` sub-page links to this repo's GitHub Pages.
- **Funnel.** [`alphaonedev/ai-memory-mcp` issue tracker](https://github.com/alphaonedev/ai-memory-mcp/issues) — every defect surfaced by this campaign opens or updates a `bug` + `v0.6.3.2-candidate` issue, parent-linked to the campaign's umbrella tracking issue.
- **Successor.** When **Patch 2 (`v0.6.3.2`)** tags, a new repo `ai-memory-a2a-v0.6.3.2` will be created using this repo as the template. `S23` and `S24` must turn green there.

## Convention going forward

`ai-memory-a2a-v<version>` per release. The umbrella keeps the spec; per-release repos hold the execution and evidence. The convention compounds: every release ships its own reproducible cert artifact, public, Apache-2.0, immutable once tagged.
