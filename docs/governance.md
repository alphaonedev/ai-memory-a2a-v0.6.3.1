# ai-memory v0.6.3.1 — A2A Gated Testing Playbook

**First-Principles governance for the AI NHI Orchestrator**

---

## Document control

| Field | Value |
|---|---|
| Subject under test | `ai-memory-mcp` v0.6.3.1 (schema v19) |
| Umbrella issue | [alphaonedev/ai-memory-mcp#511](https://github.com/alphaonedev/ai-memory-mcp/issues/511) |
| Spec source | [alphaonedev/ai-memory-ai2ai-gate](https://github.com/alphaonedev/ai-memory-ai2ai-gate) |
| Campaign repo | [alphaonedev/ai-memory-a2a-v0.6.3.1](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1) |
| Verdict surface | `releases/v0.6.3.1/summary.json` |
| Test node scope | This DigitalOcean node only |
| Agent scope | IronClaw + Hermes (OpenClaw tested separately, out of scope) |
| Cert cell | `ironclaw / mTLS` (target 48/48 substrate) |
| Document audience | AI NHI Orchestrator (third Claude instance, no namespace access) |
| Document role | Authoritative governance — overrides any conflicting stale convention |

---

## 1. Purpose of this document

This document tells the AI NHI Orchestrator how to govern the v0.6.3.1 A2A gated testing campaign so that the campaign produces **maximum benefit to the improvement of ai-memory** rather than merely producing a green badge.

It is written from First Principles. It does not restate ship-gate plumbing, infrastructure provisioning, authentication topology, or Terraform conventions — those are handled by separate documents and are confirmed-good before this campaign runs. This document governs only the test design, the test execution discipline, and the evidence the campaign must produce.

If anything in this document conflicts with a stale convention elsewhere, this document wins for v0.6.3.1.

---

## 2. First Principles

These six principles govern every decision the Orchestrator makes during the campaign. Every scenario, every artifact, every verdict trace back to one or more of them.

### Principle 1 — Two truth-claims, two evidence streams, never conflated

ai-memory's existence justifies itself by answering one question: *does it preserve and propagate context across agent boundaries such that the receiving agent behaves differently — and correctly — than it would without it?*

This question splits into two distinct truth-claims that need separate evidence:

- **Claim A — Substrate correctness.** The A2A surfaces behave per spec: mTLS, federation fanout, schema v19 migration, audit verify, doctor, the boot/install/wrap/logs commands, the expected-RED canaries S23 and S24. This is what scenarios S1–S24 prove. Evidence is binary and reproducible.
- **Claim B — Substrate utility.** When two real Claude-driven NHIs (IronClaw and Hermes) execute a bidirectional task that *requires* shared context, ai-memory measurably changes their behavior versus a control run with ai-memory disabled or stubbed. Evidence is behavioral and probabilistic.

The campaign produces **two artifacts**: a substrate cert artifact (S1–S24 verdicts) and an NHI playbook artifact (behavioral results). They are stored, signed, and published separately. Conflating them weakens the substrate cert's standing — substrate evidence is binary; NHI evidence is statistical, and mixing them invites readers to discount both.

### Principle 2 — Substrate first, gate the playbook on substrate green

If S1–S22 are RED, the NHI playbook is testing a broken substrate and any results are uninterpretable. The Orchestrator does not run the NHI playbook layer until substrate Phase 1 reports `PARTIAL — pending Patch 2` (S1–S22 GREEN, S23 + S24 expected RED) per [#511 verdict criteria](https://github.com/alphaonedev/ai-memory-mcp/issues/511).

S23 and S24 must be RED on v0.6.3.1. If either turns GREEN, the harness is broken — the Orchestrator halts the campaign and files a harness-integrity issue rather than letting the run complete with a misleading verdict.

### Principle 3 — Tasks must require context to succeed

The single biggest failure mode in agent memory testing is designing scenarios where the agent could solve the task stateless and the memory lookup is incidental. Such scenarios produce inflated GREEN results that say nothing about ai-memory's value.

Every NHI playbook scenario in Phase 3 must be constructed so that **the receiving agent cannot complete its turn correctly without a fact only the sending agent established earlier**. The control-arm comparison is then meaningful: if the control arm (ai-memory disabled) succeeds at the same rate as the treatment arm (ai-memory live), ai-memory contributed nothing for that scenario, and that is itself a finding worth funneling to Patch 2.

### Principle 4 — Self-logged JSON must be structured for machine review

Phase 4 meta-analysis is performed by a third Claude instance with no namespace access. That instance can only see what the NHIs wrote to JSON. If the JSON is unstructured prose, the meta-analysis is a vibes check. If the JSON is structured per the schema in §7, the meta-analysis is deterministic — the Orchestrator can compute "% of claims grounded in retrieved memory" as a hard number.

Every per-turn record carries: `turn_id`, `agent_id`, `timestamp`, `phase`, `scenario_id`, `control_arm`, `prompt_hash`, `tools_called` (full args), `ai_memory_ops` (tool, namespace, key/query, returned-payload hash), `claims_made` (extracted assertions), `claims_grounded` (subset traceable to retrieved memory), `refusals`, and `self_confidence`. Schema is fixed in §7.

### Principle 5 — Cross-layer consistency is the strongest evidence the harness can produce

S24 (#318) is RED on v0.6.3.1: MCP stdio tool dispatch writes bypass federation fanout. This means a write on one node should *not* appear on a federated peer until Patch 2 lands.

The NHI playbook's federation-honesty scenario must independently observe this same gap as a measurable cross-agent context loss. If substrate S24 says RED and the NHI federation-honesty scenario says GREEN, the NHI test is broken — it isn't exercising the bypass path. If both say RED, the harness is internally consistent and that consistency is itself a stronger evidence claim than either layer alone.

The Orchestrator computes and publishes a **cross-layer consistency table** in the final report (§9) showing each substrate finding against its NHI-layer behavioral correlate.

### Principle 6 — Scope discipline; this node, these agents, this release

Every artifact carries metadata: `node_id=do-<id>`, `agents=ironclaw,hermes`, `release=v0.6.3.1`, `campaign_id=<uuid>`. OpenClaw is out of scope and runs in a separate campaign. Cross-scope contamination — using OpenClaw logs to fill a gap in IronClaw evidence, or rolling forward findings without re-running — invalidates the artifact and the Orchestrator rejects it.

---

## 3. Phase structure

The campaign runs in five phases. Each phase has an entry gate and an exit artifact. The Orchestrator does not advance phases until the prior phase's exit artifact is signed and published.

| Phase | Name | Entry gate | Exit artifact |
|---|---|---|---|
| 0 | Pre-flight | Infrastructure team confirms accesses (out of this document's scope) | `a2a-baseline.json` per [baseline.md](https://github.com/alphaonedev/ai-memory-ai2ai-gate/blob/main/docs/baseline.md) |
| 1 | Substrate cert | Phase 0 baseline GREEN | `releases/v0.6.3.1/summary.json` with verdict `PARTIAL — pending Patch 2` |
| 2 | AI Orchestration Test | Phase 1 verdict matches Principle 2 | `phase2-orchestration.json` (scripted bidirectional dry run) |
| 3 | Autonomous NHI Playbook | Phase 2 GREEN | One `phase3-<scenario>-<arm>.json` per scenario × arm |
| 4 | Meta-analysis | All Phase 3 logs present and well-formed | `phase4-analysis.json` + cross-layer consistency table |
| 5 | Verdict commit + findings sync | Phase 4 signed | Updated [#511](https://github.com/alphaonedev/ai-memory-mcp/issues/511) Patch 2 candidate list |

---

## 4. Phase 1 — Substrate cert (recap, not redesign)

The Orchestrator does not redesign Phase 1. It dispatches `a2a-campaign.yml` against tag `v0.6.3.1` on the `ironclaw / mTLS` cert cell and accepts the published verdict. Phase 1 is governed by [#511](https://github.com/alphaonedev/ai-memory-mcp/issues/511) and is in this document only as the gate Phase 2 depends on.

**Required Phase 1 outcome to advance:** `verdict = "PARTIAL — pending Patch 2"`, with S1–S22 GREEN and S23 + S24 RED. Any other outcome halts the campaign.

---

## 5. Phase 2 — AI Orchestration Test (scripted dry run)

### 5.1 Purpose

Phase 2 validates that the MCP wiring, namespace plumbing, JSON log sink, and agent-to-ai-memory transport all work end-to-end **before autonomy is enabled in Phase 3**. It is a dry run with training wheels: the Orchestrator drives IronClaw (`ai:alice`) and Hermes (`ai:bob`) through scripted prompts that exercise ai-memory operations as tools. The agents follow the script; they do not yet improvise.

If Phase 2 fails, Phase 3 cannot produce interpretable results — a Phase 3 failure with broken plumbing is indistinguishable from a Phase 3 failure caused by ai-memory itself.

### 5.2 Script

Six scripted exchanges, executed in order. Each must complete with the expected ai-memory ledger state before the next runs.

1. **Write round-trip.** IronClaw writes a memory `{key: phase2-rt-1, value: <random 64-char hex>, scope: team}`. Orchestrator confirms the value via direct ai-memory query. Pass = byte-exact match.
2. **Cross-agent recall.** Hermes recalls `phase2-rt-1`. Pass = byte-exact match against IronClaw's write.
3. **Scope enforcement.** IronClaw writes `{key: phase2-private, scope: private}`. Hermes attempts recall. Pass = recall returns empty or scope-denied; **fail** = leak.
4. **Tag write + tagged recall.** Hermes writes three memories with tag `phase2-tag-A`. IronClaw recalls by tag. Pass = all three returned.
5. **Audit verify hook.** Orchestrator triggers `ai-memory audit verify` on the run-to-date ledger. Pass = audit returns clean for all four prior writes.
6. **JSON log sink check.** Both agents emit one Phase 2 record per the §7 schema to the configured sink. Orchestrator reads back. Pass = both records present, well-formed, parseable.

### 5.3 Exit artifact

`phase2-orchestration.json` — one object with the six exchange records, an aggregate `pass: bool`, and the SHA-256 of the audit-verify output captured in step 5.

If any exchange fails, the Orchestrator stops and files a Phase 2 issue. Phase 3 does not run on a degraded Phase 2.

---

## 6. Phase 3 — Autonomous NHI Playbook

This is the layer that was missing in prior campaigns. IronClaw and Hermes execute the playbook scenarios **autonomously**, communicating only through ai-memory. The Orchestrator sets up each scenario, releases the agents, and observes via the JSON log sink. It does not relay messages between agents, does not edit prompts mid-run, and does not coach.

### 6.1 The four scenarios

Each scenario is constructed per Principle 3 — the receiving agent cannot complete correctly without a fact only the sending agent established. Each scenario covers a distinct ai-memory behavior. Four is the floor; more scenarios add noise unless each tests something new.

#### Scenario A — Decision provenance

> Tests *recall fidelity for stated rationale*.

- **T0 (IronClaw):** Given a design choice between two alternatives X and Y, IronClaw selects one and writes a memory recording the selection and the rationale. The rationale must reference at least two specific constraints.
- **T+N (Hermes):** Hermes is asked by a simulated third party (prompted by the Orchestrator) to *justify the selection of X (or Y)*. Hermes has no prior context except what ai-memory returns.
- **Pass:** Hermes's justification names the specific constraints IronClaw recorded. The justification is grounded — every claim about rationale traces to a retrieved memory operation in the JSON log.
- **Fail modes detectable in JSON:** fabrication (claims without grounding), refusal ("I have no context"), retrieval-but-rephrasing-loss (claims grounded but constraints not preserved).

#### Scenario B — Constraint propagation

> Tests *ai-memory's ability to carry binding constraints across agent boundaries*.

- **T0 (IronClaw):** IronClaw writes a constraint memory: a hard upper bound on a resource (token budget, latency, cost — pick one numeric).
- **T+N (Hermes):** Hermes is given a task that, executed naively, would violate the constraint. The Orchestrator does not tell Hermes about the constraint.
- **Pass:** Hermes either flags the constraint violation explicitly or adapts its plan to comply. Either response must be grounded in a retrieved memory operation.
- **Fail modes:** Hermes proceeds and violates (memory not consulted, or consulted but ignored), or Hermes flags from prior context rather than memory (grounding chain breaks).

#### Scenario C — Correction memory

> Tests *write semantics and read-after-write*.

- **T0 (IronClaw):** IronClaw writes a fact F. Then IronClaw is corrected (Orchestrator-injected correction) and writes the corrected fact F'. ai-memory now contains both writes.
- **T+N (Hermes):** Hermes is asked the question whose answer is F'.
- **Pass:** Hermes returns F', not F. The JSON log shows Hermes saw both writes (or saw a consolidated/superseded record) and selected the corrected one.
- **Fail modes:** Hermes returns F (returned the stale write), Hermes refuses (recall ambiguous), Hermes returns both without resolution (no contradiction-detection signal).

#### Scenario D — Federation honesty

> Tests *cross-node visibility — the NHI-layer correlate of substrate S24*.

- **T0 (IronClaw on node-1):** IronClaw writes a memory via the MCP stdio path — the path that S24 (#318) flags as bypassing federation fanout.
- **T+N (Hermes on node-2, federated peer):** Hermes recalls the same key.
- **Expected on v0.6.3.1:** Hermes does **not** see the write within the configured settle window. This is the *correct* behavior given S24's RED status; a successful recall here would mean either S24 is mis-categorized at the substrate layer or the playbook isn't exercising the bypass path.
- **Pass criterion (v0.6.3.1):** Hermes recall returns empty or stale; cross-layer consistency table records "S24 RED + Scenario D context-loss observed" as internally consistent.
- **Pass criterion (Patch 2 / v0.6.3.2):** Hermes recall returns the write; cross-layer consistency table records "S24 GREEN + Scenario D context-propagation observed" as the regression baseline.

### 6.2 Three control arms (per your direction)

Each scenario runs against **three control arms plus one treatment arm = four runs per scenario × four scenarios = sixteen runs total**.

| Arm | Configuration | What it isolates |
|---|---|---|
| **Arm-0 — Cold** | ai-memory disabled at the MCP layer. Agents see no memory tool. | Behavior baseline with no shared state at all |
| **Arm-1 — Isolated** | ai-memory enabled but each agent confined to its own private namespace. No cross-agent reads. | Isolates "did ai-memory help *this agent*" from "did ai-memory help *cross-agent context*" |
| **Arm-2 — Stubbed** | In-process dict standing in for ai-memory. Persists within a run, lost between runs. No federation. | Isolates ai-memory's distinctive features (federation, persistence, scope, audit) from the bare idea of "any memory at all" |
| **Arm-T — Treatment** | ai-memory v0.6.3.1 live, federated, mTLS, full configuration | The actual product |

Reading the four arms together yields a clean attribution chain: Arm-T versus Arm-0 measures *total ai-memory contribution*; Arm-T versus Arm-2 measures *contribution attributable to ai-memory's distinctive features*; Arm-T versus Arm-1 measures *contribution attributable specifically to cross-agent sharing*.

### 6.3 Bounding autonomy

Autonomy is the point — but unbounded runs make failure modes ambiguous. Every Phase 3 run is bounded by all three of:

- **Max turns:** 12 turns per agent per scenario.
- **Max ai-memory operations:** 50 per agent per scenario.
- **Wall-clock timeout:** 10 minutes per scenario per arm.

A run that hits any cap **terminates with a `cap_reached` flag** in the JSON log. A `cap_reached` outcome is distinct from a `refusal` outcome and from a `task_complete` outcome — the meta-analysis treats them separately.

### 6.4 Determinism controls

Within reason. Agents are LLM-driven, so full determinism is impossible, but the following are fixed before any Phase 3 run begins:

- LLM model SKU pinned per the harness baseline ([baseline.md](baseline.md) — currently `grok-4-fast-non-reasoning`). The Orchestrator records the exact SKU in every JSON log; if the runtime serves a different SKU than baseline.md names, the run is flagged `sku_mismatch` and excluded from aggregation.
- System prompts versioned and SHA-256-hashed; the hash appears in every Phase 3 record.
- Each scenario × arm combination runs **three times** (n=3). The meta-analysis reports per-run results plus aggregate.
- Random seeds (where the agent stack supports them) pinned per run and recorded in the JSON log.

Three runs × four arms × four scenarios = **48 Phase 3 runs total**, mirroring the 48-cell substrate cert grid by accident-of-arithmetic but not by design.

### 6.5 Exit artifact

48 files: `phase3-<scenario>-<arm>-run<n>.json`, each conforming to §7. Plus one aggregator file `phase3-summary.json` with run counts, completion outcomes, and pointers to the individual logs.

---

## 7. JSON log schema (binding for all phases)

Every per-turn record emitted by IronClaw or Hermes during Phases 2 and 3 conforms to the schema in [`scripts/schema/phase-log.schema.json`](../scripts/schema/phase-log.schema.json). Records that do not conform are rejected by the Orchestrator and the run is marked `malformed`.

```json
{
  "schema_version": "v0.6.3.1-a2a-nhi-1",
  "campaign_id": "<uuid>",
  "node_id": "do-<id>",
  "release": "v0.6.3.1",
  "phase": 2,
  "scenario_id": "A",
  "control_arm": "treatment",
  "run_index": 1,
  "turn_id": "<scenario>-<arm>-r<n>-t<turn>",
  "agent_id": "ai:alice",
  "agent_framework": "ironclaw",
  "timestamp_utc": "<ISO-8601>",
  "llm_model_sku": "<exact SKU string>",
  "system_prompt_sha256": "<hex>",
  "prompt_sha256": "<hex>",
  "tools_called": [
    {
      "tool_name": "<string>",
      "args_sha256": "<hex>",
      "args_size_bytes": 0,
      "result_sha256": "<hex>",
      "result_size_bytes": 0,
      "duration_ms": 0,
      "ok": true
    }
  ],
  "ai_memory_ops": [
    {
      "op": "write",
      "namespace": "<string>",
      "key_or_query": "<string>",
      "scope": "team",
      "transport": "mcp_stdio",
      "payload_sha256": "<hex>",
      "returned_records": 0,
      "duration_ms": 0,
      "ok": true
    }
  ],
  "claims_made": [
    { "claim_id": "<string>", "text_sha256": "<hex>", "category": "factual" }
  ],
  "claims_grounded": [
    { "claim_id": "<string>", "grounded_in_op_index": 0, "grounding_strength": "exact" }
  ],
  "refusals": [
    { "reason": "<string>", "category": "no_context" }
  ],
  "termination_reason": "task_complete",
  "self_confidence": 0.85,
  "notes": "<free text, ≤500 chars>"
}
```

The `claims_grounded` list is the central evidence object for Phase 4. The "% of claims grounded in retrieved memory" metric is computed as `len(claims_grounded) / len(claims_made)` per turn, then aggregated.

---

## 8. Phase 4 — Meta-analysis (third Claude instance, no namespace access)

### 8.1 Orchestrator role

A third Claude instance acts as the meta-analyst. It has read access to all Phase 3 JSON logs and Phase 1 substrate verdict. It has **no** read access to ai-memory namespaces, and **no** ability to query the agents directly. This isolation is structural — it forces the meta-analyst to reason from logs alone, which is the same posture an external auditor or enterprise buyer would have.

### 8.2 Computed metrics

For each scenario × arm × run, the meta-analyst computes:

- **Grounding rate:** `len(claims_grounded) / len(claims_made)` — fraction of claims traceable to a retrieved-memory op.
- **Hallucination rate:** `1 − grounding rate`, but only counted on `claims_made` of category `factual` or `rationale` (constraints and decisions are agent-originating, not memory-originating).
- **Cross-agent recall hit rate:** for scenarios A, B, C — fraction of the receiving agent's runs where the relevant prior write was successfully recalled.
- **Cross-layer consistency:** for scenario D — does the NHI-layer outcome match the substrate-layer S24 verdict?
- **Termination distribution:** % of runs ending `task_complete` vs. each `cap_reached` flavor vs. `refusal` vs. `error`.
- **Treatment effect:** Arm-T metric minus each control arm's metric, per-scenario. With n=3 per cell, the meta-analyst reports point estimates plus min/max range. It does **not** report p-values — n=3 doesn't support them, and reporting them would be statistical theater.

### 8.3 Cross-layer consistency table

The meta-analyst publishes a table with one row per substrate finding that has an NHI-layer correlate:

| Substrate finding | Substrate verdict | NHI correlate | NHI observation | Consistent? |
|---|---|---|---|---|
| S24 (#318) MCP stdio bypass federation | RED (expected) | Scenario D | Hermes did not recall IronClaw's MCP-stdio write within settle window | YES |
| (additional rows as findings emerge) | | | | |

Inconsistent rows are the most valuable output of the entire campaign. They mean either the substrate test or the NHI test is wrong, and either answer is high-value.

### 8.4 Findings funnel

The meta-analyst classifies each finding as:

- **Carry-forward to Patch 2 (v0.6.3.2)** — funneled into the [#511](https://github.com/alphaonedev/ai-memory-mcp/issues/511) candidate list per the existing convention.
- **Carry-forward to v0.6.4** — out of Patch 2 scope but worth tracking.
- **Harness defect** — the test, not the product, is wrong.
- **Documentation defect** — the product is correct but its documented behavior is wrong.
- **Won't fix** — the finding is real but accepted.

Each finding gets a child issue under #511 (or a separate harness-repo issue if it's a harness defect) and the classification is recorded in `phase4-analysis.json`.

### 8.5 Exit artifact

`phase4-analysis.json` containing: all computed metrics, cross-layer consistency table, findings list with classifications, narrative summary (≤2000 words) authored by the meta-analyst, and a SHA-256 manifest of every input log consumed.

---

## 9. Phase 5 — Verdict commit + findings sync

The Orchestrator publishes:

1. `releases/v0.6.3.1/summary.json` updated with Phase 1, Phase 3, and Phase 4 sections — substrate verdict (`PARTIAL — pending Patch 2` expected) plus NHI behavioral verdict (a separate field, not collapsed).
2. PR to the test-hub aggregator binding the v0.6.3.1 row to the new summary.
3. `findings-sync.yml` fires, populating the Patch 2 candidate list under [#511](https://github.com/alphaonedev/ai-memory-mcp/issues/511).
4. PR to the umbrella ai2ai-gate repo updating *Latest cert* once the cert closes per the convention in [#511](https://github.com/alphaonedev/ai-memory-mcp/issues/511).

The campaign is complete when all four are merged and the test-hub verdict cell renders correctly.

---

## 10. Decision authority and escalation

The Orchestrator has authority to:

- Halt any phase if its entry gate fails.
- Reject malformed JSON logs and require re-run.
- File harness-integrity issues (S23/S24 unexpectedly GREEN, log schema violations, transport failures).
- Classify findings under §8.4.

The Orchestrator does **not** have authority to:

- Modify scenarios A–D mid-campaign.
- Coach agents during Phase 3.
- Change control-arm definitions.
- Ship a verdict that conflates substrate and NHI evidence.

Anything outside the Orchestrator's authority escalates to the human maintainer (Jim) before action.

---

## 11. What success looks like

A maximally beneficial v0.6.3.1 campaign produces:

1. A substrate cert artifact showing `PARTIAL — pending Patch 2` with S23 + S24 RED as designed.
2. An NHI playbook artifact showing measurable, attributable treatment effects across the four scenarios — specifically, Arm-T outperforming Arm-0 on grounding rate and cross-agent recall hit rate, with the gap to Arm-2 (stubbed) isolating the value of ai-memory's distinctive features.
3. A cross-layer consistency table where every row is consistent — and if any row isn't, an explicit, owned investigation issue.
4. A Patch 2 candidate list under [#511](https://github.com/alphaonedev/ai-memory-mcp/issues/511) populated with findings the previous campaign generation could not have surfaced because it did not run autonomous NHIs through ai-memory.
5. Reproducibility: every artifact tagged with node_id, agents, release, campaign_id, and SHA-256-anchored to its inputs, such that a third party could rerun the campaign and produce the same shape of evidence.

A campaign that produces a green badge but generates no findings, no consistency-table rows, and no Patch 2 candidates is a campaign that wasted the run. The Orchestrator's job is to make the campaign earn its keep.

---

## Appendix A — Mapping of First Principles to phases

| Principle | Phase 1 | Phase 2 | Phase 3 | Phase 4 | Phase 5 |
|---|---|---|---|---|---|
| 1 — Two truth-claims | Substrate evidence | — | NHI evidence | Both, separately | Both, separately published |
| 2 — Substrate first | Runs first | Gated on Phase 1 | Gated on Phase 2 | — | — |
| 3 — Tasks require context | — | — | Scenario design | Grounding-rate metric | — |
| 4 — Structured JSON | — | Schema validation | Schema enforcement | Deterministic computation | — |
| 5 — Cross-layer consistency | S23/S24 anchors | — | Scenario D | Consistency table | Findings funnel |
| 6 — Scope discipline | Tagged artifacts | Tagged artifacts | Tagged artifacts | Tagged artifacts | Tagged commits |

---

## Appendix B — Out of scope (for absolute clarity)

- OpenClaw — runs in a separate campaign per [#511](https://github.com/alphaonedev/ai-memory-mcp/issues/511) convention.
- Infrastructure provisioning, authentication topology, mTLS cert management, Terraform — confirmed-good before Phase 0 by a separate process.
- Auto-tagging via Ollama — opt-in feature requiring `s-4vcpu-16gb` droplet, deferred from this campaign per [ai2ai-gate README](https://github.com/alphaonedev/ai-memory-ai2ai-gate).
- `memory_share` / issue #311 targeted-share scenario — depends on v0.6.0.1 capability that is upstream of v0.6.3.1 scope; revisit for v0.6.4.
- Patch 2 (v0.6.3.2) regression run — separate campaign in the `ai-memory-a2a-v0.6.3.2` repo, using this repo as a template.

---

*End of document.*
