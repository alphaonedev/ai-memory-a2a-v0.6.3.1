# Operator runbook — v0.6.3.1 First-Principles campaign

End-to-end procedure for an operator running the v0.6.3.1 A2A gated testing campaign. The campaign is governed by [`docs/governance.md`](governance.md) — that document is authoritative; this page is the operator's checklist.

The five phases (Phase 0 pre-flight → Phase 1 substrate → Phase 2 dry run → Phase 3 autonomous NHI → Phase 4 meta-analysis → Phase 5 verdict commit) execute mostly inside the `a2a-gate.yml` workflow. The operator's job is to dispatch, observe, and commit.

---

## Prerequisites

| Item | Where it lives | Purpose |
|---|---|---|
| **DigitalOcean account** + `DIGITALOCEAN_TOKEN` | GitHub repo secret | Provision the 4-node mesh in Phase 0. |
| **GitHub PAT** | `gh` CLI auth (`gh auth login`) | Dispatch workflows and post Phase 5 verdicts. |
| **`XAI_API_KEY`** | GitHub repo secret | Powers the LLM behind IronClaw / Hermes (`grok-4-fast-non-reasoning` per baseline.md). |
| **SSH key** | `~/.ssh/id_ed25519` (registered with DO; fingerprint in `DIGITALOCEAN_SSH_KEY_FINGERPRINT` repo secret) | Provision and inspect mesh nodes. |
| **Local clone of this repo** | `git clone git@github.com:alphaonedev/ai-memory-a2a-v0.6.3.1.git` | Pull run artifacts, push verdicts. |
| **`jq`** + **`gh`** locally | Homebrew / apt | Inspect run JSON; dispatch / watch workflows. |

Confirm before starting:

```sh
gh auth status
gh secret list -R alphaonedev/ai-memory-a2a-v0.6.3.1 \
  | grep -E '(DIGITALOCEAN_TOKEN|XAI_API_KEY|DIGITALOCEAN_SSH_PRIVATE_KEY|DIGITALOCEAN_SSH_KEY_FINGERPRINT)'
```

---

## Phase 0 — Pre-flight (dispatch + baseline check)

### Dispatch the workflow

Per-group, one dispatch each. Both can run concurrently — they provision distinct VPCs:

```sh
REPO=alphaonedev/ai-memory-a2a-v0.6.3.1

# IronClaw campaign (primary cert agent)
gh workflow run a2a-gate.yml -R "$REPO" \
  -f ai_memory_git_ref=v0.6.3.1 \
  -f agent_group=ironclaw \
  -f campaign_id="a2a-ironclaw-v0.6.3.1-r$(date +%s)"

# Hermes campaign (counterpart agent)
gh workflow run a2a-gate.yml -R "$REPO" \
  -f ai_memory_git_ref=v0.6.3.1 \
  -f agent_group=hermes \
  -f campaign_id="a2a-hermes-v0.6.3.1-r$(date +%s)"
```

OpenClaw is **out of scope** for v0.6.3.1 per [governance Principle 6](governance.md#principle-6-scope-discipline-this-node-these-agents-this-release). Do not dispatch with `agent_group=openclaw` against this repo.

### Watch the run

```sh
gh run list -R "$REPO" --workflow=a2a-gate.yml --limit 3
gh run watch -R "$REPO" <run-id>
gh run view  -R "$REPO" <run-id> --log-failed   # if it fails
```

### Read the Phase 0 baseline

Phase 0 emits `runs/<campaign-id>/a2a-baseline.json` and gates Phase 1 on `overall_pass=true`. Pull and inspect:

```sh
git pull --rebase
jq '.overall_pass, .reasons' runs/<campaign-id>/a2a-baseline.json
jq '[.per_node[] | {node: .node_index, pass: .baseline_pass}]' runs/<campaign-id>/a2a-baseline.json
```

`overall_pass=false` means the harness was not in a known-good state at Phase 0 entry — Phase 1 will not run. The most common per-node violations and first-fix:

| Violation field | Cause | First-fix |
|---|---|---|
| `framework_is_authentic` | Binary is a symlink to another CLI | `ssh root@<node>` and `readlink -f $(which ironclaw)`; re-run install. |
| `mcp_server_ai_memory_registered` | Config malformed | Inspect `~/.ironclaw/ironclaw.json` or `~/.hermes/config.yaml`. |
| `llm_backend_is_xai_grok` | Wrong model SKU | Spec requires `grok-4-fast-non-reasoning`; fix `default_model`. |
| `mcp_command_is_ai_memory` | MCP `command` not `ai-memory` | Re-run setup_node.sh. |
| `agent_id_stamped` | `AI_MEMORY_AGENT_ID` env not propagated | Confirm `AGENT_ID` exported before setup_node.sh. |
| `federation_live` | Local `ai-memory serve` crashed or port unreachable | Inspect `/var/log/ai-memory-serve.log`; UFW status. |
| `xai_grok_chat_reachable` (F1) | xAI key invalid / out of credit / network | `curl -v https://api.x.ai/v1/models -H "Authorization: Bearer $XAI_API_KEY"` from droplet. |
| `dead_man_switch_scheduled` | `shutdown -P +480` not running | `ps aux \| grep shutdown` on droplet. |

Re-run the workflow only after fixing the violation. Do not advance to Phase 1 with `overall_pass=false`.

---

## Phase 1 — Substrate cert (S1–S24 on the 6-cell matrix)

The workflow runs Phase 1 automatically once Phase 0 baseline is GREEN. Per [governance §4](governance.md#4-phase-1-substrate-cert-recap-not-redesign), the operator does not redesign Phase 1 — they observe and accept the published verdict.

### What you should see in `runs/<id>/`

- `scenario-S1.json` … `scenario-S24.json` — one per scenario, with `pass`, `reasons`, and a minimal repro hint for any RED.
- `a2a-summary.json` — aggregate verdict for the run.
- `summary.json` partial update of `releases/v0.6.3.1/summary.json` `substrate_verdict` block.

### Required outcome to advance to Phase 2

Per [governance §4](governance.md#4-phase-1-substrate-cert-recap-not-redesign):

```text
substrate_verdict.value = "PARTIAL — pending Patch 2"
S1–S22                 = GREEN
S23                    = RED  (issue #507 — known-open)
S24                    = RED  (issue #318 — known-open)
```

### Failure modes

- **Unexpected RED on `S1` – `S22`.** Regression on a carry-forward or v0.6.3.1-specific surface. Halt the campaign — Phase 2 must not run on a degraded substrate (Principle 2). File a `bug` + `v0.6.3.2-candidate` child issue under [#511](https://github.com/alphaonedev/ai-memory-mcp/issues/511) and re-dispatch only after the regression is understood.
- **GREEN on `S23` or `S24`.** Harness integrity violation — the harness is lying. Halt immediately and file a `harness_defect` issue. Do not commit a Phase 5 verdict.
- **Cell other than `ironclaw / mTLS` red on cert sweep.** Surfaces as a finding and may downgrade the verdict, but does not halt by itself. Record and continue if the cert cell is clean.

---

## Phase 2 — AI Orchestration Test (scripted dry run)

Per [governance §5](governance.md#5-phase-2-ai-orchestration-test-scripted-dry-run), Phase 2 is a six-step scripted dry-run of MCP wiring + namespace plumbing + JSON log sink before autonomy is enabled in Phase 3.

### What you should see in `runs/<id>/`

- `phase2-orchestration.json` — six exchange records + aggregate `pass: bool` + SHA-256 of the `audit verify` output from step 5.

The six exchanges (in order): **write round-trip → cross-agent recall → scope enforcement → tag write + tagged recall → audit verify hook → JSON log sink check**.

### Required outcome to advance to Phase 3

`phase2-orchestration.json.pass == true` and all six exchange records present and well-formed per the [§7 schema](governance.md#7-json-log-schema-binding-for-all-phases).

### Failure modes

- **Any single exchange fails.** Phase 3 does not run on a degraded Phase 2 — a Phase 3 failure with broken plumbing is indistinguishable from a Phase 3 failure caused by ai-memory itself. File a Phase 2 issue, fix, re-dispatch from Phase 0.
- **Scope leak (exchange #3 returns a private memory across agents).** Treat as a high-severity substrate defect even though Phase 1 was GREEN — it means S7 is undertesting. File `harness_defect` *and* `carry_forward_patch2` candidates.
- **Audit verify (exchange #5) returns dirty.** Halt; the audit chain is not actually tamper-evident on this run. File `carry_forward_patch2` against [`#511`](https://github.com/alphaonedev/ai-memory-mcp/issues/511).

---

## Phase 3 — Autonomous NHI playbook (4 scenarios × 4 arms × n=3 = 48 runs)

Per [governance §6](governance.md#6-phase-3-autonomous-nhi-playbook), Phase 3 runs the four scenarios (A/B/C/D) under each of the four control arms (Cold / Isolated / Stubbed / Treatment) three times each. The operator does not coach agents during Phase 3 — autonomy is the point. Caps: 12 turns, 50 ai-memory ops, 10 minutes per run.

### What you should see in `runs/<id>/`

- 48 files: `phase3-<scenario>-<arm>-run<n>.json` — each conforming to the [§7 schema](governance.md#7-json-log-schema-binding-for-all-phases).
- One aggregator: `phase3-summary.json` with run counts, completion outcomes (`task_complete` / `cap_reached` / `refusal` / `error`), and pointers to the individual logs.

### Required outcome to advance to Phase 4

All 48 logs present and schema-valid. Malformed logs are rejected and the affected scenario × arm × run combination is re-dispatched.

### Failure modes

- **`sku_mismatch` flag on any record.** The runtime served a model SKU different from baseline.md. Re-dispatch the affected run after confirming the SKU pin.
- **`malformed` flag on any record.** Schema-invalid JSON; the Orchestrator rejects and re-runs.
- **Excess `cap_reached` (>1/3 of runs in a cell).** Surface to Phase 4 — likely indicates the cap is too tight for the scenario or the agent is looping. Not a halt; recorded as a finding.
- **Cross-layer inconsistency surfaces** — e.g. substrate `S24` RED but Phase 3 Scenario D Hermes recall returns the write within the settle window. **Do not auto-resolve.** Phase 4 will compute the cross-layer consistency table and flag the inconsistent row; record it as a `harness_defect` candidate (the NHI test is broken, *or* substrate is mis-categorized — Phase 4 decides).

---

## Phase 4 — Meta-analysis (third Claude instance, no namespace access)

Per [governance §8](governance.md#8-phase-4-meta-analysis-third-claude-instance-no-namespace-access), a separate Claude instance with read-only access to the JSON logs (and **no** namespace access, **no** ability to query agents directly) computes:

- Grounding rate, hallucination rate per scenario × arm × run.
- Cross-agent recall hit rate (scenarios A / B / C).
- Cross-layer consistency for scenario D vs substrate S24.
- Termination distribution.
- Treatment effect (Arm-T − each control arm), point estimates with min/max — **no p-values** (n=3 doesn't support them).

### What you should see in `runs/<id>/`

- `phase4-analysis.json` — all metrics + cross-layer consistency table + classified findings + narrative summary (≤2000 words) + SHA-256 manifest of every input log consumed.

### Operator role

The operator does not author Phase 4 — the meta-analyst does. The operator's role is to confirm `phase4-analysis.json` exists and is signed (SHA-256 manifest of inputs), then proceed to Phase 5.

If the meta-analyst flags any finding as `needs_review`, escalate to the human maintainer (Jim) before Phase 5 commits.

---

## Phase 5 — Verdict commit + findings sync

Per [governance §9](governance.md#9-phase-5-verdict-commit-findings-sync), the operator publishes the final artifact and fires the findings sync.

### Step 1 — Update `releases/v0.6.3.1/summary.json`

Merge the Phase 1 substrate verdict block, the Phase 3 NHI verdict block, and the Phase 4 cross-layer consistency table into the schema-v2 surface. The two top-level verdicts (`substrate_verdict`, `nhi_verdict`) remain **separate** — never collapse them (Principle 1).

```sh
git pull --rebase
# (apply phase outputs to releases/v0.6.3.1/summary.json — substrate_verdict, nhi_verdict,
#  cross_layer_consistency, campaign.last_run_id, campaign.updated_at)
git add releases/v0.6.3.1/summary.json runs/<campaign-id>/
git commit -m "phase5: commit v0.6.3.1 verdict for run <campaign-id>"
git push
```

The `release-summary-gate.yml` workflow verifies the schema and rejects malformed pushes.

### Step 2 — Run `findings-sync.yml`

```sh
gh workflow run findings-sync.yml -R alphaonedev/ai-memory-a2a-v0.6.3.1
gh run watch -R alphaonedev/ai-memory-a2a-v0.6.3.1 <run-id>
```

The workflow reads `phase4-analysis.json` and opens / updates child issues on `ai-memory-mcp` for each finding tagged `carry_forward_patch2` or `carry_forward_v0_6_4`. Each issue is parent-linked to umbrella [#511](https://github.com/alphaonedev/ai-memory-mcp/issues/511) and labelled `bug` + the candidate label.

### Step 3 — Update test-hub aggregator

Open a PR on the `ai-memory-test-hub` repo to bind the v0.6.3.1 row to the new `summary.json`. The substrate verdict cell is filled from `substrate_verdict.value`; the NHI cell from `nhi_verdict.value`.

The campaign is complete when the test-hub PR merges and the v0.6.3.1 cell renders the two verdicts correctly.

---

## Patch 2 funnel

How findings make it into the v0.6.3.2 candidate list under [`#511`](https://github.com/alphaonedev/ai-memory-mcp/issues/511):

1. Phase 4 classifies the finding as `carry_forward_patch2` (per [findings.md](findings.md#finding-classes-per-governance-84)).
2. Phase 5 step 2 (`findings-sync.yml`) opens the child issue on `ai-memory-mcp`, parent-linked to #511, labelled `bug` + `v0.6.3.2-candidate`, and assigned to the `v0.6.3.2` milestone.
3. The Patch 2 candidate list under #511 is the canonical view of *everything Patch 2 needs to fix*. The known seeds are [#507](https://github.com/alphaonedev/ai-memory-mcp/issues/507) (S23) and [#318](https://github.com/alphaonedev/ai-memory-mcp/issues/318) (S24).
4. When every parent-linked issue's fix has merged on `release/v0.6.3.2` and the corresponding scenarios are GREEN on the successor [`ai-memory-a2a-v0.6.3.2`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.2) campaign's first run, #511 closes and the umbrella tracking issue is satisfied.

A finding only enters Patch 2 if it has a scenario that reproduces it, a child issue on `ai-memory-mcp`, the `v0.6.3.2-candidate` label, a parent-link to #511, and the `v0.6.3.2` milestone. Anything missing one of those does not count — re-classify under [findings §classes](findings.md#finding-classes-per-governance-84).

---

## Common operations

### Cancel a run

```sh
gh run cancel <run-id> -R alphaonedev/ai-memory-a2a-v0.6.3.1
```

`terraform destroy` runs in the `if: always()` teardown; cancellation is safe (no orphan droplets). 8h dead-man switch on every droplet is the backstop if DO API is out.

### Inspect evidence locally

```sh
git pull --rebase
cd runs/<campaign-id>

jq '.overall_pass, .reasons' a2a-summary.json
jq '[.per_node[] | {node: .node_index, pass: .baseline_pass}]' a2a-baseline.json
for f in scenario-*.json;       do echo "=== $f ===" ; jq '{scenario, pass, reasons}' "$f" ; done
for f in phase3-*-run*.json;    do jq '{scenario_id, control_arm, run_index, termination_reason}' "$f" ; done
jq '.cross_layer_consistency' phase4-analysis.json
```

### Rotate credentials

```sh
gh secret set XAI_API_KEY                         -R alphaonedev/ai-memory-a2a-v0.6.3.1
gh secret set DIGITALOCEAN_TOKEN                  -R alphaonedev/ai-memory-a2a-v0.6.3.1
gh secret set DIGITALOCEAN_SSH_PRIVATE_KEY        -R alphaonedev/ai-memory-a2a-v0.6.3.1 < ~/.ssh/id_ed25519
gh secret set DIGITALOCEAN_SSH_KEY_FINGERPRINT    -R alphaonedev/ai-memory-a2a-v0.6.3.1
```

The redaction pass on `runs/` regex-masks `xai-[A-Za-z0-9_-]{20,}` so rotated-key safety is automatic for XAI keys in historical logs.

---

## Cross-links

- [Governance](governance.md) — authoritative
- [Scope](scope.md) — what is in / out of cert
- [Matrix](matrix.md) — substrate cells + Phase 3 cells + cross-layer consistency
- [Findings](findings.md) — finding classes + Patch 2 funnel
- Phase log schema: [`scripts/schema/phase-log.schema.json`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/scripts/schema/phase-log.schema.json)
- Umbrella tracking issue: [`alphaonedev/ai-memory-mcp#511`](https://github.com/alphaonedev/ai-memory-mcp/issues/511)
