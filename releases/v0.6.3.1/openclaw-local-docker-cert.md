# OpenClaw Local-Docker Substrate Cert — v0.6.3.1

**Status: 3-green streak ACHIEVED (2026-05-04)**

OpenClaw substrate evidence on `release/v0.6.3.1`, dispatched per [`docs/scope.md` §"Agent scope"](../../docs/scope.md) from a 16 GB-per-container workstation Docker mesh because Basic-tier DigitalOcean droplets used for IronClaw / Hermes don't have the memory headroom OpenClaw needs.

Per [Principle 6 (scope discipline)](../../docs/governance.md#principle-6-scope-discipline-this-node-these-agents-this-release), this evidence is `scope=openclaw` and joins the umbrella v0.6.3.1 verdict via `release=v0.6.3.1` linkage only. Cross-framework results are never collapsed.

## Verdict

| Run | Topology | Verdict | Scenarios | Reasons | git_ref |
|---|---|---|---|---|---|
| [r1](../../runs/a2a-openclaw-v0.6.3.1-r1/) | local-docker (off) | ✅ GREEN | 35/35 | 0 | `release/v0.6.3.1` |
| [r2](../../runs/a2a-openclaw-v0.6.3.1-r2/) | local-docker (off) | ✅ GREEN | 35/35 | 0 | `release/v0.6.3.1` |
| [r3](../../runs/a2a-openclaw-v0.6.3.1-r3/) | local-docker (off) | ✅ GREEN | 35/35 | 0 | `release/v0.6.3.1` |

All three runs: `overall_pass=true`, `baseline_pass=true`, F3 peer-A2A canary GREEN, 35/35 substrate scenarios, zero failure reasons.

## Coverage

The local-docker testbook runs the 35-scenario v3.0.0 base set defined in [`docs/testbook.md`](../../docs/testbook.md) suites A–I:

```
1 1b 2 4 5 6 9 10 11 12 13 14 15 16 17 18 22 23 24 25 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42
```

This exercises the same MCP + HTTP surface that IronClaw / Hermes substrate cells exercise on DigitalOcean. The DO workflow additionally appends the v0.6.3.1-specific S-prefixed scenarios (S23–S31 + S26 mixed + S27 openclaw); those land in IronClaw / Hermes evidence trees and are tracked separately under [`releases/v0.6.3.1/summary.json`](summary.json) → `substrate_verdict.matrix`.

## Topology

4-node Docker bridge mesh on a single 93 GB / 14-CPU workstation:

| Container | Role | Agent ID | Memory | Image |
|---|---|---|---|---|
| `a2a-node-1` | agent | `ai:alice` | 16 GB | `ai-memory-openclaw:local` |
| `a2a-node-2` | agent | `ai:bob` | 16 GB | `ai-memory-openclaw:local` |
| `a2a-node-3` | agent | `ai:charlie` | 16 GB | `ai-memory-openclaw:local` |
| `a2a-node-4` | memory-only aggregator | — | 4 GB | `ai-memory-base:local` |

Mesh bridge: `10.88.1.0/24`. Federation quorum: W=2 of N=4. Reproducibility spec: [`docs/local-docker-mesh.md`](../../docs/local-docker-mesh.md).

## What this evidence covers

- ai-memory `0.6.3+patch.1` binary serves all 4 nodes with v0.6.3.1 schema (v19).
- 35-scenario v3.0.0 substrate testbook GREEN under federation, MCP stdio dispatch, and HTTP REST.
- Three pristine rounds (state reset between rounds via `docker compose down -v`) prove the result is reproducible, not state-dependent.
- Baseline attestation: `framework_is_authentic` (OpenClaw 2026.5.2), `mcp_server_ai_memory_registered`, `llm_backend_is_xai_grok`, `agent_id_stamped`, `federation_live`, all `true` per node.

## What this evidence does NOT cover

- **Phase 3 NHI playbook** for OpenClaw. The Phase 3 driver (`scripts/drive_agent_autonomous.sh`) explicitly limits `AGENT_TYPE` to `ironclaw|hermes`; OpenClaw NHI evidence is out of scope for this release. The repo's [`releases/v0.6.3.1/summary.json`](summary.json) lists OpenClaw under `out_of_scope` for the umbrella verdict on the same grounds. Adding OpenClaw to Phase 3 requires (a) discovering the 2026.5.x OpenClaw config schema (the existing `entrypoint.sh` openclaw.json shape is rejected by 2026.4.22 and 2026.5.2), (b) wiring the new `openclaw agent --local --json` invocation, (c) extending `claims_extractor.py` for the new framework. Tracked separately.
- **TLS / mTLS** modes for OpenClaw on local-docker. v0.6.2 cert proved tls + mtls cells GREEN on the same mesh; for v0.6.3.1 only the `off` cell has been re-validated here. tls + mtls retest is a follow-up.
- **DigitalOcean topology**. This evidence is local-docker-only. Cross-topology equivalence on OpenClaw is not asserted.

## Harness changes

Two surgical patches in [PR `#???`](TBD) (branch `chore/openclaw-substrate-v0.6.3.1`):

1. `docker/run-testbook.sh` — pin `ai_memory_git_ref` from `release/v0.6.2` → `release/v0.6.3.1`.
2. `docker/run-testbook.sh` — replace broken in-place state-reset (`docker exec rm -f` while serve holds open file handles) with `docker compose down -v && up -d`. The previous reset left expired v0.6.2 memories live in the volume that 409-conflicted every new write.
3. `.gitignore` — exclude `docker/bin/` (staged ai-memory binary, build artifact).

## Verification chain

| Layer | Evidence |
|---|---|
| 1 — Local sanity | `bash -n docker/run-testbook.sh` clean. |
| 2 — Source verification | Commit `6224fca` shows the two pin sites + state-reset block; matches the runbook output for all three runs. |
| 3 — CI | Local-docker dispatch (no GH Actions runner — see [`docs/local-docker-mesh.md`](../../docs/local-docker-mesh.md) for justification per Principle 6). |
| 4 — Artifact inspection | `jq '{overall_pass,scenarios:(.scenarios\|length),reasons:(.reasons\|length)}'` on each run's `a2a-summary.json` returns `{true, 35, 0}`. |

## Provenance

| | |
|---|---|
| Subject | `ai-memory 0.6.3+patch.1` (`release/v0.6.3.1`, repo head `b7437de`) |
| Campaign repo | [`alphaonedev/ai-memory-a2a-v0.6.3.1`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1) |
| Branch | `chore/openclaw-substrate-v0.6.3.1` |
| Operator | AI NHI (Claude Opus 4.7 1M, `pop-os` workstation) |
| Date | 2026-05-04 |
| Images | `ai-memory-base:local` (rebuilt today with v0.6.3.1 binary), `ai-memory-openclaw:local` (rebuilt today, OpenClaw 2026.5.2) |

## Cross-references

- [docs/scope.md](../../docs/scope.md) — agent scope discipline + substrate verdict criteria.
- [docs/governance.md](../../docs/governance.md) — Principles 1–7.
- [docs/local-docker-mesh.md](../../docs/local-docker-mesh.md) — reproducibility spec.
- [releases/v0.6.3.1/summary.json](summary.json) — umbrella verdict (IronClaw + Hermes substrate, OpenClaw out-of-scope on the umbrella matrix per Principle 6).
- v0.6.2 OpenClaw local-docker precedent: [`a2a-openclaw-v0.6.2-local-docker-r{1,2,3}`](https://github.com/alphaonedev/ai-memory-ai2ai-gate/tree/main/runs) (PR `#57` on `ai-memory-ai2ai-gate`).
