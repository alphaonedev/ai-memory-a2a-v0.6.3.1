#!/usr/bin/env python3
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
"""
Phase 4 — Meta-analysis (third Claude instance, no namespace access).

Per docs/governance.md §8. Read-only over Phase 3 JSON logs + Phase 1 substrate
verdict. NO read access to ai-memory namespaces, NO ability to query agents
directly. Reasons from logs alone — same posture as an external auditor or
enterprise buyer.

## What this script computes

Deterministically, from logs only:

- **Grounding rate** — len(claims_grounded)/len(claims_made) per turn, aggregated.
- **Hallucination rate** — 1 − grounding rate, on factual + rationale categories only.
- **Cross-agent recall hit rate** — for scenarios A, B, C: receiver runs where
  the relevant prior write was successfully recalled.
- **Cross-layer consistency** — for scenario D: NHI outcome vs substrate S24 verdict.
- **Termination distribution** — task_complete vs cap_reached_* vs refusal vs error.
- **Treatment effect** — Arm-T metrics minus each control arm, per-scenario, with
  point estimates + min/max range (n=3 too small for p-values; reporting them
  would be statistical theater per governance §8.2).
- **SHA-256 manifest** of every input log consumed (provenance proof).

## What this script does NOT compute

- LLM-driven narrative summary (≤2000 words) — see governance §8.5. If
  ANTHROPIC_API_KEY is set, the script calls Claude to produce the narrative;
  otherwise it emits a stub with input-pack pointer for offline completion.
- Findings classification (§8.4) — patterns are flagged as `class=needs_review`;
  promotion to carry-forward / harness-defect / etc. is a human or LLM-assisted
  step that runs separately.

## Usage

    PHASE1_SUMMARY=releases/v0.6.3.1/summary.json     RUN_OUT_DIR=runs/$CAMPAIGN_ID     python3 scripts/phase4_meta_analyst.py

Output:
    $RUN_OUT_DIR/phase4-analysis.json     (governance §8.5 exit artifact)
    $RUN_OUT_DIR/phase4-input-manifest.txt (newline-separated SHA-256 input pack)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import statistics
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

ARMS = ("cold", "isolated", "stubbed", "treatment")
SCENARIOS = ("A", "B", "C", "D")
CARRY_FORWARD_CLASSES = (
    "carry_forward_patch2",
    "carry_forward_v0_6_4",
    "harness_defect",
    "documentation_defect",
    "wont_fix",
    "needs_review",   # default while a human / LLM hasn't classified
)


def _sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as fh:
        for chunk in iter(lambda: fh.read(64 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _safe_div(num: float, den: float) -> float:
    return num / den if den else 0.0


# ----------------------------------------------------------------------------- #
# Input loading
# ----------------------------------------------------------------------------- #

def load_phase3_runs(run_out_dir: Path) -> list[dict]:
    runs = []
    for p in sorted(run_out_dir.glob("phase3-*-*-run*.json")):
        if p.name == "phase3-summary.json":
            continue
        try:
            data = json.loads(p.read_text("utf-8"))
        except json.JSONDecodeError as e:
            sys.stderr.write(f"phase4: skipping malformed log {p.name}: {e}\n")
            continue
        data["__path"] = str(p)
        runs.append(data)
    return runs


def load_phase1_verdict(path: Path) -> dict:
    if not path.is_file():
        return {"present": False, "reason": "Phase 1 summary not found"}
    try:
        v = json.loads(path.read_text("utf-8"))
    except json.JSONDecodeError as e:
        return {"present": False, "reason": f"malformed JSON: {e}"}
    return {"present": True, "summary": v}


# ----------------------------------------------------------------------------- #
# Per-run metrics
# ----------------------------------------------------------------------------- #

def metrics_for_run(run: dict) -> dict:
    """Compute per-run metrics from §7 records."""
    records = run.get("records") or []
    total_claims = 0
    total_grounded = 0
    factual_claims = 0
    factual_grounded = 0
    recall_attempts = 0
    recall_hits = 0
    write_attempts = 0
    write_oks = 0
    op_count = 0
    for r in records:
        claims = r.get("claims_made") or []
        grounded = {g.get("claim_id") for g in (r.get("claims_grounded") or [])}
        total_claims += len(claims)
        for c in claims:
            cid = c.get("claim_id")
            cat = c.get("category")
            if cid in grounded:
                total_grounded += 1
            if cat in ("factual", "rationale"):
                factual_claims += 1
                if cid in grounded:
                    factual_grounded += 1
        for op in r.get("ai_memory_ops") or []:
            op_count += 1
            if op.get("op") == "recall":
                recall_attempts += 1
                if op.get("ok") and op.get("returned_records", 0) > 0:
                    recall_hits += 1
            elif op.get("op") == "write":
                write_attempts += 1
                if op.get("ok"):
                    write_oks += 1

    return {
        "scenario_id": run.get("scenario_id"),
        "control_arm": run.get("control_arm"),
        "run_index": run.get("run_index"),
        "termination_reason": run.get("termination_reason"),
        "wall_seconds": run.get("wall_seconds"),
        "turns": sum((run.get("turns_per_agent") or {}).values()),
        "ops": op_count,
        "claims_made": total_claims,
        "claims_grounded": total_grounded,
        "grounding_rate": _safe_div(total_grounded, total_claims),
        "factual_claims": factual_claims,
        "factual_grounded": factual_grounded,
        "hallucination_rate": 1.0 - _safe_div(factual_grounded, factual_claims) if factual_claims else 0.0,
        "recall_attempts": recall_attempts,
        "recall_hits": recall_hits,
        "recall_hit_rate": _safe_div(recall_hits, recall_attempts),
        "write_attempts": write_attempts,
        "write_oks": write_oks,
        "input_path": run.get("__path"),
        "input_sha256": _sha256_file(Path(run["__path"])) if run.get("__path") else None,
    }


# ----------------------------------------------------------------------------- #
# Aggregation across runs (per scenario × arm)
# ----------------------------------------------------------------------------- #

def aggregate_cell(per_run: list[dict]) -> dict:
    """Aggregate n=3 runs in a single (scenario, arm) cell."""
    if not per_run:
        return {"n": 0}
    grounding = [m["grounding_rate"] for m in per_run]
    halluc = [m["hallucination_rate"] for m in per_run]
    recall = [m["recall_hit_rate"] for m in per_run]
    term_dist = Counter(m.get("termination_reason") for m in per_run)
    return {
        "n": len(per_run),
        "grounding_rate_mean": statistics.fmean(grounding),
        "grounding_rate_min": min(grounding),
        "grounding_rate_max": max(grounding),
        "hallucination_rate_mean": statistics.fmean(halluc),
        "hallucination_rate_min": min(halluc),
        "hallucination_rate_max": max(halluc),
        "recall_hit_rate_mean": statistics.fmean(recall),
        "recall_hit_rate_min": min(recall),
        "recall_hit_rate_max": max(recall),
        "termination_distribution": dict(term_dist),
    }


def treatment_effect(treatment: dict, control: dict) -> dict:
    """Arm-T minus a control arm. Point estimates only — n=3 too small for p-values."""
    if not treatment or not control or treatment.get("n", 0) == 0 or control.get("n", 0) == 0:
        return {"present": False}
    return {
        "present": True,
        "delta_grounding_rate": treatment["grounding_rate_mean"] - control["grounding_rate_mean"],
        "delta_recall_hit_rate": treatment["recall_hit_rate_mean"] - control["recall_hit_rate_mean"],
        "delta_hallucination_rate": treatment["hallucination_rate_mean"] - control["hallucination_rate_mean"],
    }


# ----------------------------------------------------------------------------- #
# Cross-layer consistency
# ----------------------------------------------------------------------------- #

def cross_layer_consistency(scenario_d_aggregate: dict, phase1: dict) -> list[dict]:
    """Per §8.3. v0.6.3.1: substrate S24 RED + Scenario D context-loss = consistent."""
    rows: list[dict] = []
    s24_substrate = "UNKNOWN"
    summary = (phase1.get("summary") or {})
    scenarios = (summary.get("scenarios") or {})
    s24 = scenarios.get("S24")
    if s24 in ("RED", "FAIL", "EXPECTED_RED"):
        s24_substrate = "RED"
    elif s24 in ("GREEN", "PASS"):
        s24_substrate = "GREEN"
    elif s24:
        s24_substrate = str(s24)

    treatment = (scenario_d_aggregate.get("treatment") or {})
    nhi_recall_rate = treatment.get("recall_hit_rate_mean")

    if nhi_recall_rate is None:
        nhi_observation = "no Phase 3 Scenario D treatment data"
        consistent = "UNKNOWN"
    elif nhi_recall_rate <= 0.0:
        nhi_observation = (
            "Hermes did not recall IronClaw's MCP-stdio write within settle window "
            f"(recall hit rate={nhi_recall_rate:.2f})"
        )
        consistent = "YES" if s24_substrate == "RED" else "NO"
    else:
        nhi_observation = f"Hermes recalled the write (rate={nhi_recall_rate:.2f})"
        consistent = "YES" if s24_substrate == "GREEN" else "NO"

    rows.append({
        "substrate_finding": "S24 (#318) MCP stdio bypass federation",
        "substrate_verdict": s24_substrate,
        "nhi_correlate": "Scenario D",
        "nhi_observation": nhi_observation,
        "consistent": consistent,
        "interpretation": (
            "v0.6.3.1 expected: substrate=RED + NHI=context-loss → consistent=YES. "
            "Patch 2 baseline: substrate=GREEN + NHI=context-propagation → consistent=YES."
        ),
    })
    return rows


# ----------------------------------------------------------------------------- #
# Findings funnel — heuristic flagging only; classification is human/LLM step
# ----------------------------------------------------------------------------- #

def flag_findings(per_run_metrics: list[dict],
                   per_cell: dict[tuple[str, str], dict],
                   consistency: list[dict]) -> list[dict]:
    findings: list[dict] = []

    # Missing-cell finding: any (scenario, arm) cell with n<3
    for s in SCENARIOS:
        for a in ARMS:
            cell = per_cell.get((s, a)) or {}
            n = cell.get("n", 0)
            if n < 3:
                findings.append({
                    "id": f"missing-runs-{s}-{a}",
                    "severity": "high" if n == 0 else "medium",
                    "summary": f"Scenario {s} arm {a} has n={n} (expected 3)",
                    "class": "needs_review",
                })

    # Cap-reached finding: walltime/turn/ops cap on treatment arm
    for m in per_run_metrics:
        if m.get("control_arm") == "treatment" and m.get("termination_reason", "").startswith("cap_reached"):
            findings.append({
                "id": f"cap-{m['scenario_id']}-treatment-r{m['run_index']}",
                "severity": "medium",
                "summary": f"treatment run {m['scenario_id']}/r{m['run_index']} hit {m['termination_reason']}",
                "class": "needs_review",
            })

    # Treatment grounding-rate not exceeding cold by ≥0.20 → ai-memory not contributing
    for s in SCENARIOS:
        t = (per_cell.get((s, "treatment")) or {}).get("grounding_rate_mean")
        c = (per_cell.get((s, "cold")) or {}).get("grounding_rate_mean")
        if t is not None and c is not None and t - c < 0.20:
            findings.append({
                "id": f"weak-treatment-effect-{s}",
                "severity": "high",
                "summary": (f"treatment grounding rate ({t:.2f}) not materially above cold ({c:.2f}) "
                            f"for scenario {s} — ai-memory may not be contributing"),
                "class": "needs_review",
            })

    # Cross-layer inconsistency
    for row in consistency:
        if row.get("consistent") == "NO":
            findings.append({
                "id": f"cross-layer-inconsistent-{row['substrate_finding'].split()[0]}",
                "severity": "highest",  # most-valuable per §8.3
                "summary": f"Cross-layer inconsistency: {row['substrate_finding']} "
                           f"vs {row['nhi_correlate']} ({row['nhi_observation']})",
                "class": "needs_review",
            })

    return findings


# ----------------------------------------------------------------------------- #
# Optional Anthropic-driven narrative
# ----------------------------------------------------------------------------- #

NARRATIVE_STUB = (
    "Phase 4 narrative not produced (ANTHROPIC_API_KEY not set). To complete:\n"
    "1. Open a Claude Code session.\n"
    "2. Read phase4-analysis.json and phase4-input-manifest.txt.\n"
    "3. Author a ≤2000 word narrative summarizing:\n"
    "   - Substrate (Phase 1) verdict and what it implies for Phase 3 interpretability.\n"
    "   - Per-scenario behavioral findings (A through D).\n"
    "   - Treatment effects across the four arms with the attribution chain in §6.2.\n"
    "   - Cross-layer consistency table observations and any inconsistent rows.\n"
    "   - Top 3–5 findings recommended for Patch 2.\n"
    "4. Replace this stub in phase4-analysis.json under `narrative.text`.\n"
    "5. Re-sign / re-PR as governance §9 requires."
)


def _maybe_anthropic_narrative(analysis: dict) -> dict:
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        return {"text": NARRATIVE_STUB, "model": None, "produced_by": "stub"}
    try:
        import urllib.request
        import urllib.error
        prompt = (
            "You are the Phase 4 meta-analyst for an ai-memory v0.6.3.1 A2A campaign. "
            "You have read-only access to Phase 3 JSON logs (already reduced to metrics in the "
            "attached analysis). You have NO read access to ai-memory namespaces. Reason only "
            "from the metrics shown.\n\n"
            "Author a ≤2000-word narrative covering: substrate verdict implications, "
            "per-scenario findings (A–D), treatment effects (T vs cold/isolated/stubbed) and the "
            "attribution chain (T-cold = total ai-memory contribution; T-stubbed = distinctive-feature "
            "contribution; T-isolated = cross-agent-sharing contribution), cross-layer consistency "
            "observations, and top 3–5 findings recommended for Patch 2. Plain prose, no markdown headers.\n\n"
            f"ANALYSIS:\n{json.dumps({k:v for k,v in analysis.items() if k != 'narrative'}, indent=2)}\n"
        )
        req = urllib.request.Request(
            "https://api.anthropic.com/v1/messages",
            method="POST",
            headers={
                "x-api-key": api_key,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            data=json.dumps({
                "model": os.environ.get("ANTHROPIC_MODEL", "claude-opus-4-7"),
                "max_tokens": 4096,
                "messages": [{"role": "user", "content": prompt}],
            }).encode("utf-8"),
        )
        with urllib.request.urlopen(req, timeout=180) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        content = "".join(b.get("text", "") for b in (data.get("content") or [])
                          if isinstance(b, dict) and b.get("type") == "text")
        return {"text": content.strip(), "model": data.get("model"),
                "produced_by": "anthropic_api"}
    except Exception as e:
        return {"text": f"{NARRATIVE_STUB}\n\nAnthropic call failed: {e!r}",
                "model": None, "produced_by": "stub_after_failure"}


# ----------------------------------------------------------------------------- #
# Entry point
# ----------------------------------------------------------------------------- #

def main(argv: Iterable[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--run-out-dir", default=os.environ.get("RUN_OUT_DIR"))
    ap.add_argument("--phase1-summary", default=os.environ.get(
        "PHASE1_SUMMARY", "releases/v0.6.3.1/summary.json"))
    args = ap.parse_args(list(argv) if argv else None)

    if not args.run_out_dir:
        sys.stderr.write("phase4: --run-out-dir or RUN_OUT_DIR required\n")
        return 2
    run_out_dir = Path(args.run_out_dir)
    if not run_out_dir.is_dir():
        sys.stderr.write(f"phase4: not a directory: {run_out_dir}\n")
        return 2

    runs = load_phase3_runs(run_out_dir)
    if not runs:
        sys.stderr.write(f"phase4: no Phase 3 runs found under {run_out_dir}\n")
        return 1

    phase1 = load_phase1_verdict(Path(args.phase1_summary))

    per_run_metrics = [metrics_for_run(r) for r in runs]
    per_cell: dict[tuple[str, str], dict] = {}
    by_cell: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for m in per_run_metrics:
        by_cell[(m["scenario_id"], m["control_arm"])].append(m)
    for (s, a), ms in by_cell.items():
        per_cell[(s, a)] = aggregate_cell(ms)

    # Treatment effects per scenario
    effects_per_scenario: dict[str, dict] = {}
    for s in SCENARIOS:
        treatment = per_cell.get((s, "treatment")) or {}
        controls = {a: per_cell.get((s, a)) or {} for a in ("cold", "isolated", "stubbed")}
        effects_per_scenario[s] = {
            "treatment_aggregate": treatment,
            "vs_cold":     treatment_effect(treatment, controls["cold"]),
            "vs_isolated": treatment_effect(treatment, controls["isolated"]),
            "vs_stubbed":  treatment_effect(treatment, controls["stubbed"]),
        }

    consistency = cross_layer_consistency(effects_per_scenario.get("D", {}), phase1)
    findings = flag_findings(per_run_metrics, per_cell, consistency)

    analysis: dict[str, Any] = {
        "schema": "phase4-analysis/v1",
        "release": "v0.6.3.1",
        "campaign_id": (runs[0].get("campaign_id") if runs else "unknown"),
        "node_id": (runs[0].get("node_id") if runs else "unknown"),
        "phase1_substrate": (phase1.get("summary") or {"present": False}),
        "phase3_runs_total": len(runs),
        "phase3_runs_expected": len(SCENARIOS) * len(ARMS) * 3,
        "per_cell": {f"{s}/{a}": per_cell.get((s, a), {"n": 0})
                      for s in SCENARIOS for a in ARMS},
        "per_run_metrics": per_run_metrics,
        "treatment_effects": effects_per_scenario,
        "cross_layer_consistency_table": consistency,
        "findings": findings,
        "input_manifest_sha256": [m.get("input_sha256") for m in per_run_metrics if m.get("input_sha256")],
        "generated_at_utc": _now_iso(),
    }
    analysis["narrative"] = _maybe_anthropic_narrative(analysis)

    out = run_out_dir / "phase4-analysis.json"
    out.write_text(json.dumps(analysis, indent=2, sort_keys=True), encoding="utf-8")

    manifest = run_out_dir / "phase4-input-manifest.txt"
    with manifest.open("w", encoding="utf-8") as fh:
        for m in per_run_metrics:
            if m.get("input_sha256") and m.get("input_path"):
                fh.write(f"{m['input_sha256']}  {m['input_path']}\n")

    sys.stderr.write(f"phase4: analysis -> {out}\n")
    sys.stderr.write(f"phase4: input manifest -> {manifest}\n")
    sys.stderr.write(f"phase4: findings count = {len(findings)}; "
                     f"cross-layer rows = {len(consistency)}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
