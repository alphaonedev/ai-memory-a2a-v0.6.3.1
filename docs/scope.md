# Scope — v0.6.3.1 First-Principles campaign

What this campaign tests, what it deliberately does not test, and what each verdict in `releases/v0.6.3.1/summary.json` means.

This page is the docsite-rendered companion to repo-root [`SCOPE.md`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/SCOPE.md). The authoritative specification of *how* the campaign behaves is [`docs/governance.md`](governance.md) — if anything below conflicts with `governance.md`, governance wins.

## Subject under test

| Field | Value |
|---|---|
| Tag | [`v0.6.3.1`](https://github.com/alphaonedev/ai-memory-mcp/releases/tag/v0.6.3.1) (cut 2026-04-30) |
| Schema | `v19` (migration ladder `v15` → `v17` → `v18` → `v19`) |
| Repo | [`alphaonedev/ai-memory-mcp`](https://github.com/alphaonedev/ai-memory-mcp) |
| CLI surfaces added since v0.6.3 | `ai-memory boot`, `install <agent>`, `wrap <agent>`, `logs`, `audit verify`, `doctor` |
| Config surfaces added | `[boot]`, `[logging]`, `[audit]`, `[audit.compliance.{soc2,hipaa,gdpr,fedramp}]` |
| Tooling claim being verified | 1,886 lib tests, 49+ integration tests, 93.84% line coverage, 17 documented integrations × 10 platforms, 7-section doctor health dashboard |
| Campaign repo | [`alphaonedev/ai-memory-a2a-v0.6.3.1`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1) |
| Verdict surface | [`releases/v0.6.3.1/summary.json`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/releases/v0.6.3.1/summary.json) (schema v2) |
| Umbrella issue | [`ai-memory-mcp#511`](https://github.com/alphaonedev/ai-memory-mcp/issues/511) |

The `doctor` surface is the v0.6.3.1 promotion of `R7` from [ROADMAP2 §7.2](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md). The `budget_tokens` recall is the recovered commitment `R1`.

## Agent scope

In scope (Principle 6 — scope discipline; see [governance §2.6](governance.md#principle-6-scope-discipline-this-node-these-agents-this-release)):

- **IronClaw** — Rust framework, primary cert agent.
- **Hermes** — counterpart agent for cross-framework substrate cells and Phase 3 NHI playbook.
- **OpenClaw** — first-class third agent framework, in scope for v0.6.3.1 but **dispatched separately from a higher-resource workstation via the [local Docker mesh](local-docker-mesh.md)** (16 GB+ per container — Basic-tier DO droplets used for IronClaw/Hermes don't have enough memory). Per Principle 6, OpenClaw runs produce their own scope-tagged artifacts; the Orchestrator joins all three frameworks via `release=v0.6.3.1` linkage but never collapses them across framework boundaries (cross-scope contamination invalidates the artifact).

## What carries forward from the v0.6.3 cert

Eight base scenarios `S1` – `S8` from the umbrella [testbook](testbook.md) run unchanged on the v0.6.3.1 binary:

| Scenario | What it asserts |
|---|---|
| S1 | Per-agent write + read |
| S2 | Shared-context handoff |
| S3 | Targeted share |
| S4 | Federation-aware agents |
| S5 | Consolidation + curation |
| S6 | Contradiction detection |
| S7 | Scoping visibility |
| S8 | Auto-tagging |

These must remain green. Any regression on `S1` – `S8` is a release-blocker for the campaign verdict — they are not Patch 2 candidates.

The certification cell is **`ironclaw / mTLS`** at the carry-forward sweep. Target: 48 / 48 on that cell.

## What is new for v0.6.3.1

Sixteen scenarios `S9` – `S24` exercise the surfaces added in this release:

| ID | Surface | Assertion |
|---|---|---|
| S9 | `ai-memory boot` multi-node | Boot manifest agreement on `version`, `schema_version`, `tier` across 4 nodes. |
| S10 | `ai-memory doctor` cross-node | Storage / Index / Recall / Sync sections agree (in-flight delta tolerated). |
| S11 | `ai-memory install <agent>` recipe handoff | Recipes installed at different nodes share the same store cleanly. |
| S12 | `ai-memory wrap <agent>` cross-vendor | Boot context delivered for codex / gemini / aider / ollama. |
| S13 | `ai-memory audit verify` tamper-evident | Hash chain verifies independently per node; corruption detected. |
| S14 | `ai-memory logs` operator surface | Filters work uniformly; privacy default OFF holds. |
| S15 | **R1** `budget_tokens` recall | Same query + budget → same ranked head on federated peers. |
| S16 | **Capabilities v2** honesty cross-mesh | Asymmetric capabilities surface, never absorb. |
| S17 | **G9** webhook fanout | link / promote / delete / consolidate fire from any originating node. |
| S18 | **G4** embedding-dim integrity | Mixed-dim writes refused at boundary. |
| S19 | **G5** archive/restore preserves embeddings | Archive at A → restore at B keeps embedding + tier + expiry. |
| S20 | **G6** `on_conflict` policy | Concurrent same-key writes deterministic. |
| S21 | **G13** endianness magic byte | x86_64 + arm64 nodes exchange f32 BLOBs without silent corruption. |
| S22 | Schema **v19** migration | Heterogeneous mesh; warn manifest variant fires on mismatch. |
| **S23** | Issue [#507](https://github.com/alphaonedev/ai-memory-mcp/issues/507) `~` expansion | Tilde in `db` field expanded before SQLite open. **Expected RED on v0.6.3.1.** |
| **S24** | Issue [#318](https://github.com/alphaonedev/ai-memory-mcp/issues/318) MCP stdio fanout | MCP stdio writes trigger federation fanout. **Expected RED on v0.6.3.1.** |

`S23` and `S24` are intentionally expected to fail. They correspond to known-open OSS bugs that will close in **Patch 2 (`v0.6.3.2`)**. Their inclusion is an integrity check on the harness itself: if either ever turned green on v0.6.3.1, the harness would be lying. Both flip to expected-green in the successor `ai-memory-a2a-v0.6.3.2` repo.

## What is deferred (out of scope)

Per [governance Appendix B](governance.md#appendix-b-out-of-scope-for-absolute-clarity), this campaign deliberately does not cover:

- **Infrastructure provisioning, mTLS cert management, Terraform.** Confirmed-good before Phase 0 by a separate process.
- **Auto-tagging via Ollama.** Opt-in feature requiring `s-4vcpu-16gb` droplet; deferred per the [ai2ai-gate README](https://github.com/alphaonedev/ai-memory-ai2ai-gate).
- **`memory_share` / [#311](https://github.com/alphaonedev/ai-memory-mcp/issues/311) targeted-share scenario.** Depends on a v0.6.0.1 capability upstream of v0.6.3.1; revisit for v0.6.4.
- **Patch 2 (v0.6.3.2) regression run.** Separate campaign in `ai-memory-a2a-v0.6.3.2`, using this repo as a template.
- **v0.7 attestation (Ed25519 signing of `memory_links`).** Covered by the v0.7 cert.
- **v0.8 typed cognition / CRDTs / curator daemon.** Covered by the v0.8 cert.
- **Performance / scale benchmarking.** Owned by the ship-gate, not this correctness campaign.

Deferred work is not a gap in the v0.6.3.1 cert — it is owned by a different per-release cert.

## Verdict criteria — two truth-claims, two evidence streams

Per [Principle 1](governance.md#principle-1-two-truth-claims-two-evidence-streams-never-conflated), the campaign emits **two independent verdicts** in `releases/v0.6.3.1/summary.json` (schema v2). They are stored in separate top-level keys (`substrate_verdict`, `nhi_verdict`) and **never collapsed**.

### Substrate verdict (Phase 1 — binary, reproducible)

Read this for ship / no-ship gating. Computed from `S1` – `S24` outcomes on the `ironclaw / mTLS` cert cell.

| Value | Meaning |
|---|---|
| `CERT` | All `S1` – `S22` GREEN; `S23` and `S24` RED as expected; cert cell is 48 / 48. The release passes A2A certification on this tag. |
| `PARTIAL — pending Patch 2` | Same as `CERT` except `S23` and / or `S24` are still RED. **This is the expected v0.6.3.1 outcome** — see [governance §2.2](governance.md#principle-2-substrate-first-gate-the-playbook-on-substrate-green). The release is conditionally certified pending Patch 2. |
| `FAIL` | Any other red — including any regression on `S1` – `S8` or any unexpected failure on `S9` – `S22`. Each red opens or updates a `bug` + `v0.6.3.2-candidate` issue parent-linked to [#511](https://github.com/alphaonedev/ai-memory-mcp/issues/511). |

If `S23` or `S24` flips GREEN, the harness halts the campaign and files a harness-integrity issue. Substrate is not allowed to lie.

### NHI verdict (Phase 3 — behavioral, statistical, n=3)

Read this to assess whether ai-memory measurably changes NHI behavior under realistic agent workloads. Computed from the four-arm × four-scenario × n=3 = 48-run Phase 3 playbook.

The NHI verdict reports per-scenario treatment effects (Arm-T vs each control arm) and a cross-layer consistency assessment, never collapsed into a single ship/no-ship bit. See [governance §6](governance.md#6-phase-3-autonomous-nhi-playbook) for the full scenario design and [matrix](matrix.md) for the cell-by-cell view.

A campaign that ships a green substrate badge but produces no Phase 3 behavioral evidence does **not** satisfy the v0.6.3.1 cert.

## Cross-links

- [Governance (authoritative)](governance.md)
- [Verdict matrix](matrix.md) — substrate cells + Phase 3 arms × scenarios
- [Findings funnel](findings.md) — defects routed into Patch 2
- [Operator runbook](runbook.md) — phase-by-phase execution
- Repo-root [`SCOPE.md`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/SCOPE.md)
- Repo-root [`README.md`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/README.md) — phase structure overview
- Umbrella spec: [`ai-memory-ai2ai-gate`](https://github.com/alphaonedev/ai-memory-ai2ai-gate)
