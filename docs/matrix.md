# Verdict matrix

The campaign's verdict surface is two-layered (Principle 1 — two truth-claims, two evidence streams). This page renders both layers from [`releases/v0.6.3.1/summary.json`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/releases/v0.6.3.1/summary.json) (schema v2).

[`docs/governance.md`](governance.md) is authoritative for what each cell means and how each verdict is derived. This page is the rendered view.

## Layer 1 — Substrate cert matrix

Phase 1 runs the carry-forward sweep (`S1` – `S8`) plus the v0.6.3.1-specific scenarios (`S9` – `S24`) on the framework × transport grid. Per [governance §2.6](governance.md#principle-6-scope-discipline-this-node-these-agents-this-release), only IronClaw and Hermes are in scope; OpenClaw runs in a separate campaign.

| Framework | `off` | `TLS` | `mTLS` |
|---|---|---|---|
| **ironclaw** | regression | regression | **CERT cell** (target 48 / 48) |
| **hermes** | regression | regression | regression |

Six cells total. The single cell that gates the substrate verdict is **`ironclaw / mTLS`** — the certification cell. The carry-forward sweep on that cell is `8 scenarios × 6 sub-cases = 48` measurements (the 48 / 48 target). Other cells inform reliability claims but do not gate the cert on their own.

### Cell legend

The role labels in the table describe what each cell contributes to the cert, not its pass/fail state. They do not change between runs.

- **`regression`** — exercised every campaign run and reported, but does not gate the verdict on its own. A red regression cell surfaces as a finding and may downgrade the verdict.
- **`CERT`** — the single cell that gates the substrate verdict. Target: all of `S1` – `S22` GREEN, `S23` / `S24` RED as expected, and the carry-forward sweep at 48 / 48. Anything less than that on this cell prevents `substrate_verdict = "CERT"` (or `"PARTIAL — pending Patch 2"`).

### Cell states

A cell can be in one of four states. `PENDING` means no run has produced data for that cell yet. `RUNNING` means a campaign is in flight. `GREEN` means the most recent run produced an entirely passing sweep (with `S23` / `S24` correctly RED on the cert cell). `RED` means at least one scenario failed unexpectedly. Expected-RED scenarios (`S23`, `S24`) do not turn the cert cell red.

### Rendering convention

The page is regenerated from `releases/v0.6.3.1/summary.json` by `mkdocs-macros` (configured via [`main.py`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/main.py)). The macro reads `substrate_verdict.matrix` (six keys: `<framework>_<transport>` for `ironclaw` / `hermes` × `off` / `tls` / `mtls`) plus `campaign.last_run_id` and `campaign.updated_at`.

Until a real campaign run lands, every cell renders as `PENDING` and the source-of-truth row at the top of `summary.json` reads:

```json
{
  "substrate_verdict": {
    "value": "PENDING",
    "expected_on_v0_6_3_1": "PARTIAL — pending Patch 2",
    "matrix": { "ironclaw_off": "PENDING", "ironclaw_tls": "PENDING", "ironclaw_mtls": "PENDING",
                "hermes_off": "PENDING",   "hermes_tls": "PENDING",   "hermes_mtls": "PENDING" }
  }
}
```

Once a real run lands, each cell links to its summary at `runs/<run-id>/summary.json`.

## Layer 2 — Phase 3 NHI playbook matrix

Per [governance §6](governance.md#6-phase-3-autonomous-nhi-playbook), Phase 3 runs four scenarios × four arms × n=3 = **48 runs total**. This matrix is independent of the substrate matrix — it is the behavioral evidence stream.

### Scenarios × arms (16 cells, n=3 each)

|  | Arm-0 (Cold) | Arm-1 (Isolated) | Arm-2 (Stubbed) | Arm-T (Treatment) |
|---|---|---|---|---|
| **A — Decision provenance** | n=3 | n=3 | n=3 | n=3 |
| **B — Constraint propagation** | n=3 | n=3 | n=3 | n=3 |
| **C — Correction memory** | n=3 | n=3 | n=3 | n=3 |
| **D — Federation honesty (S24 NHI correlate)** | n=3 | n=3 | n=3 | n=3 |

Total: **16 cells × 3 runs = 48 Phase 3 runs.** Mirrors the 48-cell substrate target by accident-of-arithmetic, not by design.

### Arm definitions (per [governance §6.2](governance.md#62-three-control-arms-per-your-direction))

| Arm | Configuration | What it isolates |
|---|---|---|
| **Arm-0 — Cold** | ai-memory disabled at MCP layer. Agents see no memory tool. | Behavior baseline with no shared state at all. |
| **Arm-1 — Isolated** | ai-memory enabled; each agent confined to its own private namespace. No cross-agent reads. | "Did ai-memory help *this agent*" vs. "did ai-memory help *cross-agent context*". |
| **Arm-2 — Stubbed** | In-process dict standing in for ai-memory. Persists within a run, lost between runs. No federation. | ai-memory's distinctive features (federation, persistence, scope, audit) vs. "any memory at all". |
| **Arm-T — Treatment** | ai-memory v0.6.3.1 live, federated, mTLS, full configuration. | The actual product. |

Reading the four arms together yields a clean attribution chain:

- **Arm-T vs Arm-0** — total ai-memory contribution.
- **Arm-T vs Arm-2** — contribution attributable to ai-memory's distinctive features.
- **Arm-T vs Arm-1** — contribution attributable specifically to cross-agent sharing.

### Bounding (per [governance §6.3](governance.md#63-bounding-autonomy))

Every Phase 3 run terminates on the first of:

- **Max turns:** 12 per agent per scenario.
- **Max ai-memory operations:** 50 per agent per scenario.
- **Wall-clock timeout:** 10 minutes per scenario per arm.

A run that hits any cap terminates with a `cap_reached` flag in the JSON log; this is treated separately from `task_complete` and `refusal` in the Phase 4 metrics.

### Rendering convention

The Phase 3 cell renderer reads `nhi_verdict.scenarios` from `summary.json`. For scenarios A / B / C the cell shows `treatment_grounding_rate` plus `vs_cold` / `vs_isolated` / `vs_stubbed` deltas; for scenario D the cell shows `treatment_recall_hit_rate` against its `expected_on_v0_6_3_1` band (`low/zero` consistent with substrate S24 RED).

## Layer 3 — Cross-layer consistency table

Per [governance §8.3](governance.md#83-cross-layer-consistency-table), every substrate finding with an NHI-layer correlate is rendered in a consistency table:

| Substrate finding | Substrate verdict | NHI correlate | NHI observation | Consistent? |
|---|---|---|---|---|
| S24 ([#318](https://github.com/alphaonedev/ai-memory-mcp/issues/318)) MCP stdio bypass federation | RED (expected on v0.6.3.1) | Scenario D — Federation honesty | Hermes does **not** recall IronClaw's MCP-stdio write within the settle window | YES (expected on v0.6.3.1; flips to YES with both GREEN on Patch 2) |
| (additional rows as findings emerge) | | | | |

**Inconsistent rows are the most valuable output of the entire campaign.** They mean either the substrate test or the NHI test is wrong, and either answer is high-value. The renderer flags inconsistent rows in red and links them to the Phase 4 narrative in [`phase4-analysis.json`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/runs/) for the run.

## Substrate vs NHI verdict — never collapsed

The two verdicts in `summary.json` schema v2 are top-level siblings (`substrate_verdict`, `nhi_verdict`) by design. Reader convention:

- Use **`substrate_verdict`** for ship / no-ship gating. Binary, reproducible.
- Use **`nhi_verdict`** to assess utility delta of ai-memory under realistic agent workloads. Behavioral, statistical (n=3 per cell, 48 runs).

Schema v1 had a single `campaign.verdict` field that conflated the two. v2 separates them per Principle 1; the schema-change rationale is captured in `summary.json` itself under `schema_change_notes`.

## Cross-links

- [Governance](governance.md) — authoritative
- [Scope](scope.md) — what is in / out of cert
- [Findings](findings.md) — defects funneled into Patch 2
- [Runbook](runbook.md) — how to populate the matrix
- Source data: [`releases/v0.6.3.1/summary.json`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/releases/v0.6.3.1/summary.json)
- Phase log schema: [`scripts/schema/phase-log.schema.json`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/scripts/schema/phase-log.schema.json)
