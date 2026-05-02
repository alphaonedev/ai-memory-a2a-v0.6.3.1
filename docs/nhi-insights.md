# NHI insights — narrative across the most recent campaign run

**Audience:** designers, decision-makers, and engineers who want a
*written interpretation* of the latest NHI evidence — not the raw
`phase4-analysis.json`, and not the assessor explainer
([nhi-assessments.md](nhi-assessments.md)). This page picks the
two-to-three most-revealing findings from the most-recent run, places
them in scenario × arm context, and tells the reader what the numbers
imply for v0.6.3.1 → Patch 2.

This page is **auto-generated from the most recent
`runs/<campaign>/phase4-analysis.json`**. The macro call below pulls
the latest campaign's findings, treatment effects, and cross-layer
consistency rows at site-build time, so the narrative tracks reality
on every Pages rebuild.

!!! info "How to read this page"
    The block immediately below — *"Latest run snapshot"* — is the
    machine-rendered facts. The commentary that follows is written
    interpretation: what the numbers mean, where the failure mode
    lives, and what changes for Patch 2. If the numbers below contradict
    the commentary, **trust the numbers** and file an issue against
    [findings](findings.md) — the commentary is the part that drifts.

---

## Latest run snapshot

{{ render_latest_nhi_insights() }}

---

## Commentary

The following sections interpret the snapshot above for a designer
audience. They are stable across campaign runs only insofar as the
*shape* of the campaign is stable — if treatment effects flip from
near-zero to materially positive (the Patch 2 expected outcome), the
commentary below should be revised in a follow-up PR rather than
silently kept.

### 1. Read the treatment-effect deltas first

The single most informative number on this page is
**`delta_grounding_rate` for `T − Cold` per scenario**. If it is
materially positive, ai-memory is changing what real agents *say*,
not just what the substrate *does*. If it is near zero, three
explanations are in play and only the §7 logs can disambiguate them:

1. **The substrate isn't actually getting hit.** Arm-T is configured
   wrong; agents are running in a degraded mode that looks like
   treatment but behaves like cold.
2. **The scenario doesn't require context to succeed.** Per
   [governance Principle 3](governance.md#principle-3-tasks-must-require-context-to-succeed),
   if cold succeeds, the scenario design is inflating its grounding
   floor and ai-memory has nothing to add.
3. **ai-memory is working but the agent isn't using it.** Recall ops
   appear in the JSON log but `claims_grounded` doesn't trace claims
   back to them — the agent retrieved bytes and ignored them.

Each of those is a different fix in a different repo. The findings
funnel (governance §8.4) classifies them so the right repo gets the
right issue.

### 2. The vs-Stubbed gap is the *distinctive-features* claim

A Cold-to-Treatment gap proves ai-memory > nothing. A Stubbed-to-
Treatment gap proves ai-memory > "any in-process key-value scratch".
The distinctive features that separate stubbed from treatment are
**federation, persistence, scope, and audit** — the four things
ai-memory ships beyond a `dict()`.

If `delta_grounding_rate(T − Stubbed)` is meaningfully positive on
scenarios A or B, the value of cross-run persistence + federation is
showing up in agent behavior. If it's near zero, ai-memory's
distinctive surface area is not currently load-bearing for the agents
in question — and that, too, is a finding worth funneling. It does
not mean ai-memory is wrong; it means *for this scenario set, on this
agent stack, on this release*, the distinctive features didn't bind.
That's a scope-of-utility statement worth being honest about.

### 3. Scenario D is the cross-layer probe — read it against substrate S24

Scenario D is not a normal NHI scenario. It is the **NHI-layer
correlate of substrate finding S24 (#318)** — MCP stdio writes
bypassing federation fanout. On v0.6.3.1, S24 is RED *by design*.
The scenario D pass criterion on v0.6.3.1 is therefore *Hermes does
not recall IronClaw's MCP-stdio write* — i.e., context loss is
expected, and the cross-layer consistency row should read **YES**
(both layers agree the bypass is real).

What to look for in the snapshot above:

- If the snapshot's Scenario D `consistent` cell shows **YES**, the
  campaign found no surprise — substrate and NHI layers agree on
  v0.6.3.1's known gap.
- If it shows **UNKNOWN** with `nhi_observation: no Phase 3 Scenario D
  treatment data`, scenario D didn't run cleanly and the cross-layer
  claim cannot yet be made for this run.
- If it shows **NO**, that is the most valuable signal in the entire
  campaign. Either substrate S24 is mis-categorized or the NHI
  scenario D isn't exercising the bypass path. Both possibilities get
  a child issue under
  [#511](https://github.com/alphaonedev/ai-memory-mcp/issues/511).

When Patch 2 lands and S24 flips GREEN, the scenario D pass criterion
flips with it: Hermes *should* recall the write, and the consistency
row reads **YES** for the new reason. That symmetry — substrate verdict
and NHI observation flipping together — is the cleanest cross-layer
regression baseline this harness can produce.

### 4. Findings classification — what each row implies

The snapshot's findings list is classified per
[governance §8.4](governance.md#84-findings-funnel). Each row implies
a different downstream action:

- **`carry_forward` → Patch 2 (v0.6.3.2)** — funneled into the
  [#511](https://github.com/alphaonedev/ai-memory-mcp/issues/511)
  candidate list.
- **`carry_forward` → v0.6.4** — out of Patch 2 scope but tracked.
- **`harness_defect`** — the test, not the product, is wrong; child
  issue lands in the harness repo, not ai-memory-mcp.
- **`docs_defect`** — the product is correct but its documented
  behavior is wrong; landing PR in ai-memory's docs.
- **`wont_fix`** — real but accepted; recorded in `phase4-analysis.json`
  for posterity.
- **`needs_review`** — the meta-analyst couldn't classify
  unambiguously; flagged for human triage before Phase 5 commit.

A `needs_review` finding labeled *"weak treatment effect"* on a
scenario with all-zero arms typically means **Phase 3 didn't produce
usable agent traffic for that scenario × arm cell** (e.g., agent
errored out before any `ai_memory_ops` were emitted). That is a
harness-side outcome, not a substrate-side one — the fix is in the
phase 3 driver, not in ai-memory-mcp.

---

## Where to go next

- **[AI NHI assessment explainer](nhi-assessments.md)** — what the
  scenarios, arms, and metrics *are* (not what the latest numbers
  *say*).
- **[Per-run NHI matrix](nhi/index.md)** — every run's NHI verdict alongside
  the substrate verdict, with scenario × arm grounding-rate cells.
- **[Findings funnel](findings.md)** — downstream destinations for
  every finding classified above.
- **[Governance §8](governance.md#8-phase-4-meta-analysis-third-claude-instance-no-namespace-access)** — exact metric definitions for grounding rate,
  hallucination rate, recall hit rate, and treatment effect.
