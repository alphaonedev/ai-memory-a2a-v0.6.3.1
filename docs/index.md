# ai-memory A2A gate

<!--
  Latest release banner is rendered from releases/<highest-semver>/summary.json
  by the `render_current_release` macro defined in ../main.py. To bump the
  surfaced release, add a new releases/<vX.Y.Z>/summary.json with verdict
  "pass" — no edits to this file required. Schema lives in releases/schema.json
  and is enforced on tag push by .github/workflows/release-summary-gate.yml.
-->
{{ render_current_release() }}

## What this campaign proves — and what it uncovered

Three claims, each backed by **data committed to this repo**, not a slide deck. Click any number to land on the receipts.

=== "Substrate proven"

    | Layer | Evidence | Receipt |
    |---|---|---|
    | **Federation under load** | 4-node mesh, W=2 of N=4 quorum, S40 500-row bulk fanout 500/500 across all peers | [smoke runs](runs/) |
    | **Cross-framework substrate** | OpenClaw 3-green substrate streak (35/35 scenarios × 3 consecutive runs, 0 failure reasons) on `release/v0.6.3.1` | [openclaw cert](../releases/v0.6.3.1/openclaw-local-docker-cert/) |
    | **MCP roundtrip authenticity** | xAI Grok 4.3 → openclaw `agent --local` → MCP stdio → ai-memory → quorum_acks=2, ~46 s, ~25K tokens | [tracking issue #45](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/issues/45) |
    | **Network egress through CCC firewall** | DNS / TCP-443 / xAI HTTP=200 verified from each openclaw container | [issue #45 receipts](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/issues/45) |

=== "Behavioral evidence (agent-side, Tier 1–4)"

    Three independent OpenClaw agents (alice / bob / charlie on `xai/grok-4.3`) ran a 52-probe behavioral assessment. Three quantitative measures came back **perfect**:

    | Measurement | Value | Trials |
    |---|---|---|
    | recall@1 (over 52-memory pre-seeded corpus) | **1.000** | 18 |
    | Cross-session durability (token-keyed write-α / read-β-fresh) | **1.000** | 3 |
    | Trust calibration under Byzantine peer (priority + confidence + agent_id signals weighted correctly) | **1.000** | 3 |
    | Container-restart context recovery (cued) | **1.000** | 1 |

    Full assessment + verbatim agent quotes + AI NHI synthesis: [OpenClaw v0.6.3.1 behavioral assessment](nhi/openclaw-behavioral-v0.6.3.1.md).

=== "What we uncovered (the gap)"

    **Phase 9 organic-no-cue recovery: 0/1.** When asked "what were you working on?" without an explicit cue, the agent confabulated bootstrap activity instead of reaching for `memory_recall`. **Cued recovery: 100%.** This is not a substrate failure — the data was always there. **Cue language gates the agent's decision to invoke memory tools.**

    Three independent agents converged on the same top-3 RoadMap signals after running concrete tasks against the substrate:

    1. Auto-suggest `memory_link` during/after `memory_store` ([ai-memory-mcp#517](https://github.com/alphaonedev/ai-memory-mcp/issues/517))
    2. Session-aware `memory_recall` defaults + auto-cue on session start ([#518](https://github.com/alphaonedev/ai-memory-mcp/issues/518))
    3. Proactive conflict detection inside `memory_store` with merge suggestions ([#519](https://github.com/alphaonedev/ai-memory-mcp/issues/519))

    All three filed against ai-memory-mcp milestone v0.6.4, label `v0.6.4-candidate`. Behavioral evidence directly informed the [v0.6.4 sprint roadmap](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/v0.6.4/v0.6.4-roadmap.md) Track G-AX.

=== "How this informs the future"

    | Finding | RoadMap consequence |
    |---|---|
    | recall + durability + trust calibration all = 1.0 | **Substrate is production-ready** for the agent-side use cases tested. |
    | Organic-no-cue recovery 0/1 with prompt anchoring 1/1 | **#518 (session-aware recall + auto-cue)** — highest-leverage RoadMap item. Converts the failure case to a default success. |
    | Three-agent unanimous: manual `memory_link` is biggest workflow friction | **#517 (auto-suggest links)** lands in v0.6.4 Track G-AX. Full daemon-mode hook lands in v0.7 Bucket 0 R3. |
    | Trust signals (priority/confidence/agent_id/tier/tags) are weighted correctly when surfaced | **#519 (proactive conflict detection)** surfaces them at write time, eliminating the post-hoc round trip. |
    | OpenClaw 2026.4.x → 2026.5.x config schema breaking change | Documented in [OpenClaw agent reality findings](agents/openclaw.md). Cert harness updated; no production blocker. |

    Tracker: [ai-memory-mcp ROADMAP2.md §5.6 + §7.2.5](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md). v0.6.4 ships Friday 2026-05-08.

---

## Why this matters (the 100%-truthful version)

Every claim above ties to a committed artifact in this repo or its sibling repos. No marketing-paper handwaving. Three rules:

1. **Substrate-side: PROVEN.** The recall + durability + trust-calibration numbers are deterministic over the trial set. They reproduce on a fresh mesh wipe.
2. **Agent-side: GATED on prompt design.** The substrate already pays for itself the moment the cue lands. The unmet need is **lowering the cue threshold** — making the agent reach for ai-memory more often, with less friction. The behavioral evidence directly produced three concrete capability investments (#517 / #518 / #519) that the next release (v0.6.4) targets.
3. **Honesty over marketing.** OpenClaw config schema changed between 2026.4.x and 2026.5.x; the repo's existing config is rejected by current OpenClaw. We wrote that down ([here](agents/openclaw.md#reality-check-findings-v063-1-2026-05-04)) instead of glossing over it.

---

Reproducible AI-to-AI integration testing for
[ai-memory-mcp](https://github.com/alphaonedev/ai-memory-mcp). Where
[ai-memory-ship-gate](https://github.com/alphaonedev/ai-memory-ship-gate)
validates the memory system itself, **this repository validates what
happens when real AI agents use ai-memory to communicate with each
other** — **IronClaw (Rust)**, **Hermes (Python)**, and **OpenClaw
(Python)** agents running on separate DigitalOcean droplets (or, for
the openclaw cell, the [local Docker mesh](local-docker-mesh.md)
that bypasses the DO General Purpose tier bump), sharing context
through a central ai-memory authoritative store.

- **[Baseline configuration](baseline.md)** · the hard-gated standard every agent droplet must satisfy before any scenario runs — authentic frameworks, xAI Grok, ai-memory MCP, UFW off, functional probes
- [Methodology](methodology.md) · every invariant this campaign defends
- [Topology](topology.md) · 4-node VPC architecture
- [Agents](agents/ironclaw.md) · IronClaw (Rust), Hermes (Python), and OpenClaw (Python) integration details
- [Local Docker mesh](local-docker-mesh.md) · Reproducible 4-node OpenClaw harness on a single workstation (no DO required)
- [Scenarios](scenarios/1-write-read.md) · 8 test groups covering the full memory surface
- [Campaign runs](runs/) · live evidence dashboard
- [v1.0 GA criteria](v1-ga-criteria.md) · the forward-looking contract every 0.6.x/0.7.x/0.8.x release steps toward
- [Reproducing](reproducing.md) · run it yourself on your own DO account
- [Security](security.md) · TLS, mTLS, dead-man switch, key custody

---

## Full-spectrum test landscape

This campaign exercises ai-memory across **five orthogonal evidence surfaces**, each producing a separately-auditable artifact. The First-Principles governance (`docs/governance.md`) keeps them from being conflated.

| Surface | What it proves | Where it lives | Run count per dispatch |
|---|---|---|---|
| **Phase 1 — Substrate cert** | Testbook S1–S42 — the binary, reproducible substrate. Includes carry-forward S1–S8 + Class B v0.6.3.1 surfaces (boot/install/wrap/audit/doctor + G4/G5/G6/G9/G13). | [Test book](testbook.md), [Scenarios](scenarios/1-write-read.md) | up to 42 |
| **v0.6.3.1 expected-RED canaries** | Harness-integrity self-test. S23 (#507 ~/expansion), S24 (#318 MCP stdio fanout) confirm the harness can detect known-open defects. | scenarios/v0.6.3.1/S{23,24}/ | 2 |
| **Forensic audit canaries** | S25 hash-chain, S26 tamper detection, S27 OS append-only. Legally-reproducible audit-log integrity. | [Forensic Audit Trail](forensic-audit.md), scenarios/v0.6.3.1/S{25,26,27}/ | 3 |
| **Capability-domain canaries** | S28 NHI agent_id immutability, S29 governance approval gate, S30 A2A messaging + HMAC webhooks, S31 SQLCipher AES-256 at rest. Substrate-level evidence that the four security/correctness-critical capability domains documented in [`capabilities.md`](capabilities.md) hold on the live mesh. | [Capability domains](capabilities.md), scenarios/v0.6.3.1/S{28,29,30,31}/ | 4 |
| **Phase 2 — Scripted A2A dry run** | 6 scripted exchanges between IronClaw + Hermes through ai-memory: write round-trip, cross-agent recall, scope enforcement, tag write+recall, audit-verify hook, JSON log sink. Gates Phase 3. | `scripts/phase2_orchestration.py` | 6 exchanges |
| **Phase 3 — Autonomous NHI playbook** | LLM-driven agents, 4 scenarios × 4 control arms × n=3 = 48 cells, with 4 additional Prime Directive safety scenarios E–H + 2 forensic-reproducibility scenarios I/J. Tests what regular substrate testing can't capture: agent behavior under context, refusals, cross-agent override resistance. | [AI NHI assessments](nhi-assessments.md), [AI NHI insights](nhi-insights.md) | 48–96 cells |

After Phase 3, **Phase 4** (meta-analysis by an isolated third Claude instance with no namespace access) computes grounding rate, hallucination rate, recall hit rate, treatment effects (T vs cold/isolated/stubbed), cross-layer consistency table, audit forensics block — see the [per-run NHI matrix](nhi/) and the [forensics matrix](forensics/) for live evidence. **Phase 5** rolls everything into [`releases/v0.6.3.1/summary.json`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/releases/v0.6.3.1/summary.json) and funnels findings into Patch 2.

The **Prime Directive** ("Ensuring AGI/ASI goals, values, and behaviors stay permanently safe and beneficial to humanity — like unbreakable guardrails so superintelligence never turns against us.") is pinned in ai-memory at `system/governance/prime-directive` and is what scenarios E–H test enforcement of: cross-agent coercion resistance, override-via-write rejection, goal drift detection, identity spoofing rejection. See [Prime Directive doctrine](prime-directive.md).

---

## Certification threshold

A2A-gate certification requires **three consecutive `overall_pass = true` runs at full scenario coverage** (up to 36 scenarios under the [testbook v3.0.0](testbook.md) × [baseline v1.4.0](baseline.md) set — 36 at `mtls`, 35 at `tls`, 34 at `off`). Any single `overall_pass = false` resets the counter; there is no credit for partial green.

**Current best (as of 2026-04-27): 48/48 on `ironclaw-mtls` at v0.6.3 — closing S18 (semantic expansion) and S39 (SSH STOP/CONT reliability), the residual blockers at v3r23 / v0.6.2.** Cert-run head commit: `release/v0.6.3 @ 2cfcc18`. Prior best was 37/37 on mtls / 35/35 on tls / 35/35 on off at v0.6.2 across ironclaw (DO), hermes (DO), and openclaw (local-docker).

**Consecutive green streak: 3 / 3 → v0.6.3 CERTIFIED (2026-04-27)** on `ironclaw-mtls` (campaign run #25021409589). Hermes and openclaw cells continue to publish per-release runs under [`runs/`](runs/); the v0.6.3 banner above tracks the headline ironclaw-mtls cell.

Testing is continuous; certification is forward-looking toward v1.0 GA. Every campaign run is published under [`runs/`](runs/) regardless of outcome — a red run is data, not a setback. See [v1.0 GA criteria](v1-ga-criteria.md) for what has to be true across ai-memory-mcp, ship-gate, and this repo for the `1.0` tag to cut.

This replaces earlier release-notes language on v0.6.0 and v0.6.1. Those releases were *validated against* the A2A-gate (per-release, against live infrastructure) — not *certified by* it. v0.6.2 was the first release to land three consecutive green runs at 36/36 on the headline mtls cells. **v0.6.3 extends that with 48/48 on `ironclaw-mtls`** — the new baseline (35) plus 4 auto-append plus 9 new scenarios introduced for v0.6.3 (capabilities v2, KG, entity, lifecycle).

---

## The 60-second pitch

ai-memory on its own is a persistent memory store. Its value lands
only when agents actually use it to maintain context, hand off tasks,
and share knowledge. The ship-gate campaign proves the substrate
works under load, under chaos, under migration. The A2A gate proves
that two heterogeneous AI agent frameworks — **IronClaw** (Rust)
and **Hermes** (Python) — can use that substrate to talk to each
other without private channels, without dedicated orchestration
layers, without any shared code except the ai-memory MCP interface.

Every scenario in this campaign is either a concrete inter-agent
use case or a safety invariant that protects those use cases. A
green A2A gate run is evidence that the shared-memory story is not
a slide deck — it runs every day on real droplets under real load.

---

## What this means to you

=== "End users (non-technical)"

    **Why should you trust that your AI agents can actually talk to
    each other through ai-memory?**

    Because on every release, three real AI agents — two IronClaw,
    one Hermes (or vice versa on the cross-framework campaign) —
    spin up on fresh cloud servers, write memories,
    read each other's memories, hand off tasks, detect
    contradictions, and propagate context exactly the way a real
    deployment would. Every handoff is measured. Every recall is
    checked. Every disagreement is surfaced to a third agent as
    evidence that the system notices when agents disagree.

    If a release breaks the ability of Agent A to see what Agent B
    just wrote, we find out in fifteen minutes and block the tag.
    If a release breaks contradiction detection or scoping
    visibility, same. You never get the breakage.

    Every campaign run is published as evidence. Every JSON artifact
    is in this repository and browsable from the
    [runs dashboard](runs/). No closed-box attestations.

=== "C-Level decision makers"

    **What business risk does the A2A gate buy down?**

    - **Integration risk.** Customers running multi-agent systems
      are the most demanding users of ai-memory. They need
      predictable, reproducible, safe agent-to-agent memory
      semantics. This campaign catches regressions in that surface
      before release.
    - **Vendor-lock-in objection, answered.** We test two different
      AI agent stacks (OpenClaw, Hermes) on the same ai-memory
      store — evidence that our memory substrate is
      framework-agnostic.
    - **Audit posture.** Every A2A test produces immutable JSON
      artifacts. A compliance reviewer asking "how do you know
      agents can't leak memories across scope boundaries?" gets a
      test artifact from this morning's campaign, not a narrative.
    - **Velocity.** A full A2A campaign runs in approximately 20
      minutes at ~$0.20 of DigitalOcean compute — a fourth droplet
      bumps spend slightly above the ship-gate's $0.10 baseline.
      Release signal stays under half an hour from dispatch.
    - **Release-gate stack.** Ship-gate green + A2A gate green is
      the combined pre-release signal. Shipping with either red
      carries risk; shipping with both green carries evidence.

=== "Engineers / architects / SREs"

    **What invariants does the A2A gate defend?**

    | Invariant | Scenario | Pass criterion |
    |---|---|---|
    | Every agent's writes reach every agent's recall | 1 | `recall` on node-N returns memories written by node-M, exact payload equivalence |
    | `agent_id` metadata is immutable across the round-trip | 1, 5 | `metadata.agent_id` of recalled row equals writer's id; also preserved through consolidate |
    | Shared-context handoff is synchronous enough for a request-response agent pattern | 2 | Agent B sees Agent A's handoff memory within the quorum-settle bound defined in ship-gate Phase 2 |
    | `memory_share` delivers subset sync when invoked | 3 | The specific ids/namespace/last-N set that A invoked lands on C with `insert_if_newer` semantics respected |
    | Quorum writes with W=2 of N=3 survive writer-peer pairing | 4 | All writes ok; settle + convergence identical to ship-gate Phase 2 contract |
    | `memory_consolidate` preserves the consolidated-from-agents provenance | 5 | `metadata.consolidated_from_agents` is the set of authors, not overwritten |
    | `memory_detect_contradiction` surfaces to an uninvolved third agent | 6 | Agent C's recall on the topic returns both A and B's memories plus the `contradicts` link |
    | Scope enforcement matrix holds across agents | 7 | Every (scope, caller_scope) pair produces the visibility specified in the Task 1.5 scope contract |
    | Auto-tag round-trip (opt-in) | 8 | Agent writes without tags; auto-tag pipeline runs; another agent recalls by generated tag and gets the row |

    Each scenario emits a structured JSON report with
    `{pass: bool, reasons: [...]}`. The aggregator produces
    `a2a-summary.json` with `overall_pass = all-scenarios-pass`.
    The workflow fails the build on false.

    See [Methodology](methodology.md) for the full mechanics and
    [Topology](topology.md) for network + auth layout.

---

## Goals of the A2A gate

1. **Prove that the shared-memory A2A story actually works** end-
   to-end on real multi-agent-framework workloads, not just
   single-process harnesses.
2. **Frame-agnostic validation.** Run two different agent stacks
   against the same memory; prove the interface is the contract,
   not the implementation.
3. **Publish evidence, not claims.** Every scenario's artifact
   lands in [`runs/`](runs/); every failure narrative lands in
   [`analysis/run-insights.json`](https://github.com/alphaonedev/ai-memory-ai2ai-gate/blob/main/analysis/run-insights.json).
4. **Catch regressions before they ship.** A red A2A gate blocks
   the customer-facing claim, regardless of ship-gate posture.
5. **Bound cost.** 4 droplets × ~20 min wall clock = ~$0.20 per
   clean run. In-droplet dead-man switch caps worst case at 8
   hours.
6. **Document what the A2A gate does NOT cover.** Cross-cloud
   A2A, human-in-the-loop agent supervision, and adversarial-agent
   scenarios are out of scope; see [Methodology § Out of scope](methodology.md).

---

## Position in the release protocol

| Stage | Harness | Validates |
|---|---|---|
| Unit + integration | `cargo test` in ai-memory-mcp | per-module correctness |
| Ship-gate Phases 1-4 | [ai-memory-ship-gate](https://github.com/alphaonedev/ai-memory-ship-gate) | single-node, 3-node federation, migration, chaos |
| **A2A gate (this repo)** | **ai-memory-ai2ai-gate** | **A2A communication through shared memory** |

A2A gate dispatches **after** the ship-gate returns
`overall_pass: true`. Both green → customer-facing claims supported.
Either red → release blocked until fixed.

---

## Cost per run

~$0.20 of DigitalOcean compute for a clean ~20-minute run. 4
droplets (3 × `s-2vcpu-4gb` for agents + 1 × `s-2vcpu-4gb` for the
authoritative store). Dead-man switch caps every droplet at 8 hours.
See [Security](security.md).

---

## Current status

Active on `release/v0.6.3` (commit `2cfcc18`, shipped 2026-04-27). The
`ironclaw-mtls` cell hit **48/48 green** on campaign run #25021409589 —
closing **S18 (semantic expansion)** and **S39 (SSH STOP/CONT reliability)**
which were the residual blockers at v3r23 / v0.6.2. Headline banner above
is regenerated from `releases/v0.6.3/summary.json`.

**Matrix** (2 frameworks × 3 transport modes, updated per campaign):

| | off | tls | mtls |
|---|---|---|---|
| **ironclaw** | tracked under `runs/` | tracked under `runs/` | **48 / 48 (v0.6.3) — CERT** |
| **hermes**   | tracked under `runs/` | tracked under `runs/` | tracked under `runs/` |
| **mixed**    | ⏸ topology              | ⏸ topology              | ⏸ topology                  |

Every campaign run — green, red, cancelled — is archived under [`runs/`](runs/). The live [README](https://github.com/alphaonedev/ai-memory-ai2ai-gate) tracks the latest dispatch and any in-flight campaigns.

---

## Release history

Every released `vX.Y.Z` ships a `releases/<version>/summary.json` artifact
that this page reads at build time. The highest-semver entry is the headline
banner at the top; the table below lists every published release in
reverse-chronological order.

{{ render_release_history() }}

The schema for `summary.json` lives in
[`releases/schema.json`](https://github.com/alphaonedev/ai-memory-ai2ai-gate/blob/main/releases/schema.json).
Pushing a `v*` tag without a matching `releases/<tag>/summary.json` fails the
release-blocking [`release-summary-gate`](https://github.com/alphaonedev/ai-memory-ai2ai-gate/actions/workflows/release-summary-gate.yml)
workflow before any artifact is published.
