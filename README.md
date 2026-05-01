# ai-memory A2A campaign — v0.6.3.1

Per-release **agent-to-agent (A2A) integration certification** campaign for [`ai-memory v0.6.3.1`](https://github.com/alphaonedev/ai-memory-mcp/releases/tag/v0.6.3.1). 4-node DigitalOcean mesh + local-docker mesh fallback.

| Verdict | Run | Cell | Last updated |
|---|---|---|---|
| `PENDING` | r0 | ironclaw / mTLS (cert) | — |

> **Status.** Repo scaffolding. First campaign run pending.
> **Subject under test.** ai-memory `v0.6.3.1` (tag pinned).
> **Funnel.** Findings roll into [**Patch 2** (`v0.6.3.2`)](https://github.com/alphaonedev/ai-memory-mcp/issues/507) via the umbrella tracking issue.

## Why this repo exists

The umbrella [`ai-memory-ai2ai-gate`](https://github.com/alphaonedev/ai-memory-ai2ai-gate) keeps the **specification** (testbook, baseline, scenario contracts, v1-GA criteria). This repo is a **per-release execution + evidence** cousin: the campaign that exercises ai-memory `v0.6.3.1` against the spec, emits cert artifacts, and funnels every defect into the next patch release.

The pattern going forward: `ai-memory-a2a-v<version>` per release. Patch 2 will get its own `ai-memory-a2a-v0.6.3.2` repo when it tags. The umbrella stays the spec; per-release repos hold the evidence.

## What it tests

Two classes of scenarios.

### Class A — carry-forward (must remain green from v0.6.3 cert)

Eight base scenarios from the umbrella's testbook (S1 per-agent write+read, S2 shared-context handoff, S3 targeted share, S4 federation-aware agents, S5 consolidation+curation, S6 contradiction detection, S7 scoping visibility, S8 auto-tagging) across the matrix:

| Framework | off | TLS | mTLS |
|---|---|---|---|
| **ironclaw** | regression | regression | **CERT cell** (target 48 / 48) |
| **hermes** | regression | regression | regression |
| **openclaw** | regression | regression | regression |
| mixed (ironclaw↔hermes, ironclaw↔openclaw, hermes↔openclaw) | regression | regression | stretch |

### Class B — v0.6.3.1-specific (new surfaces)

| ID | Surface | What it asserts |
|---|---|---|
| S9 | `ai-memory boot` multi-node | Boot manifest agreement on `version`, `schema_version`, `tier` across 4 nodes. |
| S10 | `ai-memory doctor` cross-node | Storage / Index / Recall / Sync sections agree (in-flight delta tolerated). |
| S11 | `ai-memory install <agent>` recipe handoff | Recipes installed at different nodes share the same store cleanly. |
| S12 | `ai-memory wrap <agent>` cross-vendor | Boot context delivered consistently for codex / gemini / aider / ollama. |
| S13 | `ai-memory audit verify` tamper-evident | Hash chain verifies independently per node; corruption detected, not absorbed. |
| S14 | `ai-memory logs` operator surface | Filters work uniformly; privacy default OFF holds. |
| S15 | **R1** `budget_tokens` recall | Same query + budget on federated peers → same ranked head. |
| S16 | **Capabilities v2** honesty cross-mesh | Asymmetric capabilities surface, never absorb. |
| S17 | **G9** webhook fanout | link / promote / delete / consolidate fire from any originating node. |
| S18 | **G4** embedding-dim integrity | Mixed-dim writes refused at boundary; `dim_violations` surfaced per node. |
| S19 | **G5** archive/restore preserves embeddings | Archive at A → restore at B keeps embedding + tier + expiry. |
| S20 | **G6** `on_conflict` policy | Concurrent same-key writes → deterministic outcome per policy. |
| S21 | **G13** endianness magic byte | x86_64 + arm64 nodes exchange f32 BLOBs without silent corruption. |
| S22 | Schema **v19** migration | Heterogeneous mesh; warn manifest variant fires on mismatch. |
| **S23** | **Issue #507** `~` expansion | Tilde in `db` field expanded before SQLite open. **Expected RED on v0.6.3.1; GREEN on Patch 2.** |
| **S24** | **Issue #318** MCP stdio fanout | MCP stdio writes trigger federation fanout. **Expected RED on v0.6.3.1; GREEN on Patch 2.** |

S23 and S24 are **expected-red** on v0.6.3.1 — they prove the harness can detect the defects we already know about before we trust any other verdict.

## Repo layout

```
.
├── README.md                  this file
├── LICENSE                    Apache 2.0
├── CHANGELOG.md               campaign run log
├── SCOPE.md                   delta vs v0.6.3 cert
├── LINEAGE.md                 link to umbrella spec + ship-gate cert
├── harness/                   terraform/, docker-compose.local.yml, ansible/
├── scenarios/
│   ├── carry-forward/         S1 – S8 (umbrella spec)
│   └── v0.6.3.1/              S9 – S24 (per-release)
├── runs/                      per-campaign JSON evidence
├── releases/v0.6.3.1/         summary.json + certification.md
├── docs/                      GitHub Pages source (Jekyll)
└── .github/workflows/         a2a-campaign.yml + publish-pages.yml + findings-sync.yml
```

## Reproducing locally

```sh
# 4-node OpenClaw mesh in docker
cd harness && docker compose -f docker-compose.local.yml up
```

Full DigitalOcean reproduction: see [`harness/terraform/README.md`](harness/terraform/README.md) (TBD).

## Cross-links

- **Spec / testbook / baseline.** [`alphaonedev/ai-memory-ai2ai-gate`](https://github.com/alphaonedev/ai-memory-ai2ai-gate)
- **Ship-gate (release testing).** [`alphaonedev/ai-memory-ship-gate`](https://github.com/alphaonedev/ai-memory-ship-gate)
- **Aggregator landing.** [`alphaonedev.github.io/ai-memory-test-hub`](https://alphaonedev.github.io/ai-memory-test-hub/) → `/releases/v0.6.3.1/`
- **Subject under test.** [`alphaonedev/ai-memory-mcp`](https://github.com/alphaonedev/ai-memory-mcp) tag `v0.6.3.1`
- **Patch 2 funnel.** Umbrella tracking issue (TBD) on `ai-memory-mcp`; seed defect [#507](https://github.com/alphaonedev/ai-memory-mcp/issues/507)

## License

Apache 2.0. See [`LICENSE`](LICENSE).
