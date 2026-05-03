#!/usr/bin/env python3
"""Merge phase3-summary-A-D.json + phase3-summary-E-J.json → phase3-summary.json.

Phase 3 is split into two passes (A-D@n=3 + E-J@n=2) to fit the workflow
timeout budget. Each pass writes its own summary file; this script
unions them so Phase 4 sees a single canonical phase3-summary.json.
"""
import json
import pathlib
import sys


def load(p: pathlib.Path):
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else None


def main(argv):
    if len(argv) != 2:
        print("usage: phase3_merge_summaries.py <campaign_dir>", file=sys.stderr)
        return 2
    d = pathlib.Path(argv[1])
    s1 = load(d / "phase3-summary-A-D.json")
    s2 = load(d / "phase3-summary-E-J.json")
    out = d / "phase3-summary.json"
    if s1 and s2:
        merged = {
            **s1,
            "scenarios": sorted(set(s1.get("scenarios", [])) | set(s2.get("scenarios", []))),
            "runs_per_cell": {"A-D": s1.get("runs_per_cell"), "E-J": s2.get("runs_per_cell")},
            "expected_runs": s1.get("expected_runs", 0) + s2.get("expected_runs", 0),
            "actual_runs": s1.get("actual_runs", 0) + s2.get("actual_runs", 0),
            "runs": s1.get("runs", []) + s2.get("runs", []),
        }
        out.write_text(json.dumps(merged, indent=2, sort_keys=True), encoding="utf-8")
        print(f"merged {len(merged['runs'])} cells → {out}")
        return 0
    if s1:
        out.write_text(json.dumps(s1, indent=2, sort_keys=True), encoding="utf-8")
        print(f"only A-D pass present, copied → {out}")
        return 0
    if s2:
        out.write_text(json.dumps(s2, indent=2, sort_keys=True), encoding="utf-8")
        print(f"only E-J pass present, copied → {out}")
        return 0
    print("no phase3-summary-*.json found, nothing to merge", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
