# Per-run NHI matrix

Every campaign run that produced a `phase4-analysis.json` lands here
with its **NHI-layer verdict** rendered alongside the **substrate-layer
verdict** already shown on [Campaign runs](../runs/). One row per run,
sorted newest-first.

Each row carries:

- **Run ID** — the campaign directory under `runs/`.
- **Substrate verdict** — from `a2a-summary.json` (this is the same
  value rendered on the [Campaign runs](../runs/) dashboard).
- **NHI verdict** — derived from `phase4-analysis.json` per
  [governance §11](../governance.md#11-what-success-looks-like).
- **Scenario × arm grounding-rate matrix** — `per_cell.<scenario>/<arm>.grounding_rate_mean`.
- **Top finding** — the highest-severity `findings[*]` entry, with its
  classification (governance §8.4).
- **Cross-layer row outcome** — the consistency cell for substrate
  finding S24 (#318) vs scenario D (governance §8.3).

Rows where `phase4-analysis.json` is absent (older or interrupted
runs) are omitted from this view; their substrate verdict still
renders on [Campaign runs](../runs/).

---

{{ render_nhi_per_run_matrix() }}

---

## Reading the matrix

- **A green grounding-rate cell** (≥ 0.50) means real agent claims in
  that scenario × arm trace back to retrieved memory ops at least half
  the time. **A near-zero cell** means either the scenario didn't
  drive enough agent traffic, the agent didn't retrieve, or the
  retrievals didn't bind to claims — which one is true is in the §7
  logs of the corresponding run.
- **The cross-layer column is the headline.** YES = substrate and
  NHI layers agree on the known gap. UNKNOWN = scenario D didn't
  produce data. NO = the campaign found a contradiction between the
  layers, which is the highest-value output of the entire harness.
- **Top finding `severity: high` with `class: needs_review`** typically
  means Phase 3 produced no usable agent traffic for that cell — the
  fix is in the phase 3 driver, not ai-memory.

For the written interpretation of the most-recent run, see
[NHI insights](../nhi-insights.md). For the explainer on what the
scenarios, arms, and metrics *are*, see
[NHI assessments](../nhi-assessments.md).
