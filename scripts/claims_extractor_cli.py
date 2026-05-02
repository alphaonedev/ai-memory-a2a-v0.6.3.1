#!/usr/bin/env python3
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
"""claims_extractor_cli — thin shell-friendly wrapper around claims_extractor.

Used by drive_agent_autonomous.sh on each agent droplet. Reads the agent's
stdout from a file and the audit-log-derived ai_memory_ops JSON from another
file, calls extract(), and prints a single JSON object to stdout shaped as:

    {"tools_called": [...], "claims_made": [...], "claims_grounded": [...]}

Always exits 0 with a valid JSON object on stdout — even on parse failure —
so the calling shell can `jq -c` the result without special-casing errors.
Errors are surfaced via empty arrays + a stderr diagnostic; the wrapping
shell collapses those into the "notes" field per the §7 schema.

Usage:
    claims_extractor_cli.py \\
        --framework ironclaw|hermes \\
        --output-file PATH \\
        --ai-memory-ops PATH
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Resolve `claims_extractor` next to this CLI on disk. setup_node.sh installs
# both files together under /opt/ai-memory-a2a/, so a directory-local import
# works on the droplet without depending on PYTHONPATH.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import claims_extractor  # noqa: E402


def _read_text(path: str) -> str:
    p = Path(path)
    if not p.is_file():
        return ""
    try:
        return p.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def _read_ops(path: str) -> list[dict]:
    raw = _read_text(path).strip()
    if not raw:
        return []
    try:
        data = json.loads(raw)
    except (ValueError, TypeError) as e:
        sys.stderr.write(f"claims_extractor_cli: ai_memory_ops not JSON: {e}\n")
        return []
    return data if isinstance(data, list) else []


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--framework", required=True, choices=("ironclaw", "hermes"))
    ap.add_argument("--output-file", required=True,
                    help="Path to the agent CLI's stdout capture.")
    ap.add_argument("--ai-memory-ops", required=True,
                    help="Path to a JSON file containing the §7 ai_memory_ops array.")
    args = ap.parse_args(argv)

    raw = _read_text(args.output_file)
    ops = _read_ops(args.ai_memory_ops)

    try:
        tools_called, claims_made, claims_grounded = claims_extractor.extract(
            agent_framework=args.framework,
            agent_output_raw=raw,
            ai_memory_ops=ops,
        )
    except Exception as e:  # noqa: BLE001 — last-line-of-defense
        sys.stderr.write(f"claims_extractor_cli: extract() raised: {e}\n")
        tools_called, claims_made, claims_grounded = [], [], []

    sys.stdout.write(json.dumps({
        "tools_called": tools_called,
        "claims_made": claims_made,
        "claims_grounded": claims_grounded,
    }, sort_keys=True))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
