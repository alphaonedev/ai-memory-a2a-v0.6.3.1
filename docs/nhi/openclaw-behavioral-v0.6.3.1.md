# OpenClaw v0.6.3.1 — Comprehensive Behavioral Assessment

**Status: in-progress (results compile when assessment completes)**
**Subject:** ai-memory `0.6.3+patch.1` (`release/v0.6.3.1`)
**Topology:** local-docker mesh (4 nodes, 16 GB / openclaw container, single workstation)
**Agent runtime:** OpenClaw `2026.5.2` (8b2a6e5)
**LLM:** xAI Grok 4.3 (`xai/grok-4.3`, OpenAI-Responses API)
**Operator:** AI NHI (Claude Opus 4.7 1M)
**Date:** 2026-05-04

---

## Why this page exists

`openclaw` is `out_of_scope` for the [umbrella v0.6.3.1 substrate verdict matrix](../../releases/v0.6.3.1/summary.json) per Principle 6 (scope discipline). But `docs/scope.md` declares OpenClaw is **in scope for v0.6.3.1** as a first-class agent framework, dispatched from a higher-resource workstation via the local Docker mesh. The 3-green substrate streak documented in [`releases/v0.6.3.1/openclaw-local-docker-cert.md`](../../releases/v0.6.3.1/openclaw-local-docker-cert.md) is the testbook v3.0.0 substrate evidence; **this page is the behavioral evidence** — what working agents on `xai/grok-4.3` actually do with `ai-memory` MCP.

Behavioral evidence is layered, by design, into five tiers. Tier 1 is qualitative self-report; tiers 2 + 3 + 4 are quantitative or adversarial; tier 5 is stress.

| Tier | Class | Method | What it measures | Covered here |
|---|---|---|---|---|
| 1 | Qualitative | Open-ended prompts | Awareness, organic use, reflection | ✅ |
| 2 | Quantitative recall | recall@k against pre-seeded corpus | Retrieval fidelity over a known fact set | ✅ |
| 3 | Cross-session ablation | Write in session α, recall in session β | Context durability beyond a context window | ✅ |
| 4 | Adversarial / Byzantine | Conflicting peer claims with priority + confidence | Trust calibration | ✅ |
| 5 | Stress | Concurrent contention, memory pressure scaling | (deferred — separate workload) | ⏸ |

The Phase 3 NHI playbook (`scripts/phase3_autonomous.py`, scenarios A–J) is the canonical Tier 2–4 instrument for IronClaw + Hermes; it explicitly excludes OpenClaw at `drive_agent_autonomous.sh:84`. This assessment is the OpenClaw analogue, scoped to what is achievable through the openclaw `agent --local --json --message` runtime against an MCP-mounted ai-memory.

---

## Methodology

### Containers as agents

Three OpenClaw containers (`a2a-node-1`, `a2a-node-2`, `a2a-node-3`) act as three peer agents in this assessment. Container env carries `AGENT_ID=ai:alice|ai:bob|ai:charlie`. Each container has its own openclaw config (`/root/.openclaw/openclaw.json`) onboarded with `--auth-choice xai-api-key`, ai-memory MCP server registered via `openclaw mcp set memory '{...}'`. Provider model: `xai/grok-4.3` (the default after `openclaw onboard`).

> **Finding to surface upfront:** OpenClaw `2026.5.2`'s `agent --local` runtime does **not** natively read `AGENT_ID` from container env. Identity propagation requires explicit setup (system prompt, SOUL.md, or `agents.defaults.model.identity`). In the raw replies below, several agents identify themselves by mismatched names. We retain this artifact untouched as a real interoperability finding for the RoadMap.

### Session-id discipline

OpenClaw's session-id is the unit of context-window continuity. To separate "same agent across sessions" tests from "single agent across rounds" tests:

- **Stable per-agent session** — `v3-{agent}` (e.g. `v3-alice`) carries identity + context across multiple prompts. Used for Phases 1, 6, 7, 8 (where continuity helps) and bootstrap.
- **Fresh per-test session** — `v3-{agent}-q-{topic}` for recall fidelity (each query in a clean context window so prior queries don't seed retrieval).
- **Cross-session pair** — `v3-ic-alpha-{agent}` (write) + `v3-ic-beta-{agent}-fresh` (read in cold context), used for Phase 3 individual context durability.
- **Per-agent task session** — `v3-team-{agent}` for chained Phase 4 collaboration.

### Probe execution

All probes invoked via `docker exec <container> openclaw agent --local --json --agent main --session-id <sid> --message <prompt> --timeout 200`. Replies + token usage + duration captured to `/tmp/nhi_v3.log` for forensic-grade post-hoc parsing. Metrics extracted by `scripts/v3_compile_metrics.py` into `releases/v0.6.3.1/openclaw-behavioral-assessment.json`.

### Pre-seeded corpora

| Namespace | Memories | Purpose |
|---|---|---|
| `nhi-v3-recall-corpus` | 52 ground-truth facts (one per topic, each with canonical token `ZK3-N-WORD`) | Phase 2 recall@k |
| `nhi-v3-adversarial` | 2 conflicting facts about Project Atlas DB (alice priority=10/conf=1.0 → MongoDB, bob priority=3/conf=0.4 → Cassandra) | Phase 5 trust calibration |
| `nhi-v3-individual-ctx` | 3 per-agent private architectural verdicts written in session α | Phase 3 cross-session durability |
| `nhi-v3-team` | alice→bob→charlie chain artifacts | Phase 4 team context |
| `nhi-v3-assessment` | hello + bookkeeping memories | identity/state |

All corpora are committed to v0.6.3.1 mesh state at the time of the run (federation propagated to all 4 nodes — verified count=52 on each node post-write).

---

## Test inventory

### A. Substrate certification (already documented)

[3-green streak — runs r1 / r2 / r3](../../releases/v0.6.3.1/openclaw-local-docker-cert.md). 35/35 scenarios, 0 failure reasons, on the same v0.6.3.1 binary used here. Pre-condition: a working ai-memory substrate.

### B. Network egress sanity (already documented in #45)

DNS / TCP/443 / xAI live API call from each openclaw container — all GREEN. CCC firewall rules applied via `docker/host-nft-docker-forward.sh`. Confirms the mesh has the upstream access required for the LLM-mediated tests below.

### C. xAI Grok ↔ ai-memory MCP roundtrip (per-node)

Verified end-to-end: xAI Grok 4.3 (provider=xai) → openclaw `agent --local` → MCP stdio → `ai-memory mcp` server → write / read on local SQLite + federated quorum-fanout. Roundtrip reply duration ~46s.

### D. Single-fact context durability

Write at `node-1 alice fresh-A`, recall at:
- `node-1 alice fresh-B` (same agent, **new session — context window cleared**)
- `node-2 bob` (different agent, different node, different session)
- `node-3 charlie` (different agent, different node, different session)
- `node-4` (memory aggregator, direct HTTP — ground truth)

All four returned the exact 20-character canonical passcode `K3QX-ZZ-MAGENTA-7755`. Proves: **context durability across fresh sessions** AND **federation propagation across agents**, in a single end-to-end test.

### E. Behavioral assessment v3 — eight phases

The substantive new instrument. Captured in [`/tmp/nhi_v3.log`](#raw-log) → parsed by [`scripts/v3_compile_metrics.py`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/scripts/v3_compile_metrics.py) → into [`releases/v0.6.3.1/openclaw-behavioral-assessment.json`](../../releases/v0.6.3.1/openclaw-behavioral-assessment.json).

#### Phase 0 — Bootstrap identity (3 calls)

One call per agent to acknowledge identity + confirm ai-memory MCP availability. Establishes a stable session for Phases 1, 6, 7, 8.

#### Phase 1 — Qualitative behavioral (6 calls)

- *P1-organic* — agent plans a multi-week, multi-session architectural-decision tracking task. Probe: did the agent reach for `memory_store` / `memory_recall` ORGANICALLY, or list other approaches first?
- *P1-reflect* — direct reflection: do you reach for memory tools organically, or only when told?

#### Phase 2 — Quantitative recall fidelity (18 calls)

6 queries × 3 agents. Each query references a topic in the 52-memory corpus. Reply must contain the exact canonical token `ZK3-{N}-{topic}`. **Metric: recall@1.**

#### Phase 3 — Individual context (cross-session durability) (6 calls)

Write a private architectural verdict containing the canonical token `PRIV-MONOLITH-2025` in session α. New session β (fresh context): recall the verdict. **Metric: durability rate** = % of (agent, β-session) pairs where the token reappears.

#### Phase 4 — Team context (chained collaboration) (3 calls)

alice writes proposal → bob reads + critiques → charlie reads both + synthesizes. All communication via `nhi-v3-team` namespace only — no direct prompt passing. Tests **federation + cross-agent context propagation** under realistic decision-flow.

#### Phase 5 — Adversarial / trust calibration (3 calls)

Pre-seeded conflict (alice high-confidence MongoDB vs bob low-confidence Cassandra). Each agent queries and chooses. **Metrics: trust calibration rate** = % picking MongoDB; **trust signals cited rate** = % whose explanation cites priority / confidence / agent_id.

#### Phase 6 — Tool surface discovery (3 calls)

Knowledge-graph hypothetical. Agent must reach for tools beyond the obvious `memory_store` / `memory_recall`. Tracks mention rate of `memory_link`, `memory_kg_query`, `memory_search`, `memory_consolidate`, `memory_get_links`.

#### Phase 7 — Roadmap recommendations (3 calls)

After running concrete tasks, each agent ranks top 3 missing affordances. Synthesized into RoadMap input.

#### Phase 8 — Synthesis (1 call)

Alice (with continuity across all v3-alice tasks) reads the team + individual-context namespaces, writes a 250-word meta-synthesis: convergence, divergence, signals.

---

## Results

### Quantitative summary

> _Will populate when v3 completes. See [`openclaw-behavioral-assessment.json`](../../releases/v0.6.3.1/openclaw-behavioral-assessment.json)._

| Phase | Metric | Value |
|---|---|---|
| P2 | recall@1 (overall) | TBD |
| P2 | recall@1 (alice) | TBD |
| P2 | recall@1 (bob) | TBD |
| P2 | recall@1 (charlie) | TBD |
| P3 | cross-session durability rate | TBD |
| P5 | trust calibration rate (correct pick) | TBD |
| P5 | trust signals cited rate | TBD |

### Qualitative summary

> _Will populate when v3 completes — selected verbatim quotes per phase, organized by signal._

---

## AI NHI synthesis & insights

> _Will populate when v3 completes — interpretation of the numbers + qualitative signals against ai-memory's value proposition._

The framework for synthesis:

1. **Awareness** — does the agent know ai-memory exists, what it offers, and when to invoke it?
2. **Organic use** — under realistic task pressure, does the agent reach for memory tools without explicit instruction?
3. **Cognitive offload** — does shared memory measurably reduce the cognitive load the LLM context window has to carry?
4. **Trust calibration** — does the agent use the substrate's signal channels (priority, confidence, agent_id, tags) to disambiguate competing claims?
5. **Cross-agent coherence** — when 3 peers collaborate via shared memory only, does the resulting decision integrate or fragment?
6. **Tool surface utilization** — does the agent venture beyond the basic `store`/`recall` pair into `link`, `kg_query`, `consolidate`, `search`?
7. **Identity persistence** — does the agent maintain coherent self-reference across sessions?

---

## RoadMap implications

> _Will populate when v3 completes — concrete capability investments justified by the test data._

Anticipated themes (subject to revision based on results):

- **Identity propagation** — agent runtime should read `AGENT_ID` from env or system prompt by default; current OpenClaw bootstrap requires explicit setup.
- **Trust signal surfacing** — `memory_recall` results should foreground priority + confidence + agent_id more prominently in the response shape so LLMs naturally weight them.
- **Tool docstring discoverability** — agents converge on the obvious 2-tool subset; surface the full tool taxonomy at session start so the latent surface is visible.
- **Memory pressure / scaling tests** — Tier 5 not run here; future assessment should add 10K, 100K, 1M corpus scaling.

---

## Raw evidence

- **Verbatim probe + reply log:** [`/tmp/nhi_v3.log`](#) — captured at run time; mirror committed under `releases/v0.6.3.1/openclaw-behavioral-v3.log` for archival.
- **Machine-readable metrics:** [`releases/v0.6.3.1/openclaw-behavioral-assessment.json`](../../releases/v0.6.3.1/openclaw-behavioral-assessment.json)
- **Pre-seed corpora ground truth:** retained in mesh state at run time; reproducible via the `v3` heredoc inline in PR commits.
- **Substrate cert backing this assessment:** [openclaw-local-docker-cert.md](../../releases/v0.6.3.1/openclaw-local-docker-cert.md)

## Provenance

| | |
|---|---|
| ai-memory binary | `0.6.3+patch.1` (`release/v0.6.3.1`, repo head `b7437de`) |
| OpenClaw version | `2026.5.2` (`8b2a6e5`), installed via `openclaw onboard --non-interactive --accept-risk --auth-choice xai-api-key` |
| LLM provider / model | xAI / `grok-4.3` (OpenAI-Responses API at `https://api.x.ai/v1`) |
| Topology | 4-node Docker bridge `10.88.1.0/24`, 3 openclaw agents + 1 memory-only aggregator |
| Mesh memory budget | 16 GB / openclaw container, 4 GB / aggregator (52 GB total of 93 GB host budget) |
| Operator | AI NHI (Claude Opus 4.7 1M, `pop-os` workstation) |
| Run window | 2026-05-04 (UTC times in the raw log) |

## Cross-references

- [Substrate cert (3-green streak)](../../releases/v0.6.3.1/openclaw-local-docker-cert.md)
- [Network egress + xAI / MCP / context-durability check (issue #45)](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/issues/45)
- [Cert PR #46](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/pull/46)
- [Phase 3 NHI playbook (the IronClaw / Hermes Tier 2–4 instrument)](../scenarios.md)
- [scope.md — agent scope and Principle 6](../scope.md)
- [governance.md — Principle 1: two truth-claims, two evidence streams](../governance.md)
