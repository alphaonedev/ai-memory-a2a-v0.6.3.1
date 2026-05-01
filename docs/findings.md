# Findings funnel

This page is the public ledger of every defect surfaced by the v0.6.3.1 A2A campaign and where each one is in the **Patch 2 (`v0.6.3.2`)** funnel. Findings are emitted by Phase 4 meta-analysis and committed in Phase 5 per [`docs/governance.md`](governance.md) — that document is authoritative; this page is the rendered surface.

The funnel rolls up to umbrella tracking issue [`alphaonedev/ai-memory-mcp#511`](https://github.com/alphaonedev/ai-memory-mcp/issues/511).

## How findings flow (5-phase view)

Phase 4 emits findings; Phase 5 hands them off to the issue tracker. The narrow funnel:

1. **Detection (Phase 1 or Phase 3).** A scenario fails or a Phase 3 metric crosses a threshold. The runner writes a structured record — substrate failures land in `runs/<run-id>/scenario-*.json`; Phase 3 NHI logs land in `runs/<run-id>/phase3-<scenario>-<arm>-run<n>.json` per the [§7 schema](governance.md#7-json-log-schema-binding-for-all-phases).
2. **Classification (Phase 4).** The third Claude meta-analyst (no namespace access) reads the logs, computes the [§8.2 metrics](governance.md#82-computed-metrics), and assigns each finding a class from the §8.4 taxonomy below. The result lands in `phase4-analysis.json`.
3. **Sync (Phase 5).** `findings-sync.yml` opens or updates a child issue on [`alphaonedev/ai-memory-mcp`](https://github.com/alphaonedev/ai-memory-mcp/issues) for each finding tagged `carry_forward_patch2` or `carry_forward_v0_6_4`. Each issue is parent-linked to umbrella [`#511`](https://github.com/alphaonedev/ai-memory-mcp/issues/511) and labelled `bug` + `v0.6.3.2-candidate` (or `v0.6.4-candidate`).
4. **Closure.** A `v0.6.3.2-candidate` issue closes when its fix lands on the `release/v0.6.3.2` branch and the corresponding scenario flips green on the successor [`ai-memory-a2a-v0.6.3.2`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.2) campaign's first run.

A finding only enters Patch 2 if it has a scenario that reproduces it, an issue thread on `ai-memory-mcp`, the `v0.6.3.2-candidate` label, a parent-link to #511, and a milestone. Anything missing one of those does not count.

## Finding classes (per [governance §8.4](governance.md#84-findings-funnel))

The Phase 4 meta-analyst classifies each finding into exactly one of:

| Class | Meaning | Where it goes |
|---|---|---|
| **`carry_forward_patch2`** | Real defect in `ai-memory-mcp`; fix scheduled for `v0.6.3.2`. | Child issue under [#511](https://github.com/alphaonedev/ai-memory-mcp/issues/511), label `v0.6.3.2-candidate`. |
| **`carry_forward_v0_6_4`** | Real defect, but out of Patch 2 scope. Tracked for the next minor release. | Child issue under #511, label `v0.6.4-candidate`. |
| **`harness_defect`** | The test, not the product, is wrong. | Issue on the harness repo (`ai-memory-a2a-v0.6.3.1` or `ai-memory-ai2ai-gate`). |
| **`documentation_defect`** | Product is correct but its documented behavior is wrong. | Doc-fix PR against `ai-memory-mcp`. |
| **`wont_fix`** | Real finding, accepted as-is. | Recorded in `phase4-analysis.json` with rationale; no child issue opened. |
| **`needs_review`** | Default. The meta-analyst could not classify with confidence. | Escalates to the human maintainer. |

Each finding's class is recorded verbatim in `phase4-analysis.json`. Phase 5 reads that file and routes accordingly.

## Pre-campaign reds (known-open on v0.6.3.1)

These two defects the campaign knows about going in. They are encoded as the **expected-red** scenarios `S23` and `S24` so the harness can prove on every run that it can detect them. Both have a defaulted Phase 4 classification of **`carry_forward_patch2`**.

| Scenario | Issue | Severity | Title | Expected disposition | Role |
|---|---|---|---|---|---|
| `S23` | [`#507`](https://github.com/alphaonedev/ai-memory-mcp/issues/507) | medium | `config.toml` `~` expansion | **`carry_forward_patch2`** in v0.6.3.2 | Seed defect for Patch 2. Anchors umbrella tracking issue #511. |
| `S24` | [`#318`](https://github.com/alphaonedev/ai-memory-mcp/issues/318) | high | MCP stdio writes bypass federation fanout | **`carry_forward_patch2`** in v0.6.3.2 | Patch 2 candidate. Asymmetric: reads via stdio fine, writes silently diverge. NHI correlate is Phase 3 Scenario D. |

If either ever returns GREEN on this v0.6.3.1 campaign, the harness is broken — the Orchestrator halts and files a `harness_defect` rather than letting the run complete with a misleading verdict (per [governance Principle 2](governance.md#principle-2-substrate-first-gate-the-playbook-on-substrate-green)).

### Why these two specifically

- [`#507`](https://github.com/alphaonedev/ai-memory-mcp/issues/507) is a one-character-class bug — the loader does not expand `~` before passing the path to SQLite. Clean integrity check: failure mode is binary (open succeeds or it does not), no flake surface, and the fix is small enough to plausibly land in Patch 2 alone.
- [`#318`](https://github.com/alphaonedev/ai-memory-mcp/issues/318) is the more serious of the two — a silent correctness break in the federation fanout layer for one specific transport (MCP stdio). It exercises the harness's ability to detect divergence between mesh nodes rather than just per-node failures, and it has a behavioral correlate at the NHI layer (Phase 3 Scenario D — Federation honesty).

Together they cover both ends of the harness's detection range: a deterministic per-node failure and a multi-node divergence whose NHI correlate feeds the cross-layer consistency table ([governance §8.3](governance.md#83-cross-layer-consistency-table)).

Both flip to expected-green in [`ai-memory-a2a-v0.6.3.2`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.2) once Patch 2 ships.

## Cross-layer consistency findings

Findings derived from the [governance §8.3 consistency table](governance.md#83-cross-layer-consistency-table) — i.e. rows where the substrate-layer outcome and the NHI-layer correlate disagree — get a separate, higher-priority class because they mean either the substrate test or the NHI test is wrong, and either answer is structurally important.

| Row state | Disposition |
|---|---|
| Both layers RED (e.g. S24 RED + Scenario D context-loss observed on v0.6.3.1) | **Consistent.** Recorded but no new finding. |
| Both layers GREEN (e.g. S24 GREEN + Scenario D context-propagation observed on Patch 2) | **Consistent.** Recorded as the regression baseline. |
| Substrate RED, NHI GREEN | **Inconsistent — `harness_defect` candidate.** The NHI test is not exercising the bypass path; substrate is the source of truth and the playbook is broken. |
| Substrate GREEN, NHI RED | **Inconsistent — `carry_forward_patch2` candidate.** The substrate test missed a real failure mode the NHI playbook surfaced; substrate scenario needs tightening *and* the underlying defect routes to Patch 2. |

## Campaign-discovered findings

> Empty until first campaign run completes.

This section is populated by `findings-sync.yml` from the issue tracker on `ai-memory-mcp`, filtering for `v0.6.3.2-candidate` (or `v0.6.4-candidate`) issues parent-linked to umbrella [#511](https://github.com/alphaonedev/ai-memory-mcp/issues/511) and not already listed in *Pre-campaign reds*.

The expected schema, once it lands:

| Run | Source phase | Scenario / metric | Cell or arm | Issue | Severity | Class | Status |
|---|---|---|---|---|---|---|---|
| `r2` | Phase 1 / Phase 4 | (e.g. `S15` / Phase 4 grounding-rate gap) | `ironclaw / mTLS` or `arm-T / scenario-B` | `#NNN` | high / medium / low | `carry_forward_patch2` | open / fix-merged / verified |

Findings stay listed here even after their issues close — they are part of the immutable cert artifact for the v0.6.3.1 release.

## Patch 2 funnel — operator hand-off

The end-to-end funnel for an operator:

1. Phase 5 commits `releases/v0.6.3.1/summary.json` with the substrate + NHI verdicts and `phase4-analysis.json`.
2. Operator runs `findings-sync.yml` (workflow_dispatch). The workflow opens / updates each finding's child issue under [#511](https://github.com/alphaonedev/ai-memory-mcp/issues/511).
3. The Patch 2 candidate list under #511 is the canonical view of "everything Patch 2 needs to fix." It rolls up to the `v0.6.3.2` milestone on `ai-memory-mcp`.
4. When every parent-linked issue's fix has merged and the corresponding scenarios are green on the successor [`ai-memory-a2a-v0.6.3.2`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.2) campaign's first run, #511 closes.

See the [runbook](runbook.md#patch-2-funnel) for the operator's exact button-pushing.

## Cross-links

- [Governance](governance.md) §8 — authoritative finding classification
- [Scope](scope.md) — verdict criteria
- [Matrix](matrix.md) — substrate cells + Phase 3 cells + cross-layer consistency table
- [Runbook](runbook.md) — Phase 5 hand-off mechanics
- Subject under test: [`alphaonedev/ai-memory-mcp`](https://github.com/alphaonedev/ai-memory-mcp)
- Umbrella tracking issue: [`alphaonedev/ai-memory-mcp#511`](https://github.com/alphaonedev/ai-memory-mcp/issues/511)
- Patch 2 milestone: `v0.6.3.2` on [`alphaonedev/ai-memory-mcp/milestones`](https://github.com/alphaonedev/ai-memory-mcp/milestones)
- Successor repo: [`alphaonedev/ai-memory-a2a-v0.6.3.2`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.2) (will exist when Patch 2 tags)
