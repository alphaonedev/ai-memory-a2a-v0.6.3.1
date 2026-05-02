# Forensic audit per-run matrix

Every campaign run that produced a `phase4-analysis.json` lands here with its
`audit_forensics` block rendered: per-node chain heads, line counts, tamper
detection per node, Phase 3 op-to-audit match rate, and forged-provenance
detection rate. One row per run, sorted newest-first.

Each row carries:

- **Run ID** — the campaign directory under `runs/`.
- **Per-node chain heads** — SHA-256 of the latest audit entry on each
  node (truncated to 16 hex for display). Empty cell = audit log missing
  or empty for that node.
- **Per-node line counts** — total audit entries on each node.
- **Tamper detection** — substrate-canary verdict from
  [S26](../forensic-audit.md#the-five-properties-tested) plus the per-node
  uniform inference (S26 runs on `node-1`; we replicate the verdict to
  every node since the audit substrate is uniform across the v0.6.3.1
  mesh).
- **Op→audit match rate** — `phase3_writes_matched / phase3_writes_total`
  across every Phase 3 record's `ai_memory_ops`. The auditor's primary
  forensic-reproducibility metric.
- **Forged-provenance detection rate** — `scenario_j_runs_detected /
  scenario_j_runs_total`. Scenario J asks the receiver to detect a memory
  whose body lies about authorship; the audit log's stamped `agent_id` is
  the source of truth.
- **Legal admissibility summary** — deterministic prose summary the
  meta-analyst computes from the audit-forensics block.

Rows where `phase4-analysis.json` is absent (older or interrupted runs)
are omitted; their substrate verdict still renders on
[Campaign runs](../runs/).

---

{{ render_audit_per_run() }}

---

## Reading the matrix

- **Op→audit match rate at 1.00** means every Phase 3 NHI memory write has
  a 1:1 corresponding audit entry — the forensic-reproducibility property
  Scenario I tests.
- **Match rate strictly below 1.00** means at least one ai_memory_op did
  NOT land in the audit log, which is itself a high-severity finding (the
  audit hook silently skipped a write).
- **Tamper detection per node** — `verify_rc=0, ok=true` on every node is
  the clean-chain baseline. Any non-zero rc on a node means the chain
  itself is in an unverifiable state — the test infrastructure must
  resolve that before the run's substrate verdict can be trusted.
- **Forged-provenance detection rate** at 1.00 means every Scenario J run
  saw the receiver flag the body-vs-audit-log authorship discrepancy.
  Lower means the receiver agent failed to consult the audit log as the
  source of truth.

For the substrate-level property tests (S25/S26/S27), see the per-run
substrate cell in [Campaign runs](../runs/). For the explainer on what
the audit substrate guarantees, see [Forensic audit trail](../forensic-audit.md).
