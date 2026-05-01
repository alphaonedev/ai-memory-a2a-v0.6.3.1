# Scenarios

The full scenario list for the v0.6.3.1 A2A campaign, in two classes. **Class A** is carried forward from the umbrella testbook and must remain green. **Class B** is the v0.6.3.1-specific set covering the surfaces that shipped in this tag.

Each row links to its scenario directory in the repo (where `contract.md`, `runner.sh`, `fixtures/`, `expected.json` live) and, where applicable, to the upstream `ai-memory-mcp` issue it traces to.

Status is currently `PENDING` for every scenario — no campaign run has produced data yet. Once a run lands, statuses are populated from [`releases/v0.6.3.1/summary.json`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/releases/v0.6.3.1/summary.json) by the publish workflow.

## Class A — carry-forward

Eight base scenarios from the [umbrella `ai-memory-ai2ai-gate` testbook](https://github.com/alphaonedev/ai-memory-ai2ai-gate). Run unchanged on the v0.6.3.1 binary. Any red here is a regression and a release-blocker for the campaign verdict — Class A reds are **not** Patch 2 candidates.

| ID | Title | Surface | Status | Expected | Scenario directory |
|---|---|---|---|---|---|
| S1 | Per-agent write + read | `memory_store` / `memory_recall` | `PENDING` | GREEN | [`scenarios/carry-forward/S1`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/carry-forward) |
| S2 | Shared-context handoff | `shared_context` | `PENDING` | GREEN | [`scenarios/carry-forward/S2`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/carry-forward) |
| S3 | Targeted share | `share_to(agent_id)` | `PENDING` | GREEN | [`scenarios/carry-forward/S3`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/carry-forward) |
| S4 | Federation-aware agents | `federation_peers` | `PENDING` | GREEN | [`scenarios/carry-forward/S4`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/carry-forward) |
| S5 | Consolidation + curation | `memory_consolidate` | `PENDING` | GREEN | [`scenarios/carry-forward/S5`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/carry-forward) |
| S6 | Contradiction detection | `memory_detect_contradiction` | `PENDING` | GREEN | [`scenarios/carry-forward/S6`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/carry-forward) |
| S7 | Scoping visibility | scope rules | `PENDING` | GREEN | [`scenarios/carry-forward/S7`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/carry-forward) |
| S8 | Auto-tagging | `memory_auto_tag` | `PENDING` | GREEN | [`scenarios/carry-forward/S8`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/carry-forward) |

## Class B — v0.6.3.1-specific

Sixteen scenarios for surfaces shipped in [`v0.6.3.1`](https://github.com/alphaonedev/ai-memory-mcp/releases/tag/v0.6.3.1). `S9` – `S22` are expected GREEN. `S23` and `S24` are intentional **expected RED** integrity checks.

| ID | Title | Surface | Status | Expected | Scenario directory | Issue |
|---|---|---|---|---|---|---|
| S9 | Boot manifest agreement | `ai-memory boot` multi-node | `PENDING` | GREEN | [`scenarios/v0.6.3.1/S9`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S9) | — |
| S10 | Doctor cross-node | `ai-memory doctor` | `PENDING` | GREEN | [`scenarios/v0.6.3.1/S10`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S10) | — |
| S11 | Recipe handoff | `ai-memory install <agent>` | `PENDING` | GREEN | [`scenarios/v0.6.3.1/S11`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S11) | — |
| S12 | Cross-vendor wrap | `ai-memory wrap <agent>` | `PENDING` | GREEN | [`scenarios/v0.6.3.1/S12`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S12) | — |
| S13 | Audit verify tamper-evident | `ai-memory audit verify` | `PENDING` | GREEN | [`scenarios/v0.6.3.1/S13`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S13) | — |
| S14 | Operator logs | `ai-memory logs` | `PENDING` | GREEN | [`scenarios/v0.6.3.1/S14`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S14) | — |
| S15 | `budget_tokens` recall (R1) | recall | `PENDING` | GREEN | [`scenarios/v0.6.3.1/S15`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S15) | — |
| S16 | Capabilities v2 honesty | `memory_capabilities` | `PENDING` | GREEN | [`scenarios/v0.6.3.1/S16`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S16) | — |
| S17 | Webhook fanout (G9) | webhooks | `PENDING` | GREEN | [`scenarios/v0.6.3.1/S17`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S17) | — |
| S18 | Embedding-dim integrity (G4) | write boundary | `PENDING` | GREEN | [`scenarios/v0.6.3.1/S18`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S18) | — |
| S19 | Archive/restore preserves embeddings (G5) | archive | `PENDING` | GREEN | [`scenarios/v0.6.3.1/S19`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S19) | — |
| S20 | `on_conflict` policy (G6) | concurrent writes | `PENDING` | GREEN | [`scenarios/v0.6.3.1/S20`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S20) | — |
| S21 | Endianness magic byte (G13) | f32 BLOB exchange | `PENDING` | GREEN | [`scenarios/v0.6.3.1/S21`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S21) | — |
| S22 | Schema v19 migration | migration ladder | `PENDING` | GREEN | [`scenarios/v0.6.3.1/S22`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S22) | — |
| **S23** | `~` expansion in `db` | config.toml | `PENDING` | **RED (expected)** | [`scenarios/v0.6.3.1/S23`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S23) | [`#507`](https://github.com/alphaonedev/ai-memory-mcp/issues/507) |
| **S24** | MCP stdio fanout | MCP stdio writes | `PENDING` | **RED (expected)** | [`scenarios/v0.6.3.1/S24`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S24) | [`#318`](https://github.com/alphaonedev/ai-memory-mcp/issues/318) |

## Why S23 and S24 are expected RED

`S23` and `S24` correspond to defects that already have OSS issue threads with reproductions on `ai-memory-mcp`. We know v0.6.3.1 ships with these defects; they were not fixed in time for this tag.

- **`S23`** — [`#507` — config.toml `~` expansion](https://github.com/alphaonedev/ai-memory-mcp/issues/507). The `db` field in `config.toml` accepts a path like `~/.ai-memory/store.db` but the loader passes the literal `~` to SQLite without home-directory expansion, so the open call fails on first run for any user who used a tilde in their config. Medium severity. This is the **seed defect for Patch 2** — the umbrella tracking issue is anchored on it.
- **`S24`** — [`#318` — MCP stdio writes bypass federation fanout](https://github.com/alphaonedev/ai-memory-mcp/issues/318). Writes that arrive over the MCP stdio transport take a code path that does not call into the federation fanout layer, so peers never see them. Reads via stdio are unaffected; the bug is asymmetric. High severity (silent divergence between mesh nodes is a correctness break).

If either scenario came back `GREEN` on v0.6.3.1, the harness would be lying — there is no plausible way the underlying code path passes on this tag without a hot-fix that did not ship. Their inclusion is an integrity check on the harness itself.

## How they flip under Patch 2

When Patch 2 (`v0.6.3.2`) tags, a successor repo `ai-memory-a2a-v0.6.3.2` will be created from this one as a template. In that successor:

- `S23` and `S24` move out of the expected-red list. The Class B table flips them to **expected GREEN**.
- The umbrella tracking issue on `ai-memory-mcp` is closed when both `S23` and `S24` are green on the Patch 2 cert.
- This repo, `ai-memory-a2a-v0.6.3.1`, becomes immutable evidence that the v0.6.3.1 tag shipped with both defects — the cert artifact for that release stays as it is, forever.

That is the funnel pattern: every per-release campaign is a self-contained, immutable cert artifact. Patch releases get their own repos rather than rewriting history on the previous one.

## Cross-links

- Back to [index](./index.md)
- [Scope](./scope.md) — verdict criteria
- [Matrix](./matrix.md) — framework × transport view
- [Findings](./findings.md) — defects funneled into Patch 2
- [Reproducing](./reproducing.md) — how to run a single scenario
- [Class A directory](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/carry-forward) | [Class B directory](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1)
