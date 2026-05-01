# Scope — what's specific to v0.6.3.1

This document describes the **delta** between this per-release campaign and the v0.6.3 cert in the umbrella [`ai-memory-ai2ai-gate`](https://github.com/alphaonedev/ai-memory-ai2ai-gate).

## Subject under test

- **Tag.** [`v0.6.3.1`](https://github.com/alphaonedev/ai-memory-mcp/releases/tag/v0.6.3.1) (shipped 2026-04-30)
- **Schema.** v19 (migration ladder v15 → v17 → v18 → v19, verified on production data)
- **CLI surface added since v0.6.3.** `ai-memory boot`, `install <agent>`, `wrap <agent>`, `logs`, `audit verify`, `doctor` (the last is the v0.6.3.1 promotion of R7 from ROADMAP2 §7.2)
- **Config surfaces added.** `[boot]`, `[logging]`, `[audit]`, `[audit.compliance.{soc2,hipaa,gdpr,fedramp}]`
- **Tooling claim being verified.** 1,886 lib tests, 49+ integration tests, 93.84% line coverage, 17 documented integrations × 10 platforms, 7-section doctor health dashboard

## What's carried forward from v0.6.3 cert

The eight base scenarios `S1 – S8` from the umbrella testbook are run unchanged. They must remain green on v0.6.3.1; any regression is a release-blocker for the campaign verdict.

The `ironclaw / mTLS` cell is the certification cell (target 48/48). Other cells are regression / stretch.

## What's new for v0.6.3.1

Sixteen scenarios (`S9 – S24`) covering the new CLI surface, the new config surfaces, the audit log, the recovered commitments (`budget_tokens` R1, doctor R7), and the audit findings absorbed into v0.6.3.1 (G4, G5, G6, G9, G13).

S23 and S24 are **expected-red** — they correspond to known-open OSS bugs ([#507](https://github.com/alphaonedev/ai-memory-mcp/issues/507) and [#318](https://github.com/alphaonedev/ai-memory-mcp/issues/318) respectively) that will be closed in **Patch 2 (`v0.6.3.2`)**. Their inclusion here proves the campaign harness can detect defects we already know about — the **integrity check** on the test infrastructure itself.

## What's deferred

- v0.7 attestation (Ed25519 signing of `memory_links`) — covered by the v0.7 cert when it tags.
- v0.8 typed cognition / CRDTs / curator daemon — covered by the v0.8 cert.
- Full mixed-framework × mTLS sweep (cell currently `stretch`) — not blocking for v0.6.3.1 cert; kept as nightly regression.

## Verdict criteria

- **CERT** — all carry-forward `S1 – S8` green; all new scenarios `S9 – S22` green; `S23` and `S24` red (expected); ironclaw / mTLS cell 48/48.
- **PARTIAL — pending Patch 2** — same as CERT but with `S23` and / or `S24` red and counted toward the Patch-2 funnel rather than treated as regressions.
- **FAIL** — any other red. Each red gets a finding issue on `ai-memory-mcp`.
