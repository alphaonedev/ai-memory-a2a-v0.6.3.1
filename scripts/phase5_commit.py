#!/usr/bin/env python3
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
"""
Phase 5 — Verdict commit + findings sync.

Per docs/governance.md §9. After Phase 4 signs off, this script:

1. Updates `releases/v0.6.3.1/summary.json` with the Phase 1, Phase 3, and Phase 4
   sections — separate `substrate_verdict` and `nhi_verdict` fields (Principle 1).
2. Computes `last_run_id`, `updated_at`.
3. Commits the updated summary on the campaign branch (does NOT push — pushing
   is the operator's call so an audit trail of "who pushed the verdict" exists).
4. Emits an issue-comment payload to stdout (or to a file via --findings-out)
   that the `findings-sync.yml` workflow consumes to populate the Patch 2
   candidate list under #511.

Phase 5 does NOT open the umbrella PR or modify the test-hub aggregator —
those are operator steps because they cross repo boundaries (#511 in
ai-memory-mcp, the test-hub repo). This script produces the deliverables
those steps need; the operator pastes/commits them.

## Usage

    CAMPAIGN_ID=a2a-ironclaw-v0.6.3.1-r2     RUN_OUT_DIR=runs/$CAMPAIGN_ID     python3 scripts/phase5_commit.py [--no-commit] [--findings-out path]

Output:
    releases/v0.6.3.1/summary.json   (mutated)
    runs/$CAMPAIGN_ID/phase5-findings.md   (issue-comment-ready Markdown)
    stdout                               (the same Markdown for piping)

Exit 0 on clean update; 1 if Phase 4 inputs are missing or malformed.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent
SUMMARY_PATH = REPO_ROOT / "releases" / "v0.6.3.1" / "summary.json"


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def load_phase4(run_out_dir: Path) -> dict:
    p = run_out_dir / "phase4-analysis.json"
    if not p.is_file():
        sys.stderr.write(f"phase5: missing {p}; run phase4 first\n")
        sys.exit(1)
    return json.loads(p.read_text("utf-8"))


def load_phase1(run_out_dir: Path) -> dict:
    """Phase 1 substrate is the existing summary.json's substrate_verdict block,
    refreshed by the substrate-cert workflow. We read the canonical surface."""
    if not SUMMARY_PATH.is_file():
        sys.stderr.write(f"phase5: missing {SUMMARY_PATH}\n")
        sys.exit(1)
    return json.loads(SUMMARY_PATH.read_text("utf-8"))


def derive_substrate_verdict(scenarios: dict[str, str], expected_red: list[str]) -> str:
    """Per governance §4 verdict rules: PARTIAL if S23/S24 RED + everything else GREEN."""
    if not scenarios:
        return "PENDING"
    expected_set = set(expected_red)
    statuses = list(scenarios.items())
    non_expected_red = [s for s, v in statuses if s not in expected_set and v in ("RED", "FAIL")]
    if non_expected_red:
        return "FAIL"
    expected_actual_red = [s for s in expected_set if scenarios.get(s) in ("RED", "FAIL", "EXPECTED_RED")]
    expected_actual_green = [s for s in expected_set if scenarios.get(s) in ("GREEN", "PASS")]
    pending = [s for s, v in statuses if v in ("PENDING", "UNKNOWN", "PENDING_EXPECTED_RED")]
    if expected_actual_green:
        return "HARNESS_INTEGRITY_FAILURE"
    if pending:
        return "PENDING"
    if len(expected_actual_red) == len(expected_set):
        return "PARTIAL — pending Patch 2"
    return "FAIL"


def derive_nhi_verdict(phase4: dict) -> tuple[str, dict]:
    """Boil down Phase 4 metrics into a single NHI verdict.

    PASS when treatment outperforms cold by ≥0.20 grounding rate on every scenario
    AND there are no `class=needs_review` findings of severity=highest. Otherwise
    NEEDS_REVIEW unless the per-scenario picture is clearly bad → FAIL.
    """
    effects = phase4.get("treatment_effects", {})
    findings = phase4.get("findings", [])
    has_highest = any(f.get("severity") == "highest" for f in findings)
    weak_scenarios = []
    for s, e in effects.items():
        delta = ((e.get("vs_cold") or {}).get("delta_grounding_rate"))
        if delta is None or delta < 0.20:
            weak_scenarios.append(s)
    detail = {"weak_scenarios": weak_scenarios, "has_highest_severity_finding": has_highest}
    if has_highest:
        return "NEEDS_REVIEW", detail  # cross-layer inconsistency or similar — flag, don't pass
    if not weak_scenarios:
        return "PASS", detail
    if len(weak_scenarios) >= 3:
        return "FAIL", detail
    return "NEEDS_REVIEW", detail


def render_findings_md(phase4: dict, campaign_id: str, substrate_v: str, nhi_v: str) -> str:
    findings = phase4.get("findings", [])
    consistency = phase4.get("cross_layer_consistency_table", [])
    lines: list[str] = []
    lines.append(f"## v0.6.3.1 A2A campaign — Phase 5 verdict roll-up ({_now_iso()})")
    lines.append("")
    lines.append(f"- **Campaign:** `{campaign_id}`")
    lines.append(f"- **Substrate verdict:** `{substrate_v}`")
    lines.append(f"- **NHI verdict:** `{nhi_v}`")
    lines.append(f"- **Phase 3 runs collected:** {phase4.get('phase3_runs_total', 0)} / "
                 f"{phase4.get('phase3_runs_expected', 0)}")
    lines.append("")
    lines.append("### Cross-layer consistency")
    if consistency:
        lines.append("| Substrate finding | Substrate | NHI correlate | NHI observation | Consistent |")
        lines.append("|---|---|---|---|---|")
        for row in consistency:
            lines.append(f"| {row.get('substrate_finding')} | {row.get('substrate_verdict')} | "
                          f"{row.get('nhi_correlate')} | {row.get('nhi_observation')} | "
                          f"{row.get('consistent')} |")
    else:
        lines.append("_No cross-layer rows produced — Phase 3/D missing or empty._")
    lines.append("")
    lines.append("### Findings funnel — needs classification")
    if findings:
        for f in findings:
            sev = f.get("severity", "?")
            cls = f.get("class", "needs_review")
            lines.append(f"- **[{sev}]** `{f.get('id')}` ({cls}) — {f.get('summary')}")
    else:
        lines.append("_No findings flagged. Reviewer should still confirm — a campaign that emits no findings is suspicious._")
    lines.append("")
    lines.append("### Next actions for the maintainer")
    lines.append("1. Classify `needs_review` findings into the §8.4 buckets "
                 "(carry-forward Patch 2 / v0.6.4 / harness-defect / docs-defect / wont-fix).")
    lines.append("2. For each `carry_forward_patch2` finding, open a child issue under "
                 "[#511](https://github.com/alphaonedev/ai-memory-mcp/issues/511) and link it here.")
    lines.append("3. Push the updated `releases/v0.6.3.1/summary.json` and trigger "
                 "`findings-sync.yml` from the campaign repo.")
    lines.append("4. Open the test-hub aggregator PR binding the v0.6.3.1 row to this summary.")
    lines.append("")
    lines.append("_Generated by `scripts/phase5_commit.py` per docs/governance.md §9._")
    return "\n".join(lines)


def update_summary_json(summary: dict, phase4: dict, campaign_id: str,
                        substrate_v: str, nhi_v: str, run_out_dir: Path) -> dict:
    """Mutate the §summary fields per Principle 1 (separate substrate + NHI)."""
    summary["campaign"]["last_run_id"] = campaign_id
    summary["campaign"]["updated_at"] = _now_iso()

    summary["substrate_verdict"]["value"] = substrate_v

    # Top-level `version` + `verdict` are flat shims for release-summary-gate.yml.
    # version mirrors subject.tag; verdict is a derived 3-state collapse:
    #   pass  iff substrate ∈ {PASS, "PARTIAL — pending Patch 2"} AND nhi=PASS
    #   fail  iff substrate=FAIL OR substrate=HARNESS_INTEGRITY_FAILURE OR nhi=FAIL
    #   pending otherwise
    summary["version"] = (summary.get("subject") or {}).get("tag", summary.get("version"))
    if substrate_v in ("FAIL", "HARNESS_INTEGRITY_FAILURE") or nhi_v == "FAIL":
        summary["verdict"] = "fail"
    elif substrate_v in ("PASS", "PARTIAL — pending Patch 2") and nhi_v == "PASS":
        summary["verdict"] = "pass"
    else:
        summary["verdict"] = "pending"

    nhi = summary.setdefault("nhi_verdict", {})
    nhi["value"] = nhi_v
    p4_path = run_out_dir / "phase4-analysis.json"
    try:
        nhi["phase4_analysis_path"] = str(p4_path.resolve().relative_to(REPO_ROOT))
    except ValueError:
        # RUN_OUT_DIR outside repo root (e.g. /tmp); record the absolute path.
        nhi["phase4_analysis_path"] = str(p4_path)
    effects = phase4.get("treatment_effects", {})
    for s, e in effects.items():
        if s not in nhi.get("scenarios", {}):
            continue
        cell = nhi["scenarios"][s]
        treatment = e.get("treatment_aggregate") or {}
        if s == "D":
            cell["treatment_recall_hit_rate"] = treatment.get("recall_hit_rate_mean")
        else:
            cell["treatment_grounding_rate"] = treatment.get("grounding_rate_mean")
            cell["vs_cold"]     = (e.get("vs_cold") or {}).get("delta_grounding_rate")
            cell["vs_isolated"] = (e.get("vs_isolated") or {}).get("delta_grounding_rate")
            cell["vs_stubbed"]  = (e.get("vs_stubbed") or {}).get("delta_grounding_rate")
        # per-scenario verdict
        delta = (e.get("vs_cold") or {}).get("delta_grounding_rate")
        if delta is None:
            cell["verdict"] = "PENDING"
        elif delta >= 0.20:
            cell["verdict"] = "PASS"
        elif delta >= 0.05:
            cell["verdict"] = "WEAK"
        else:
            cell["verdict"] = "FAIL"

    table = phase4.get("cross_layer_consistency_table", [])
    if table:
        summary["cross_layer_consistency"]["table"] = table
        any_pending = any(row.get("consistent") == "PENDING" for row in table)
        any_no = any(row.get("consistent") == "NO" for row in table)
        if any_no:
            summary["cross_layer_consistency"]["value"] = "INCONSISTENT"
        elif any_pending:
            summary["cross_layer_consistency"]["value"] = "PENDING"
        else:
            summary["cross_layer_consistency"]["value"] = "CONSISTENT"
    return summary


def maybe_commit(message: str, *, dry_run: bool) -> tuple[bool, str]:
    if dry_run:
        return False, "skipped (--no-commit)"
    try:
        subprocess.check_call(["git", "-C", str(REPO_ROOT), "add",
                                "releases/v0.6.3.1/summary.json"])
        subprocess.check_call(["git", "-C", str(REPO_ROOT), "commit", "-m", message])
        return True, "committed"
    except subprocess.CalledProcessError as e:
        return False, f"commit failed: {e}"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--run-out-dir", default=os.environ.get("RUN_OUT_DIR"))
    ap.add_argument("--no-commit", action="store_true",
                    help="Compute + write summary.json + emit findings.md, but do not git-commit.")
    ap.add_argument("--findings-out", default=None,
                    help="Write the findings Markdown here (default: $RUN_OUT_DIR/phase5-findings.md).")
    args = ap.parse_args(argv)

    if not args.run_out_dir:
        sys.stderr.write("phase5: --run-out-dir or RUN_OUT_DIR required\n")
        return 1
    run_out_dir = Path(args.run_out_dir).resolve()
    campaign_id = os.environ.get("CAMPAIGN_ID") or run_out_dir.name

    phase4 = load_phase4(run_out_dir)
    summary = load_phase1(run_out_dir)

    substrate_v = derive_substrate_verdict(
        summary.get("substrate_verdict", {}).get("scenarios", {}),
        summary.get("substrate_verdict", {}).get("expected_red", []) or [])
    nhi_v, _detail = derive_nhi_verdict(phase4)

    summary = update_summary_json(summary, phase4, campaign_id,
                                   substrate_v, nhi_v, run_out_dir)
    SUMMARY_PATH.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n",
                             encoding="utf-8")
    sys.stderr.write(f"phase5: summary.json updated -> {SUMMARY_PATH}\n")

    md = render_findings_md(phase4, campaign_id, substrate_v, nhi_v)
    findings_path = Path(args.findings_out) if args.findings_out else (run_out_dir / "phase5-findings.md")
    findings_path.parent.mkdir(parents=True, exist_ok=True)
    findings_path.write_text(md, encoding="utf-8")
    sys.stderr.write(f"phase5: findings markdown -> {findings_path}\n")
    print(md)

    msg = (f"campaign({campaign_id}): substrate={substrate_v} nhi={nhi_v}\n\n"
           f"Phase 5 verdict-commit per docs/governance.md §9.\n"
           f"Phase 4 analysis: {run_out_dir}/phase4-analysis.json\n"
           f"Findings funnel: {findings_path.name}\n\n"
           "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>")
    ok, status = maybe_commit(msg, dry_run=args.no_commit)
    sys.stderr.write(f"phase5: git commit: {status}\n")
    return 0 if ok or args.no_commit else 1


if __name__ == "__main__":
    sys.exit(main())
