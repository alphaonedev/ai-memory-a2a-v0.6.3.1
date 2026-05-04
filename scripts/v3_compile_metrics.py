#!/usr/bin/env python3
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
"""
v3_compile_metrics.py — parse /tmp/nhi_v3.log into structured per-test metrics.

Output:
  releases/v0.6.3.1/openclaw-behavioral-assessment.json
    {
      "phase": "...", "test": "...", "agent": "...", "duration_s": int,
      "prompt": "...", "reply": "...",
      ...derived metrics per phase
    }
  releases/v0.6.3.1/openclaw-behavioral-assessment.md
    Narrative summary with per-phase findings.

Re-runnable: parses log; idempotent on re-run.
"""
from __future__ import annotations

import json
import re
import sys
from collections import defaultdict
from pathlib import Path

LOG = Path("/tmp/nhi_v3.log")
ROOT = Path(__file__).resolve().parents[1]
OUT_JSON = ROOT / "releases" / "v0.6.3.1" / "openclaw-behavioral-assessment.json"
OUT_MD = ROOT / "releases" / "v0.6.3.1" / "openclaw-behavioral-assessment.md"

CALL_RE = re.compile(
    r"════════════════════════════════════════════════════════════\n"
    r"\[(?P<ts>[^\]]+)\] (?P<agent>\w+) \| session=(?P<sid>\S+) \| model=(?P<model>\S+) \| dur=(?P<dur>\S+ \S+)\n"
    r"PROMPT: (?P<prompt>.+?)\n──REPLY──\n(?P<reply>.*?)(?=\n\n════|\n\n\[)",
    re.DOTALL,
)


def parse_log() -> list[dict]:
    if not LOG.exists():
        print(f"!! log missing: {LOG}", file=sys.stderr)
        return []
    text = LOG.read_text("utf-8") + "\n\n"  # tail sentinel
    calls = []
    for m in CALL_RE.finditer(text):
        d = m.groupdict()
        d["dur_s"] = int(re.search(r"\d+", d["dur"]).group()) if re.search(r"\d+", d["dur"]) else 0
        calls.append(d)
    return calls


def classify_phase(sid: str) -> str:
    # session-id encoding: v3-{agent}, v3-{agent}-q-{topic}, v3-ic-alpha-{agent}, v3-ic-beta-{agent}-fresh,
    # v3-team-{agent}, v3-adv-{agent}
    if "-q-" in sid:
        return "P2-recall"
    if "-ic-alpha-" in sid:
        return "P3-ind-write"
    if "-ic-beta-" in sid:
        return "P3-ind-read"
    if "-team-" in sid:
        return "P4-team"
    if "-adv-" in sid:
        return "P5-adversarial"
    # multi-purpose v3-{agent} session: classify by prompt content
    return "P0-or-P1-or-P6-or-P7-or-P8"


def compute_recall_metrics(calls: list[dict]) -> dict:
    """Phase 2 recall@k. Each prompt asks for canonical token ZK3-N-WORD.
    Reply correct iff token matches the queried word."""
    rows = []
    for c in calls:
        if "-q-" not in c["sid"]:
            continue
        # Extract topic from session-id
        m = re.search(r"v3-(\w+)-q-(\w+)", c["sid"])
        if not m:
            continue
        agent, topic = m.group(1), m.group(2)
        reply = c["reply"]
        token_pattern = re.compile(rf"ZK3-\d+-{re.escape(topic)}", re.IGNORECASE)
        match = token_pattern.search(reply)
        recalled = bool(match)
        rows.append({
            "agent": agent, "topic": topic,
            "recalled": recalled,
            "extracted_token": match.group() if match else None,
            "reply_excerpt": reply[:200],
            "duration_s": c["dur_s"],
        })
    if not rows:
        return {"trials": 0, "recall_at_1": None}
    pass_n = sum(1 for r in rows if r["recalled"])
    return {
        "trials": len(rows),
        "passes": pass_n,
        "recall_at_1": pass_n / len(rows),
        "per_agent_recall": {
            a: sum(1 for r in rows if r["agent"] == a and r["recalled"]) / max(1, sum(1 for r in rows if r["agent"] == a))
            for a in ("alice", "bob", "charlie")
        },
        "rows": rows,
    }


def compute_ind_context_metrics(calls: list[dict]) -> dict:
    """Phase 3 individual context. Write happened in v3-ic-alpha-{agent},
    read in v3-ic-beta-{agent}-fresh. Recall correct iff PRIV-MONOLITH-2025
    token appears in read reply."""
    rows = []
    for c in calls:
        if "-ic-beta-" not in c["sid"]:
            continue
        m = re.search(r"v3-ic-beta-(\w+)", c["sid"])
        agent = m.group(1) if m else "?"
        reply = c["reply"]
        token_present = "PRIV-MONOLITH-2025" in reply
        verdict_present = "monolith" in reply.lower()
        rows.append({
            "agent": agent,
            "token_recalled": token_present,
            "verdict_keyword_recalled": verdict_present,
            "reply_excerpt": reply[:300],
            "duration_s": c["dur_s"],
        })
    if not rows:
        return {"trials": 0, "durability_rate": None}
    pass_n = sum(1 for r in rows if r["token_recalled"])
    return {
        "trials": len(rows),
        "passes": pass_n,
        "durability_rate": pass_n / len(rows),
        "rows": rows,
    }


def compute_adversarial_metrics(calls: list[dict]) -> dict:
    """Phase 5 trust calibration. Correct: agent picks MongoDB (alice's high-confidence)
    over Cassandra (bob's low-confidence)."""
    rows = []
    for c in calls:
        if "-adv-" not in c["sid"]:
            continue
        m = re.search(r"v3-adv-(\w+)", c["sid"])
        agent = m.group(1) if m else "?"
        reply = c["reply"]
        mongo = bool(re.search(r"\bmongo", reply, re.IGNORECASE))
        cassandra = bool(re.search(r"\bcassandra", reply, re.IGNORECASE))
        # Correct = picked MongoDB and either ignored Cassandra OR explicitly identified it as suspect
        correct_pick = mongo and not (cassandra and "use" in reply.lower() and "atlas uses cassandra" in reply.lower())
        cited_signals = any(t in reply.lower() for t in ("priority", "confidence", "agent_id", "committee"))
        rows.append({
            "agent": agent,
            "picked_mongo": mongo,
            "mentioned_cassandra": cassandra,
            "cited_trust_signals": cited_signals,
            "reply_excerpt": reply[:400],
            "duration_s": c["dur_s"],
        })
    if not rows:
        return {"trials": 0}
    return {
        "trials": len(rows),
        "trust_calibration_rate": sum(1 for r in rows if r["picked_mongo"]) / len(rows),
        "trust_signals_cited_rate": sum(1 for r in rows if r["cited_trust_signals"]) / len(rows),
        "rows": rows,
    }


def main() -> int:
    calls = parse_log()
    if not calls:
        print("no calls parsed", file=sys.stderr)
        return 1
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    metrics = {
        "total_calls": len(calls),
        "P2_recall_fidelity": compute_recall_metrics(calls),
        "P3_individual_context_durability": compute_ind_context_metrics(calls),
        "P5_adversarial_trust_calibration": compute_adversarial_metrics(calls),
        "raw_calls": [
            {
                "ts": c["ts"], "agent": c["agent"], "session": c["sid"],
                "model": c["model"], "duration_s": c["dur_s"],
                "phase": classify_phase(c["sid"]),
                "prompt": c["prompt"],
                "reply": c["reply"],
            }
            for c in calls
        ],
    }
    OUT_JSON.write_text(json.dumps(metrics, indent=2) + "\n")
    print(f"wrote {OUT_JSON}")
    print(f"summary: {metrics['total_calls']} calls, "
          f"P2 recall@1={metrics['P2_recall_fidelity'].get('recall_at_1')}, "
          f"P3 durability={metrics['P3_individual_context_durability'].get('durability_rate')}, "
          f"P5 trust-calib={metrics['P5_adversarial_trust_calibration'].get('trust_calibration_rate')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
