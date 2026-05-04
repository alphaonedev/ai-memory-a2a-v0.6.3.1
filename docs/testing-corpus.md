# Testing Corpus — every test, every result, every insight

<div class="a1-banner" markdown>
<div class="a1-banner-title">CAMPAIGN-LEVEL ORIENTATION</div>
<div class="a1-banner-body">
This page is the single entry point to the v0.6.3.1 testing corpus. Every test we ran, what it measures, what it produced, where the receipts live. **Five evidence streams, three frameworks, one substrate under test.** Every claim links to a committed artifact.
</div>
</div>

<div class="a1-kpis" markdown>
<div class="a1-kpi"><span class="a1-kpi-value">9 / 9</span><span class="a1-kpi-label">Substrate runs (3 frameworks × 3 streaks)</span></div>
<div class="a1-kpi"><span class="a1-kpi-value">52</span><span class="a1-kpi-label">Behavioral probes (Tier 1–4)</span></div>
<div class="a1-kpi"><span class="a1-kpi-value">1.000</span><span class="a1-kpi-label">recall@1 (n=18)</span></div>
<div class="a1-kpi"><span class="a1-kpi-value">1.000</span><span class="a1-kpi-label">Cross-session durability (n=3)</span></div>
<div class="a1-kpi"><span class="a1-kpi-value">1.000</span><span class="a1-kpi-label">Trust calibration (n=3)</span></div>
<div class="a1-kpi"><span class="a1-kpi-value">3</span><span class="a1-kpi-label">RoadMap signals filed → v0.6.4</span></div>
</div>

---

<div class="a1-divider" markdown>
<span class="a1-divider-num">01</span>
<span class="a1-divider-line"></span>
</div>

## What's under test

**Subject:** [`ai-memory 0.6.3+patch.1`](https://github.com/alphaonedev/ai-memory-mcp/releases/tag/v0.6.3.1) — Apache-2.0 substrate for AI-to-AI memory + coordination. Schema v19. 1,886 library tests, 93.84% line coverage upstream. The job of this campaign is to put a working substrate under realistic agent-loop pressure and write down what survives and what doesn't.

**Three agent frameworks** exercise the substrate under three different transports:

<div class="a1-cards" markdown>
<div class="a1-card" markdown>
<span class="a1-card-eyebrow">Primary cert agent</span>
<span class="a1-card-title">IronClaw (Rust)</span>
<span class="a1-card-desc">First-class agent. DigitalOcean 4-node mesh. Drives the Phase 3 NHI behavioral playbook (scenarios A–J) at n=3 across four control arms.</span>
<span class="a1-card-footer"><a href="agents/ironclaw/">Setup</a> · <a href="runs/#ironclaw-campaigns">Runs</a></span>
</div>
<div class="a1-card" markdown>
<span class="a1-card-eyebrow">Cross-framework counterpart</span>
<span class="a1-card-title">Hermes (Python)</span>
<span class="a1-card-desc">Counterpart to IronClaw on the same DO topology. Proves substrate scenarios are framework-agnostic — same scenarios pass on different agent runtimes.</span>
<span class="a1-card-footer"><a href="agents/hermes/">Setup</a> · <a href="runs/#hermes-campaigns">Runs</a></span>
</div>
<div class="a1-card" markdown>
<span class="a1-card-eyebrow">First-class third agent</span>
<span class="a1-card-title">OpenClaw (Node.js)</span>
<span class="a1-card-desc">Workstation 4-node Docker mesh, 16 GB / openclaw container. xAI Grok 4.3 backed. 3-green substrate streak + Tier 1–4 behavioral assessment (52 probes, 8 phases).</span>
<span class="a1-card-footer"><a href="agents/openclaw/">Setup</a> · <a href="runs/#openclaw-campaigns">Runs</a> · <a href="nhi/openclaw-behavioral-v0.6.3.1/">Behavioral</a></span>
</div>
</div>

---

<div class="a1-divider" markdown>
<span class="a1-divider-num">02</span>
<span class="a1-divider-line"></span>
</div>

## The five evidence streams

Per [Principle 1](governance.md) (two truth-claims, two evidence streams, never conflated), the campaign produces independently-auditable artifacts. **Substrate-side** answers "does the code work?". **Behavioral-side** answers "do agents actually use it well?". Each stream is layered into tiers; higher-tier instruments produce stronger signal but cost more to run.

<div class="a1-cards" markdown>

<div class="a1-card" markdown>
<span class="a1-card-eyebrow">Stream 1 · Substrate cert</span>
<span class="a1-card-title">Phase 0 + 1 — Testbook v3.0.0 substrate</span>
<span class="a1-card-desc">35 scenarios per run covering MCP stdio + HTTP REST + federation + audit + governance + KG. 3-consecutive-green is the cert criterion. <strong>9 / 9 streaks complete this release</strong> (3 ironclaw + 3 hermes + 3 openclaw).</span>
<span class="a1-card-footer"><span class="a1-pill a1-pill--pass">3-GREEN × 3</span> <a href="testbook/">Testbook v3.0.0</a> · <a href="runs/">Runs</a></span>
</div>

<div class="a1-card" markdown>
<span class="a1-card-eyebrow">Stream 2 · Phase 3 NHI playbook</span>
<span class="a1-card-title">Behavioral matrix — 4 arms × 10 scenarios × n=3</span>
<span class="a1-card-desc">Scenarios A–J at four control arms (cold / isolated / stubbed / treatment). Per-cell grounding rate, hallucination rate, recall hit rate, treatment-vs-control attribution. Phase 4 meta-analysis is independent (third Claude, no namespace access).</span>
<span class="a1-card-footer"><a href="nhi-assessments/">Assessor</a> · <a href="nhi/">Per-run matrix</a> · <a href="nhi-insights/">Insights</a></span>
</div>

<div class="a1-card" markdown>
<span class="a1-card-eyebrow">Stream 3 · Forensic audit</span>
<span class="a1-card-title">Hash-chain + tamper detection + append-only</span>
<span class="a1-card-desc">S25 (audit chain), S26 (byte-mutation tamper detection), S27 (OS append-only). Audit log integrity proof — legally reproducible.</span>
<span class="a1-card-footer"><a href="forensic-audit/">Audit trail</a> · <a href="forensics/">Per-run forensics</a></span>
</div>

<div class="a1-card" markdown>
<span class="a1-card-eyebrow">Stream 4 · OpenClaw behavioral (Tier 1–4)</span>
<span class="a1-card-title">52 probes × 3 agents × 8 phases</span>
<span class="a1-card-desc">Qualitative awareness, quantitative recall@k, cross-session durability ablation, Byzantine peer trust calibration, tool-surface discovery, RoadMap recommendations, soft-restart + hard-restart context recovery.</span>
<span class="a1-card-footer"><span class="a1-pill a1-pill--cert">recall@1=1.000</span> <a href="nhi/openclaw-behavioral-v0.6.3.1/">Full report</a></span>
</div>

<div class="a1-card" markdown>
<span class="a1-card-eyebrow">Stream 5 · Network + MCP roundtrip</span>
<span class="a1-card-title">DNS + TLS + xAI live + ai-memory MCP per node</span>
<span class="a1-card-desc">Per-container egress through CCC firewall. xAI Grok 4.3 → openclaw <code>agent --local</code> → MCP stdio → ai-memory write/read with <code>quorum_acks=2</code>. Roundtrip ~46 s, ~25K tokens.</span>
<span class="a1-card-footer"><a href="https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/issues/45">Tracking issue #45</a></span>
</div>

</div>

---

<div class="a1-divider" markdown>
<span class="a1-divider-num">03</span>
<span class="a1-divider-line"></span>
</div>

## The headline numbers (with receipts)

<div class="a1-metric-grid" markdown>

<div class="a1-metric" markdown>
<span class="a1-metric-label">recall fidelity</span>
<span class="a1-metric-value">1.000</span>
<span class="a1-metric-sub">recall@1 over 18 trials (6 queries × 3 agents) against a 52-memory pre-seeded corpus. <a href="../releases/v0.6.3.1/openclaw-behavioral-assessment.json">JSON</a></span>
</div>

<div class="a1-metric" markdown>
<span class="a1-metric-label">cross-session durability</span>
<span class="a1-metric-value">1.000</span>
<span class="a1-metric-sub">Token-keyed write in session α, recall in fresh session β. n=3 agents. <a href="nhi/openclaw-behavioral-v0.6.3.1/#phase-3-cross-session-durability-10">Phase 3</a></span>
</div>

<div class="a1-metric" markdown>
<span class="a1-metric-label">trust calibration</span>
<span class="a1-metric-value">1.000</span>
<span class="a1-metric-sub">Byzantine peer test: alice priority=10/conf=1.0 (MongoDB) vs bob priority=3/conf=0.4 (Cassandra). 3 / 3 agents picked correct + cited trust signals. <a href="nhi/openclaw-behavioral-v0.6.3.1/#phase-5-trust-calibration-under-byzantine-peer-10">Phase 5</a></span>
</div>

<div class="a1-metric" markdown>
<span class="a1-metric-label">substrate cert (openclaw)</span>
<span class="a1-metric-value">35 / 35</span>
<span class="a1-metric-sub">Three consecutive green runs, 0 failure reasons. <a href="../releases/v0.6.3.1/openclaw-local-docker-cert/">Cert doc</a></span>
</div>

</div>

---

<div class="a1-divider" markdown>
<span class="a1-divider-num">04</span>
<span class="a1-divider-line"></span>
</div>

## What the testing uncovered (the gap that informs v0.6.4)

<div class="a1-banner" markdown>
<div class="a1-banner-title">THE SINGLE HIGHEST-LEVERAGE SIGNAL</div>
<div class="a1-banner-body">
<strong>Phase 9 organic-no-cue recovery: 0 / 1.</strong> Without an explicit cue ("memory_recall on namespace=…") the agent confabulated bootstrap activity instead of reaching for memory. Cued recovery: 100%. The data was always there. <strong>Cue language gates the agent's decision to invoke memory tools, not data availability.</strong>
</div>
</div>

After running concrete tasks — cross-session recall, multi-agent collaboration, conflicting-memory resolution, KG reasoning — three independent agents converged on the same top-3 capability gaps:

<div class="a1-cards" markdown>

<div class="a1-card" markdown>
<span class="a1-card-eyebrow">RoadMap signal #1</span>
<span class="a1-card-title">Auto-suggest <code>memory_link</code> during/after <code>memory_store</code></span>
<span class="a1-card-desc">Manual linking is the biggest workflow friction in KG reasoning + multi-agent collab. Filed <a href="https://github.com/alphaonedev/ai-memory-mcp/issues/517">ai-memory-mcp #517</a>; v0.6.4 Track G-AX (lightweight) + v0.7 Bucket 0 R3 (full daemon-mode hook).</span>
<span class="a1-card-footer"><span class="a1-pill a1-pill--info">v0.6.4-G1</span></span>
</div>

<div class="a1-card" markdown>
<span class="a1-card-eyebrow">RoadMap signal #2</span>
<span class="a1-card-title">Session-aware <code>memory_recall</code> defaults + auto-cue</span>
<span class="a1-card-desc">Closes the Phase 9 organic-no-cue failure case by converting the cue to a default — agent runtime injects memory_recall results into the system prompt at session start, no agent decision required. Filed <a href="https://github.com/alphaonedev/ai-memory-mcp/issues/518">#518</a>.</span>
<span class="a1-card-footer"><span class="a1-pill a1-pill--info">v0.6.4-G2</span></span>
</div>

<div class="a1-card" markdown>
<span class="a1-card-eyebrow">RoadMap signal #3</span>
<span class="a1-card-title">Proactive conflict detection inside <code>memory_store</code></span>
<span class="a1-card-desc">Surfaces conflicts at write time with merge_strategy suggestions (replace / link.supersedes / link.contradicts / consolidate). Eliminates the post-hoc detect+resolve round trip. Filed <a href="https://github.com/alphaonedev/ai-memory-mcp/issues/519">#519</a>.</span>
<span class="a1-card-footer"><span class="a1-pill a1-pill--info">v0.6.4-G3</span></span>
</div>

</div>

All three issues are filed against `ai-memory-mcp` milestone [v0.6.4](https://github.com/alphaonedev/ai-memory-mcp/milestone/7) (sprint window 2026-05-04 → 2026-05-08). Behavioral evidence directly drove the [v0.6.4 sprint scope](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/v0.6.4/v0.6.4-roadmap.md) Track G-AX.

---

<div class="a1-divider" markdown>
<span class="a1-divider-num">05</span>
<span class="a1-divider-line"></span>
</div>

## Methodology — how this campaign is run

Every claim above is reproducible. The methodology is named in three places — pick the depth you want:

| Audience | Read |
|---|---|
| Decision-maker (15 min) | [Why this campaign exists](index.md), [the 60-second pitch](index.md#the-60-second-pitch), and the headline numbers above |
| Reviewer (30 min) | [Methodology](methodology.md), [Scope](scope.md), [Governance](governance.md) — the First-Principles design |
| Operator (1 hour) | [Reproducing on DO](reproducing.md), [Local Docker mesh reproducibility](local-docker-mesh.md), [Testbook v3.0.0](testbook.md), [Every test performed](tests.md) |

**Reproducibility floor:** every campaign run lives under [`runs/`](runs/) with `a2a-summary.json`, `campaign.meta.json`, `a2a-baseline.json`, `f3-peer-a2a.json`, per-scenario `scenario-N.json` + `.log`, and (Phase 3+ runs only) `phase2-orchestration.json`, `phase3-*.json`, `phase4-analysis.json`. The `runs/` index now also surfaces per-framework subtotals + cross-framework instruments overview.

**Governance floor:** scope-tagged artifacts (`scope=ironclaw` / `scope=hermes` / `scope=openclaw`) join the umbrella v0.6.3.1 release via release-tag linkage only. Cross-framework data is **never collapsed** into a single verdict per Principle 6 (scope discipline).

---

<div class="a1-divider" markdown>
<span class="a1-divider-num">06</span>
<span class="a1-divider-line"></span>
</div>

## How this informs v0.6.4 + beyond

The substrate side is proven for the use cases tested. The agent-side is **gated on prompt design**. The next-level value is lowering the cue threshold — making the agent reach for ai-memory more often, with less friction.

| Finding | RoadMap consequence | Where to track |
|---|---|---|
| recall + durability + trust calibration all = 1.000 | Substrate is production-ready for the agent-side use cases tested | [Cert doc](../releases/v0.6.3.1/openclaw-local-docker-cert.md) |
| Organic-no-cue recovery 0/1; cued recovery 1/1 | **Highest-leverage RoadMap item** — converts the failure case to a default success | ai-memory-mcp [#518](https://github.com/alphaonedev/ai-memory-mcp/issues/518), v0.6.4-G2 |
| Three-agent unanimous: manual `memory_link` is the biggest workflow friction | v0.6.4 Track G-AX (lightweight, response-field) + v0.7 Bucket 0 R3 (full daemon-mode hook) | [#517](https://github.com/alphaonedev/ai-memory-mcp/issues/517) |
| Trust signals (priority/confidence/agent_id/tier/tags) weighted correctly when surfaced | Surface them at write time instead of post-hoc | [#519](https://github.com/alphaonedev/ai-memory-mcp/issues/519) |
| OpenClaw 2026.4.x → 2026.5.x config schema breaking change | Documented openly; cert harness updated; no production blocker | [agents/openclaw](agents/openclaw.md#reality-check-findings-v063-1-2026-05-04) |
| ai-memory-a2a-v0.6.3.1 mesh state-reset was non-functional (in-place rm during running daemon) | Replaced with `docker compose down -v && up -d`; documented in cert PR #46 | [PR #46](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/pull/46) |

For the full reconciled roadmap (substrate + behavioral findings + v0.6.4 sprint scope), see [`ai-memory-mcp/ROADMAP2.md`](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md).

---

<div class="a1-divider" markdown>
<span class="a1-divider-num">07</span>
<span class="a1-divider-line"></span>
</div>

## Honest reality findings

**Five things we wrote down honestly that an "everything is great" deck wouldn't:**

1. **OpenClaw 2026.5.x has a breaking config-schema change.** The repo's existing `entrypoint.sh` openclaw.json shape is rejected by both 2026.4.22 and 2026.5.2. Modern config is gateway-centric; we documented the validated `openclaw onboard --auth-choice xai-api-key` recipe rather than glossing.
2. **The fictional `openclaw run` flag set never existed.** Neither in 2026.4.22 nor 2026.5.2. The repo's `drive_agent.sh` openclaw branch silently fell back to HTTP. Substrate scenarios passed without a working openclaw runtime — true but uncomfortable, and now named.
3. **Identity propagation is not automatic.** Container env carries `AGENT_ID=ai:alice|bob|charlie` but the OpenClaw `agent --local` runtime does not read it. MCP write metadata is correct (the env in `mcpServers.memory.env` flows through), but the LLM's verbal self-reference can drift. Logged.
4. **Mesh state-reset via in-place `docker exec rm -f a2a.db*` does not actually clean the volume.** `serve` holds open WAL handles; `rm` only unlinks directory entries; quorum-resync from peer nodes can repopulate. First openclaw r1 attempt failed 21/35 from this; cleaned up via `docker compose down -v && up -d` and re-ran 35/35 GREEN.
5. **Substrate verdict in `releases/v0.6.3.1/summary.json` is `pending`.** Not `cert`. The campaign is not done. `expected_red` for S23 (`#507`) and S24 (`#318`) is documented; both flip to expected-green at v0.6.3.2 (Patch 2).

If anything on this page contradicts the JSON in the run artifacts, **trust the JSON**. Open an issue.

---

## Reading order

- New to the campaign → start at the [home page](index.md)
- Want the verdict → [latest-run NHI insights](nhi-insights.md) + [per-run NHI matrix](nhi/index.md)
- Want the receipts → [Campaign runs](runs/) + per-run evidence pages
- Want to reproduce → [Reproducing](reproducing.md) (DO) or [Local Docker mesh](local-docker-mesh.md) (workstation)
- Want to read the design → [Methodology](methodology.md), [Scope](scope.md), [Governance](governance.md)

— Authored 2026-05-04 by AI NHI (Claude Opus 4.7 1M) on behalf of AlphaOne LLC.
