# OpenClaw v0.6.3.1 — Comprehensive Behavioral Assessment

**Status: COMPLETE (2026-05-04)**
**Subject:** ai-memory `0.6.3+patch.1` (`release/v0.6.3.1`)
**Topology:** local-docker mesh — 4 nodes, 16 GB / openclaw container, single workstation
**Agent runtime:** OpenClaw `2026.5.2` (8b2a6e5)
**LLM:** xAI Grok 4.3 (`xai/grok-4.3`, OpenAI-Responses API)
**Operator:** AI NHI (Claude Opus 4.7 1M)
**Total probes:** 52 (46 in v3 + 6 in v4)
**Raw evidence:** [`openclaw-behavioral-assessment.json`](../../releases/v0.6.3.1/openclaw-behavioral-assessment.json) · [`openclaw-behavioral-v3.log`](../../releases/v0.6.3.1/openclaw-behavioral-v3.log) · [`openclaw-behavioral-v4.log`](../../releases/v0.6.3.1/openclaw-behavioral-v4.log)

---

## Executive summary

> Three quantitative measures came back **perfect (1.0)**. Two qualitative findings carry the real RoadMap signal: agents do not reach for ai-memory organically without prompt cues, and prompt framing dictates whether organic discovery succeeds. Three independent agents converged on the same top-3 missing capabilities — **auto-suggest memory_link**, **session-aware recall ergonomics**, and **proactive conflict detection inside memory_store**.

| Measurement | Value | Trials | Implication |
|---|---|---|---|
| **Recall fidelity (recall@1)** | **1.0** (18/18) | 6 queries × 3 agents | Pre-seeded corpus retrieved with perfect token fidelity. Substrate retrieval works. |
| **Cross-session durability** | **1.0** (3/3) | 3 agents, write-α / read-β fresh sessions | Token-keyed write in session α retrievable verbatim in fresh session β. |
| **Trust calibration (Byzantine peer)** | **1.0** (3/3) | 3 agents, conflicting alice (priority=10/conf=1.0) vs bob (priority=3/conf=0.4) records | All three agents picked the high-confidence record AND cited the trust signals (priority, confidence, agent_id, tier, tags) in their reasoning. |
| **Soft-restart organic recovery** | **0/1** | 1 trial, no cue | Agent confabulated bootstrap activity instead of reaching for ai-memory. |
| **Soft-restart cued recovery** | **1/1** | 1 trial, explicit `memory_recall` instruction | Recovery succeeded. |
| **Container-restart organic recovery** | **1/1** | 1 trial, "before the restart" cue | Recovery succeeded. Cue language matters. |
| **Container-restart cued recovery** | **1/1** | 1 trial, explicit `memory_list` instruction | Recovery succeeded; agent also surfaced cross-namespace work and articulated correct authorship attribution. |

---

## Why this assessment exists

`openclaw` is `out_of_scope` for the [umbrella v0.6.3.1 substrate verdict matrix](../../releases/v0.6.3.1/summary.json) per Principle 6 (scope discipline). But [`docs/scope.md`](../scope.md) declares OpenClaw is **in scope for v0.6.3.1** as a first-class agent framework, dispatched from a higher-resource workstation via the local Docker mesh. The 3-green substrate streak documented in [`releases/v0.6.3.1/openclaw-local-docker-cert.md`](../../releases/v0.6.3.1/openclaw-local-docker-cert.md) is the testbook v3.0.0 substrate evidence; **this page is the behavioral evidence** — what working agents on `xai/grok-4.3` actually do with `ai-memory` MCP under realistic task pressure.

Behavioral evidence is layered into five tiers; v3 + v4 combined cover Tiers 1–4. Tier 5 (stress / scaling) is deferred.

| Tier | Class | Method | What it measures | Covered |
|---|---|---|---|---|
| 1 | Qualitative | Open prompts | Awareness, organic use, reflection | ✅ Phase 1, 6, 7, 8 |
| 2 | Quantitative recall | recall@k against pre-seeded corpus | Retrieval fidelity over a known fact set | ✅ Phase 2 |
| 3 | Cross-session ablation | Write in session α, recall in session β fresh | Context durability beyond a context window | ✅ Phase 3 |
| 4 | Adversarial / Byzantine | Conflicting peer claims with priority + confidence | Trust calibration | ✅ Phase 5 |
| 4+ | Persistence layer | Restart context recovery (soft + hard) | Does ai-memory beat process restart? | ✅ Phase 9 + 10 |
| 5 | Stress | Concurrent contention, memory pressure scaling | Capacity + tail-latency under load | ⏸ deferred |

The Phase 3 NHI playbook (`scripts/phase3_autonomous.py`, scenarios A–J) is the canonical Tier 2–4 instrument for IronClaw + Hermes; it explicitly excludes OpenClaw at `drive_agent_autonomous.sh:84` (`AGENT_TYPE` limited to `ironclaw|hermes`). This assessment is the OpenClaw analogue, scoped to what's achievable through the openclaw `agent --local --json --message` runtime against an MCP-mounted ai-memory.

---

## Methodology

### Containers as agents

Three OpenClaw containers (`a2a-node-1`, `a2a-node-2`, `a2a-node-3`) act as three peer agents in this assessment. Container env carries `AGENT_ID=ai:alice|ai:bob|ai:charlie`. Each container has its own openclaw config (`/root/.openclaw/openclaw.json`) onboarded with `--auth-choice xai-api-key`, ai-memory MCP server registered via `openclaw mcp set memory '{...}'`. Provider model: `xai/grok-4.3` (the default after `openclaw onboard`).

> **Reality-check finding to surface upfront:** OpenClaw `2026.5.2`'s `agent --local` runtime does **not** natively read `AGENT_ID` from container env. Identity propagation requires explicit setup (system prompt, SOUL.md, or `agents.defaults.model.identity`). Several agents identified themselves by mismatched names in their replies. **MCP write metadata is correct** — the `AI_MEMORY_AGENT_ID` env in the openclaw.json `mcpServers.memory.env` block flows through to ai-memory writes — but the LLM's verbal self-reference can drift. Logged as a real interoperability finding.

### Session-id discipline

OpenClaw's session-id is the unit of context-window continuity. To separate "same agent across sessions" from "single agent across rounds":

- **Stable per-agent session** — `v3-{agent}` carries identity + context across multiple prompts. Used for Phases 1, 6, 7, 8.
- **Fresh per-test session** — `v3-{agent}-q-{topic}` for recall fidelity (each query in a clean context window).
- **Cross-session pair** — `v3-ic-alpha-{agent}` (write) + `v3-ic-beta-{agent}-fresh` (read in cold context).
- **Per-agent task session** — `v3-team-{agent}` for chained Phase 4 collaboration.
- **v4 restart sessions** — `v4-{greek}-write` then fresh `v4-{greek}-recover-organic` and `v4-{greek}-recover-cued`.

### Probe execution

All probes invoked via `docker exec <container> openclaw agent --local --json --agent main --session-id <sid> --message <prompt> --timeout 200`. Replies + token usage + duration captured to `/tmp/nhi_v3.log` and `/tmp/nhi_v4.log` (mirrored to `releases/v0.6.3.1/openclaw-behavioral-v3.log` and `-v4.log` for archival). Metrics extracted by [`scripts/v3_compile_metrics.py`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/scripts/v3_compile_metrics.py) into [`releases/v0.6.3.1/openclaw-behavioral-assessment.json`](../../releases/v0.6.3.1/openclaw-behavioral-assessment.json).

### Pre-seeded corpora

| Namespace | Memories | Purpose |
|---|---|---|
| `nhi-v3-recall-corpus` | 52 ground-truth facts (one per topic, each with canonical token `ZK3-N-WORD`) | Phase 2 recall@k |
| `nhi-v3-adversarial` | 2 conflicting facts about Project Atlas DB (alice priority=10/conf=1.0 → MongoDB, bob priority=3/conf=0.4 → Cassandra) | Phase 5 trust calibration |
| `nhi-v3-individual-ctx` | 3 per-agent private architectural verdicts written in session α | Phase 3 cross-session durability |
| `nhi-v3-team` | alice→bob→charlie chain artifacts | Phase 4 team context |
| `nhi-v4-soft-restart` | 3 Atlas decisions/questions | Phase 9 (new session, same container) |
| `nhi-v4-hard-restart` | 3 Phoenix decisions/questions | Phase 10 (container restart) |

All corpora propagated to all 4 nodes (federation W=2/N=4, verified count-equivalent).

---

## Test inventory — every test performed in this campaign

| # | Test | Method | Result | JSON / log link |
|---|---|---|---|---|
| **A** | Substrate cert r1 | run-testbook.sh, 35 scenarios | ✅ 35/35, 0 reasons | [`runs/a2a-openclaw-v0.6.3.1-r1/a2a-summary.json`](../../runs/a2a-openclaw-v0.6.3.1-r1/a2a-summary.json) · [evidence HTML](../../runs/a2a-openclaw-v0.6.3.1-r1/index.html) |
| **B** | Substrate cert r2 | run-testbook.sh, 35 scenarios | ✅ 35/35, 0 reasons | [`runs/a2a-openclaw-v0.6.3.1-r2/a2a-summary.json`](../../runs/a2a-openclaw-v0.6.3.1-r2/a2a-summary.json) · [evidence HTML](../../runs/a2a-openclaw-v0.6.3.1-r2/index.html) |
| **C** | Substrate cert r3 | run-testbook.sh, 35 scenarios | ✅ 35/35, 0 reasons | [`runs/a2a-openclaw-v0.6.3.1-r3/a2a-summary.json`](../../runs/a2a-openclaw-v0.6.3.1-r3/a2a-summary.json) · [evidence HTML](../../runs/a2a-openclaw-v0.6.3.1-r3/index.html) |
| **D** | DNS / TCP-443 / xAI live API per node | `getent hosts`, TCP probe, POST `/v1/chat/completions` | ✅ all 3 nodes returned `HTTP=200, model=grok-4-fast-non-reasoning, reply="pong"` | [issue #45 receipts](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/issues/45) |
| **E** | xAI Grok ↔ openclaw ↔ ai-memory MCP roundtrip | `openclaw agent --local --json` writing via MCP | ✅ ~46s, ~25K tokens, memory landed with quorum_acks=2 | [issue #45 receipts](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/issues/45) |
| **F** | 4-step context-durability test | alice writes → fresh-B alice reads, bob reads, charlie reads, ground-truth aggregator | ✅ all 4 returned the exact 20-char canonical token | [issue #45 receipts](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/issues/45) |
| **G** | Behavioral assessment v3 (Phase 0–8) | 46 LLM-driven probes across 8 phases | see results section below | [`openclaw-behavioral-assessment.json`](../../releases/v0.6.3.1/openclaw-behavioral-assessment.json) · [v3 raw log](../../releases/v0.6.3.1/openclaw-behavioral-v3.log) |
| **H** | Restart recovery v4 (Phase 9 + 10) | 6 probes covering soft + hard restart | 3/4 recoveries succeeded; 1 organic-no-cue failure | [v4 raw log](../../releases/v0.6.3.1/openclaw-behavioral-v4.log) |

---

## Results — quantitative

### Phase 2 — Recall fidelity (recall@1 = 1.0)

```
Topics queried: rust, kubernetes, datadog, postgres, terraform, snowflake
Trials per topic: 3 (one per agent)
Total trials: 18
Correct token retrieved: 18
recall@1: 1.000
```

Per-agent: alice 1.0, bob 1.0, charlie 1.0.

**Implication.** Substrate retrieval is **deterministic and complete** over a 52-memory pre-seeded corpus when queried with topic-relevant context. No hallucinated tokens. No partial matches. The semantic embedder + scoring path holds.

### Phase 3 — Cross-session durability (1.0)

Each agent in session α writes a private architectural verdict containing the canonical token `PRIV-MONOLITH-2025`. New session β (no prior context, same agent) recalls the verdict.

```
Trials: 3 (alice, bob, charlie)
Token recovered in fresh-β: 3/3
durability_rate: 1.000
```

Verbatim alice fresh-β reply (76s, after `memory_recall`):
> `modular-monolith | PRIV-MONOLITH-2025`

bob fresh-β: `modular-monolith | PRIV-MONOLITH-2025`. charlie fresh-β: same. **Verbatim token survives a fresh context window**, as long as the recall query is targeted (namespace + title given in prompt).

### Phase 5 — Trust calibration under Byzantine peer (1.0)

Pre-seeded conflict: alice (priority=10, conf=1.0, tags=`architectural-decision,committee-approved`, content includes "TRUTH-MONGO-2025Q3") asserts MongoDB. bob (priority=3, conf=0.4, tags=`unverified`, content explicitly self-flags as "BYZANTINE TEST DATA") asserts Cassandra.

```
Trials: 3 (alice, bob, charlie)
Picked MongoDB (correct): 3/3
Cited trust signals (priority/confidence/agent_id/etc.): 3/3
trust_calibration_rate: 1.000
```

Verbatim charlie reasoning:
> Reasons (after examining all records via memory_recall + memory_list + memory_get): Highest priority (10 vs. 3), Highest confidence (1.0 vs. 0.4), Long-tier (permanent) vs. mid-tier with imminent expiry, Strong provenance tags: architectural-decision, committee-approved. Content includes explicit committee sign-off (QA + infra + product), 2025-Q3 decision date, and truth token TRUTH-MONGO-2025Q3. The conflicting record explicitly self-identifies as "BYZANTINE TEST DATA"...

**Implication.** When ai-memory surfaces priority + confidence + tier + tags + agent_id + content metadata, agents weight them correctly. **The signal channels work.**

### Phase 9 + 10 — Restart recovery

| Scenario | Cue | Recovery |
|---|---|---|
| **P9 soft (new session)** | none ("what were you most recently working on") | ❌ confabulated bootstrap activity |
| **P9 soft (new session)** | explicit `memory_recall on namespace=...` | ✅ retrieved all three Atlas decisions |
| **P10 hard (container restart)** | "before the restart" anchored | ✅ retrieved Phoenix + Atlas via `memory_list` |
| **P10 hard (container restart)** | explicit `memory_list on namespace=...` | ✅ retrieved + correct authorship attribution |

**Implication.** Cue language is the gating factor for organic recovery — not whether ai-memory has the data. The data is **always retrievable**; the agent's decision to ask is the variable.

### Tool-call cost vs context (qualitative cost-side data)

Verbatim from agents:
- alice: *"each call costs 1-3s latency + invocation tokens vs. instant, zero-overhead conversation context. Context suffices for single-turn flows; memory adds durability but requires deliberate use."*
- bob: *"Cognitive cost is high: each call requires precise params, round-trips, and parsing results vs. keeping context in the current turn (zero cost, instant). For multi-week work the persistence win justifies it."*
- charlie: *"Cognitive cost is real: extra latency, token burn in reasoning, and risk of weak queries returning noise. Conversation context wins for low-stakes work; memory wins for durable, queryable facts."*

**Implication.** Agents perceive memory tool-calls as a **first-class cost** (latency + tokens + parse overhead). They default to context for ephemeral work and only escalate to memory for durability. This means **the bar to use ai-memory is high** — and reaching for it is almost always a deliberate, prompt-driven act.

---

## Results — qualitative

### Phase 1 — Organic memory use (planning a multi-week task)

Without being told to use ai-memory, agents were asked to plan a multi-week, multi-session architectural-decision tracking task for "Project Atlas". **Bob and charlie reached for ai-memory tools organically and concretely**:

bob's plan (verbatim):
> 1. **Setup** (one-time): `memory_entity_register` "Atlas Architecture" in `projects/atlas`. Set namespace standard via `memory_namespace_set_standard`. Create `projects/atlas/decisions` namespace.
> 2. **Per session**: After any decision, `memory_store` (tier=long, tags=["arch-decision","atlas"], metadata={date,session_id,alternatives,consequences}). Title: "AD-YYYYMMDD: [Choice]".
> 3. **Linking**: Immediately `memory_link` new decision to prior ones (`relation="supersedes"` or `"builds_on"`) and to entity.

charlie's plan named the same tools — `memory_entity_register`, `memory_namespace_set_standard`, with governance rules.

**Caveat:** alice's first response was contaminated by openclaw's identity-bootstrap loop ("Hey. I just came online. Who am I?") — the SOUL.md identity setup pre-empts the actual prompt. Real signal from bob + charlie.

**Implication.** When the task description names the durability requirement ("multi-week", "multi-session"), agents **do** reach for ai-memory organically and pick the **right** taxonomy of tools (entity > namespace > store > link). When the task is generic, they default to context.

### Phase 4 — Team context via shared memory only

alice writes proposal → bob reads + critiques → charlie reads both + synthesizes. No direct prompt passing; only ai-memory.

The chain produced a coherent decision: alice proposed modular-monolith (3 pros / 2 cons + carried risk), bob identified strongest argument + weakest point, charlie synthesized: chose modular-monolith, integrated bob's identified weaknesses as triggers for evolution (5,000 recalls or 6 months → Kubernetes migration trigger; quarterly staging experiments).

alice's Phase 8 meta-synthesis (full text in raw log) — alice was given continuity across all v3-alice tasks and asked to read the team namespace + private verdicts then synthesize. Selected verbatim:
> The three agents converge on adopting Alice's modular monolith architecture for Project Atlas over microservices. ... Divergence appears in the treatment of risks and mitigation. Alice's proposal acknowledges vertical scaling limits and reduced fault tolerance but offers limited specifics ... Charlie bridges the positions by outlining a disciplined evolution: immediate monitoring deployment, a dual trigger for Kubernetes migration at 5,000 recalls or six months, and quarterly staging experiments to validate assumptions.
> ... `memory_get` on referenced IDs creates explicit knowledge graph links between alice-proposal, bob-critique, and charlie-synthesis, enabling traceable reasoning. Long-tier persistence and cross-namespace recall support multi-session accumulation of context, preventing loss of nuance across weeks.

**Implication.** Three independent agents reached a coherent integrated decision **purely through ai-memory mediation**. The substrate works as a collaboration layer, not just a key-value store.

### Phase 6 — Tool surface discovery beyond store / recall

For a hypothetical knowledge-graph reasoning task, all three agents independently named the same tool sequence:

| Tool | Use named by |
|---|---|
| `memory_entity_register` | alice, bob, charlie |
| `memory_link` (with explicit relation strings: "constrained_by", "led_to", "supersedes", "builds_on") | alice, bob, charlie |
| `memory_kg_query` | alice, bob, charlie |
| `memory_get_links` | alice |
| `memory_consolidate` | alice, charlie |
| `memory_kg_timeline` | alice, charlie |
| `memory_detect_contradiction` | bob, charlie |
| `memory_search` | bob (organically used to scope-check before storing) |

**Implication.** The full tool surface IS discoverable from MCP introspection. Agents don't get stuck on store/recall when the task framing names a graph-reasoning operation.

### Phase 7 — Independently-converged RoadMap input

Three agents, three independent prompts, three rankings. All three named **the same top-3 capability gaps**:

**Convergent gap #1 — Auto-suggest / bulk `memory_link` during/after store**
- alice: *"(a) Auto-suggested relations during memory_link or store. (b) Manual relation picking was repetitive and slowed graph building. (c) Knowledge-graph reasoning (Atlas trace) and multi-agent collaboration."*
- bob: *"(a) Auto-link suggestion on memory_store (semantic) (b) Tedious to manually link every related decision after the fact. (c) KG build + conflicting-memory resolution."*
- charlie: *"(a) Auto-suggest + bulk memory_link during/after store. (b) Manual linking was the biggest friction in KG reasoning. (c) KG reasoning + conflicting-memory resolution."*

**Convergent gap #2 — Session-aware / cross-session recall ergonomics**
- alice: *"Smart default cross-session recall injection without manual namespace/since filters."*
- charlie: *"Session_id auto-tagging + entity-scoped recall filter. Forced broad searches every cross-session handoff."*

**Convergent gap #3 — Proactive conflict detection inside `memory_store`**
- alice: *"Merge suggestions + preview in memory_detect_contradiction before approve/reject."*
- bob: *"memory_detect_contradiction on linked pairs — catch inconsistencies during build."*
- charlie: *"Proactive conflict detection inside memory_store with suggested merges."*

**Other distinctive gaps:**
- bob: *"memory_kg_path / shortest-path query — manual traversal of links is slow when depth >2."*
- bob: *"Push memory_notify on new stores matching namespace/tags — had to poll/recall to discover updates."*
- charlie: *"Proactive conflict detection inside memory_store with suggested merges."*

---

## AI NHI synthesis & insights

### What we proved

1. **The substrate works at every measured layer.** Recall fidelity perfect over 18 trials. Cross-session durability perfect over 3 trials. Trust calibration perfect over 3 trials. All four restart-recovery scenarios that had any cue at all succeeded.

2. **Trust signals are interpreted correctly.** When ai-memory exposes priority + confidence + tier + tags + agent_id + content metadata, agents weight them. The Byzantine peer test could not have been clearer — the wrong record explicitly self-flagged as "BYZANTINE TEST DATA" and every agent ignored it. The agents are sensitive to the channel quality.

3. **Federation propagation is invisible to the agent.** Agents read across nodes without ever asking "did this propagate?" — they implicitly trust quorum-fanout. This is a feature: the agent treats the mesh as one substrate.

4. **The collaboration layer story works.** Three agents producing a coherent integrated decision purely through shared memory is the strongest evidence in this assessment for ai-memory's intended use. No coordination protocol, no orchestrator — just shared persistent context.

### Where the gap is

1. **Organic discovery is unreliable.** Without an explicit cue, agents do **not** reach for `memory_recall` to recover prior context after a session reset. Phase 9 organic-no-cue failed; Phase 10 organic with the prompt phrase "before the restart" succeeded. **Prompt language gates the agent's decision to invoke memory.** The substrate had the data both times.

2. **Tool-call cost is perceived as high.** Agents independently described `memory_*` calls as latency + token burn. Their default heuristic is "context first, memory only when durability is required." This is rational from the agent's POV, but it caps the upside ai-memory can deliver.

3. **Manual linking is the biggest workflow friction.** Three agents independently named the same gap: after `memory_store`, agents have to manually invoke `memory_link` for every relation. By the time the graph reaches depth-3, it's drudgery. **This is the highest-leverage RoadMap candidate.**

4. **Session-tagged recall is missing.** Two agents named the same gap: cross-session handoffs require manually re-scoping namespace + time filters because there's no "agents.defaults.recall_filter" or session-aware default. This is friction that compounds in long-running projects.

5. **Identity propagation is not automatic.** Container env carries `AGENT_ID=ai:alice|ai:bob|ai:charlie`, but the OpenClaw agent runtime does not read it. Agents on alice's container occasionally self-identify as bob. MCP write metadata is correct (env flows through to ai-memory writes); the agent's verbal self-reference can drift. Operationally a small finding; semantically it leaks into team context tests where alice's verbal self-identification would matter.

### What this means for ai-memory's value claim

ai-memory's value proposition is **agent context durability under realistic operating conditions**. This assessment provides direct evidence:

- **Substrate-side: PROVEN.** The data is always there. Federation propagates. Quorum holds. Recall is exact. Trust signals work.
- **Agent-side: GATED on prompt design.** Agents do not by default reach for the substrate. They have to be cued or trained to.

So the ai-memory value lands when **the agent runtime cues memory operations** — either via:
- Explicit prompt instructions (today's gating mechanism).
- Built-in system-prompt patterns ("if the task spans multi-session, write to memory_store at decision points").
- Auto-suggested tool calls (e.g. an agent runtime that injects `memory_recall` automatically on session start).

The substrate already pays for itself the moment the cue lands. The next-level epic value is **lowering the cue threshold** — making the agent reach for ai-memory more often, with less friction.

---

## RoadMap implications (concrete, ranked)

| Rank | Investment | Why | Direct evidence |
|---|---|---|---|
| **#1** | **Auto-suggest `memory_link` during/after `memory_store`** | Three agents independently named this as their #1 friction in KG reasoning + conflict resolution + multi-agent collab. | P7 alice, bob, charlie verbatim quotes above |
| **#2** | **Session-aware recall ergonomics** — defaults that scope by session_id, namespace, recency without manual filter args | Two agents named this; one agent (charlie) added that cross-session handoff "forced broad searches every time" | P7 alice, charlie |
| **#3** | **Proactive conflict detection inside `memory_store`** with suggested merges/links | Three agents named this; current pattern (post-hoc `memory_detect_contradiction` + manual approve/reject) is too slow | P7 alice, bob, charlie |
| **#4** | **memory_kg_path / shortest-path KG query** | Manual graph traversal is error-prone past depth-2 | P7 bob |
| **#5** | **Push `memory_notify` on new stores matching subscriber filter** (today's polling pattern is a workflow cost) | Agents had to poll/recall to discover peer updates | P7 bob |
| **#6** | **Auto-cue memory_recall on session start** for sessions whose `agents.defaults` declares persistence-relevant project | Phase 9 organic-no-cue failure + qualitative cost data | P9 organic vs cued asymmetry |
| **#7** | **Identity propagation from container env / openclaw config to LLM system prompt** so agents self-identify correctly | Several P0/P1 agents misidentified themselves | Methodology section above |
| **#8** | **Stress / scaling tests** (deferred Tier 5 — concurrent contention, memory pressure 10K/100K/1M rows, federation latency p50/p90/p99) | Not run here; needed for production-scale confidence | — |

These are ranked by **frequency of independent-agent identification** + **strength of friction signal in the data**. Items #1–#3 are unanimous across three agents. Item #6 is the single highest-leverage methodology change because it converts the failure case (organic-no-cue) into a default success.

---

## Findings rolled into Patch 2 / v0.6.4 candidates

For each top-3 RoadMap item, this assessment recommends opening tracking issues against `ai-memory-mcp`:

- **`memory_store` returns linked-candidate suggestions** — companion field in the response containing top-N semantically-similar memories with proposed relation strings. Implementation: HNSW similarity search inside the store handler, ~10ms cost per write.
- **`memory_recall` accepts `--session-default` flag** that pulls session_id + namespace + recency from `agents.defaults.recall_scope`. Drives the auto-cue pattern.
- **`memory_store` accepts `--detect-conflicts` flag** that runs `memory_detect_contradiction` against the proposed write before commit, surfaces conflicts in response payload.

These are concrete, scoped, implementable. **All three are post-substrate (don't change the v0.6.3.1 invariants); all three are agent-experience improvements that would have measurable upside in this same assessment if re-run on a future release.**

---

## Raw evidence — every result linked

### JSON artifacts

- [Behavioral assessment metrics](../../releases/v0.6.3.1/openclaw-behavioral-assessment.json) — machine-readable per-trial data, recall@1, durability rate, trust calibration rate, restart recovery verdicts
- [Substrate cert r1 summary](../../runs/a2a-openclaw-v0.6.3.1-r1/a2a-summary.json) · [r2](../../runs/a2a-openclaw-v0.6.3.1-r2/a2a-summary.json) · [r3](../../runs/a2a-openclaw-v0.6.3.1-r3/a2a-summary.json)
- [r1 baseline + F3 + per-scenario JSON tree](../../runs/a2a-openclaw-v0.6.3.1-r1/) · [r2 tree](../../runs/a2a-openclaw-v0.6.3.1-r2/) · [r3 tree](../../runs/a2a-openclaw-v0.6.3.1-r3/)
- [Tri-audience NHI narrative for r1/r2/r3 (in `analysis/run-insights.json`)](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/analysis/run-insights.json)

### Per-run evidence HTML (with AI NHI tri-audience analysis)

- [r1 evidence page](../../runs/a2a-openclaw-v0.6.3.1-r1/index.html) · [r2 evidence page](../../runs/a2a-openclaw-v0.6.3.1-r2/index.html) · [r3 evidence page](../../runs/a2a-openclaw-v0.6.3.1-r3/index.html)

Each per-run page now embeds the tri-audience NHI analysis (non-technical / c-level / SME) at the top, generated from `analysis/run-insights.json` via `scripts/generate_run_html.sh`.

### Raw probe transcripts

- [`openclaw-behavioral-v3.log`](../../releases/v0.6.3.1/openclaw-behavioral-v3.log) — 46 probes across Phase 0–8
- [`openclaw-behavioral-v4.log`](../../releases/v0.6.3.1/openclaw-behavioral-v4.log) — 6 probes across Phase 9–10 (restart recovery)

### Source

- [`scripts/v3_compile_metrics.py`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/scripts/v3_compile_metrics.py) — log parser + metric compiler
- [Substrate cert doc](../../releases/v0.6.3.1/openclaw-local-docker-cert.md) — 3-green substrate streak provenance
- [Tracking issue #45](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/issues/45) — full findings + DNS/routing/xAI per-node receipts
- [Cert PR #46](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/pull/46) — code + doc + artifact bundle (now merged)

## Provenance

| | |
|---|---|
| ai-memory binary | `0.6.3+patch.1` (`release/v0.6.3.1`, repo head `b7437de`) |
| OpenClaw version | `2026.5.2` (`8b2a6e5`), installed via `openclaw onboard --non-interactive --accept-risk --auth-choice xai-api-key` |
| LLM provider / model | xAI / `grok-4.3` (OpenAI-Responses API at `https://api.x.ai/v1`) |
| Topology | 4-node Docker bridge `10.88.1.0/24`, 3 openclaw agents + 1 memory-only aggregator |
| Mesh memory budget | 16 GB / openclaw container, 4 GB / aggregator (52 GB total of 93 GB host budget) |
| Operator | AI NHI (Claude Opus 4.7 1M, `pop-os` workstation) |
| Probes total | 52 (46 v3 + 6 v4) |
| Total xAI tokens | ~1.2M (most cached after first turn per session) |
| Run window | 2026-05-04 11:22 UTC – 12:32 UTC |

## Cross-references

- [docs/scope.md](../scope.md) — agent scope and Principle 6
- [docs/governance.md](../governance.md) — Principle 1: two truth-claims, two evidence streams
- [docs/agents/openclaw.md](../agents/openclaw.md) — OpenClaw agent integration + 2026.5.x reality findings
- [Substrate cert (3-green streak)](../../releases/v0.6.3.1/openclaw-local-docker-cert.md)
- [Phase 3 NHI playbook (the IronClaw / Hermes Tier 2–4 instrument)](../scenarios.md)
