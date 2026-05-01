# Matrix — framework × transport

The framework × transport matrix is the spatial layout of the campaign. Rows are A2A frameworks (`ironclaw`, `hermes`, `openclaw`, plus a `mixed` cross-framework row); columns are transports (`off`, `TLS`, `mTLS`). Each cell represents the full carry-forward sweep (`S1` – `S8` × 8 scenarios) plus any v0.6.3.1-specific scenarios that target that cell.

A cell can be in one of four states. `PENDING` means no run has produced data for that cell yet. `RUNNING` means a campaign is in flight against that cell. `GREEN` means the most recent run produced an entirely passing sweep (with `S23` and `S24` correctly red on the `CERT` cell). `RED` means at least one scenario failed unexpectedly — i.e. a regression on `S1` – `S8` or an unexpected failure on `S9` – `S22`. Expected reds (`S23`, `S24`) do not turn the cell red.

The single cell that gates the campaign verdict is **`ironclaw / mTLS`** — the certification cell. Other cells are regression or stretch and inform reliability claims but do not gate the cert.

## Current state

Last run id: `r0` (placeholder — no campaign has executed yet).
Last run timestamp: `2026-04-30` (placeholder — repo scaffolding date).
Source: [`releases/v0.6.3.1/summary.json`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/releases/v0.6.3.1/summary.json).

| Framework | `off` | `TLS` | `mTLS` |
|---|---|---|---|
| **ironclaw** | regression — `PENDING` (r0, 2026-04-30) | regression — `PENDING` (r0, 2026-04-30) | **CERT cell** — `PENDING` (r0, 2026-04-30) |
| **hermes** | regression — `PENDING` (r0, 2026-04-30) | regression — `PENDING` (r0, 2026-04-30) | regression — `PENDING` (r0, 2026-04-30) |
| **openclaw** | regression — `PENDING` (r0, 2026-04-30) | regression — `PENDING` (r0, 2026-04-30) | regression — `PENDING` (r0, 2026-04-30) |
| **mixed** (ironclaw↔hermes, ironclaw↔openclaw, hermes↔openclaw) | regression — `PENDING` (r0, 2026-04-30) | regression — `PENDING` (r0, 2026-04-30) | stretch — `PENDING` (r0, 2026-04-30) |

Once a real campaign run lands, each cell links to its summary at `https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/runs/<run-id>/summary.json` (e.g. `runs/r1/summary.json`). The `r0` link does not resolve — `r0` is a placeholder for "no run yet".

## Regeneration

This page is intended to be regenerated from [`releases/v0.6.3.1/summary.json`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/releases/v0.6.3.1/summary.json) by the `publish-pages.yml` workflow. For now it is **manually authored with `PENDING` placeholders** — the regeneration step will overwrite the table once the workflow lands.

The `summary.json` schema flattens the matrix into nine keys (`<framework>_<transport>`) for the three pure rows; the `mixed` row is recorded out-of-band in the per-run summaries under `runs/<id>/`. The publish step reads those nine keys plus the `last_run_id` and `updated_at` fields to render the table cells.

## Cell legend

The `regression` / `CERT` / `stretch` labels in the table describe the role each cell plays in the cert, not its pass/fail state. They do not change between runs.

- **`regression`** — a cell that is exercised every campaign run and reported in the matrix, but does not gate the verdict on its own. Failure here surfaces as a finding and may downgrade the verdict, but a single regression cell going red does not by itself flip the campaign to `FAIL` — that determination is made at the scenario level (`S1` – `S22`).
- **`CERT`** — the single cell that gates the verdict. For v0.6.3.1 this is `ironclaw / mTLS`. Target: 48 / 48 on the carry-forward sweep, plus all of `S9` – `S22` green and `S23` / `S24` red as expected. If this cell is anything other than fully green-with-expected-reds, the verdict cannot be `CERT`.
- **`stretch`** — a cell run on a best-effort basis, typically nightly rather than per-campaign. Currently the only stretch cell is `mixed / mTLS`. A red stretch cell does not affect the verdict but is reported transparently.

## How a cell maps to scenarios

- The eight carry-forward scenarios `S1` – `S8` run on every cell (`9 cells × 8 scenarios = 72 sweep entries` per campaign, including the `mixed` row).
- The fourteen new-surface scenarios `S9` – `S22` run primarily on the `CERT` cell (`ironclaw / mTLS`). `S21` (endianness) also runs on a `mixed-arch / mTLS` topology that crosses x86_64 and arm64 nodes.
- The two expected-red scenarios `S23` and `S24` run on the `CERT` cell only.

Total scenario executions per full campaign on the `CERT` cell: `8 (carry-forward) + 14 (S9–S22) + 2 (expected-red) = 24` distinct scenarios; the carry-forward sweep itself is `8 scenarios × 6 sub-cases = 48` measurements (the 48 / 48 target).

## Cross-links

- Back to [index](./index.md)
- [Scope](./scope.md) — what is in / out of cert
- [Scenarios](./scenarios.md) — per-scenario status
- [Reproducing](./reproducing.md) — how to populate the matrix yourself
- Source data: [`releases/v0.6.3.1/summary.json`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/releases/v0.6.3.1/summary.json)
- Topology spec on the umbrella: [`ai-memory-ai2ai-gate/topology`](https://github.com/alphaonedev/ai-memory-ai2ai-gate)
