# Scope — v0.6.3.1 campaign

What is in scope for this per-release A2A campaign, what is deferred to later certs, and what counts as `CERT` / `PARTIAL` / `FAIL`.

This is the public-facing companion to [`SCOPE.md`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/SCOPE.md) at the repo root. The repo-root copy is the source of truth; this page mirrors it for Pages readers.

## Subject under test

| Field | Value |
|---|---|
| Tag | [`v0.6.3.1`](https://github.com/alphaonedev/ai-memory-mcp/releases/tag/v0.6.3.1) (shipped 2026-04-30) |
| Schema | `v19` (migration ladder `v15` → `v17` → `v18` → `v19`, verified on production data) |
| Repo | [`alphaonedev/ai-memory-mcp`](https://github.com/alphaonedev/ai-memory-mcp) |
| CLI surfaces added since v0.6.3 | `ai-memory boot`, `install <agent>`, `wrap <agent>`, `logs`, `audit verify`, `doctor` |
| Config surfaces added | `[boot]`, `[logging]`, `[audit]`, `[audit.compliance.{soc2,hipaa,gdpr,fedramp}]` |
| Tooling claim being verified | 1,886 lib tests, 49+ integration tests, 93.84% line coverage, 17 documented integrations × 10 platforms, 7-section doctor health dashboard |

The `doctor` surface in particular is the v0.6.3.1 promotion of `R7` from [ROADMAP2 §7.2](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md). The `budget_tokens` recall is the recovered commitment `R1`.

## What is carried forward from v0.6.3 cert

The eight base scenarios `S1` – `S8` from the [umbrella testbook](https://github.com/alphaonedev/ai-memory-ai2ai-gate) are run unchanged on the v0.6.3.1 binary. They must remain green. Any regression is a release-blocker for the campaign verdict — these are not Patch 2 candidates.

The certification cell is `ironclaw / mTLS` at the carry-forward sweep. Target: 48 / 48 on that cell. Other cells are regression or stretch and do not gate the verdict on their own.

## What is new for v0.6.3.1

Sixteen scenarios `S9` – `S24` exercise the surfaces added in this release:

- New CLI: `boot`, `doctor`, `install`, `wrap`, `audit verify`, `logs` (`S9` – `S14`).
- Recovered commitments: `R1` `budget_tokens` (`S15`), Capabilities v2 honesty (`S16`).
- Audit findings absorbed into v0.6.3.1: `G9` webhook fanout (`S17`), `G4` embedding-dim integrity (`S18`), `G5` archive/restore (`S19`), `G6` `on_conflict` policy (`S20`), `G13` endianness magic byte (`S21`).
- Schema `v19` migration on a heterogeneous mesh (`S22`).
- Two **expected-red** integrity checks (`S23`, `S24`) — see below.

## Expected-red scenarios

`S23` and `S24` are intentionally expected to fail on v0.6.3.1. They correspond to known-open OSS bugs that will be closed in **Patch 2 (`v0.6.3.2`)**:

- `S23` → [`#507` — config.toml `~` expansion](https://github.com/alphaonedev/ai-memory-mcp/issues/507) (medium severity, the seed defect for Patch 2).
- `S24` → [`#318` — MCP stdio writes bypass federation fanout](https://github.com/alphaonedev/ai-memory-mcp/issues/318) (high severity).

Their inclusion is an integrity check on the harness itself. If `S23` or `S24` came back green on v0.6.3.1, the harness would be lying — we know the underlying defects exist on this tag because they have OSS issue threads with reproductions. Both flip to expected-green in the successor `ai-memory-a2a-v0.6.3.2` repo.

## What is deferred

This campaign deliberately does not cover:

- **v0.7 attestation.** Ed25519 signing of `memory_links` is on the v0.7 cert. Not in scope here.
- **v0.8 typed cognition / CRDTs / curator daemon.** Covered by the v0.8 cert when v0.8 tags.
- **Full mixed-framework × mTLS sweep.** The `mixed / mTLS` cell in the matrix is currently `stretch` — kept as nightly regression and not blocking for the v0.6.3.1 verdict.
- **Performance / scale benchmarking.** The ship-gate covers performance regressions. This campaign is correctness-focused.
- **Provider-specific surfaces beyond the four wrap targets.** `wrap` is exercised against `codex`, `gemini`, `aider`, `ollama`. Other vendors are not in the v0.6.3.1 cert sweep.

Deferred work is not a gap in the v0.6.3.1 cert — it is owned by a different per-release cert.

## Verdict criteria

The campaign emits exactly one of three verdicts in [`releases/v0.6.3.1/summary.json`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/releases/v0.6.3.1/summary.json):

- **`CERT`** — all carry-forward `S1` – `S8` green; all new-surface `S9` – `S22` green; `S23` and `S24` red as expected; the `ironclaw / mTLS` cell is 48 / 48. The release passes A2A certification on this tag.
- **`PARTIAL`** — same as `CERT` except `S23` and / or `S24` are still red and counted toward the Patch 2 funnel rather than treated as regressions. The release is conditionally certified pending Patch 2.
- **`FAIL`** — any other red, including any regression on `S1` – `S8` or any failure on `S9` – `S22`. Each red opens or updates a `bug` + `v0.6.3.2-candidate` issue on [`alphaonedev/ai-memory-mcp`](https://github.com/alphaonedev/ai-memory-mcp), parent-linked to the campaign's umbrella tracking issue.

The verdict is computed from `summary.json` by the `publish-pages.yml` workflow and reflected on [the index page](./index.md) as well as on the [test-hub aggregator](https://alphaonedev.github.io/ai-memory-test-hub/).

## Cross-links

- Back to [index](./index.md)
- [Matrix](./matrix.md) — framework × transport status
- [Scenarios](./scenarios.md) — full scenario list with expected verdicts
- [Reproducing](./reproducing.md) — local docker mesh + DigitalOcean
- [Findings](./findings.md) — defects funneled into Patch 2
- Repo-root [`SCOPE.md`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/SCOPE.md) — source of truth for this page
- Umbrella spec: [`ai-memory-ai2ai-gate`](https://github.com/alphaonedev/ai-memory-ai2ai-gate)
