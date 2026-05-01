#!/usr/bin/env python3
"""Validate Phase 2 / Phase 3 per-turn log records against phase-log.schema.json.

Per docs/governance.md §4 and §7. Records that fail validation are rejected by
the Orchestrator and the run is marked malformed. Used by the Phase 2/3 harness
inline (write -> validate -> commit) and by the Phase 4 meta-analyst as a
gate before consuming any record.

Usage:
    python validate_log.py path/to/record.json [path/to/another.json ...]
    cat record.json | python validate_log.py -
    python validate_log.py --schema custom-schema.json record.json

Exit codes:
    0 — every record valid
    1 — at least one record invalid
    2 — schema or input file unreadable
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    from jsonschema import Draft202012Validator
except ImportError:
    sys.stderr.write(
        "validate_log.py: jsonschema package required. Install with `pip install jsonschema`.\n"
    )
    sys.exit(2)

DEFAULT_SCHEMA = Path(__file__).parent / "phase-log.schema.json"


def load_schema(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def validate_record(validator: Draft202012Validator, record: dict, source: str) -> bool:
    errors = sorted(validator.iter_errors(record), key=lambda e: list(e.absolute_path))
    if not errors:
        return True
    sys.stderr.write(f"INVALID  {source}\n")
    for err in errors:
        path = "/".join(str(p) for p in err.absolute_path) or "<root>"
        sys.stderr.write(f"   {path}: {err.message}\n")
    return False


def iter_records(arg: str):
    if arg == "-":
        yield "<stdin>", json.load(sys.stdin)
        return
    p = Path(arg)
    if not p.is_file():
        sys.stderr.write(f"validate_log.py: not a file: {arg}\n")
        sys.exit(2)
    with p.open("r", encoding="utf-8") as fh:
        data = json.load(fh)
    if isinstance(data, list):
        for i, rec in enumerate(data):
            yield f"{arg}[{i}]", rec
    else:
        yield arg, data


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--schema", default=str(DEFAULT_SCHEMA))
    ap.add_argument("inputs", nargs="+")
    args = ap.parse_args()

    schema_path = Path(args.schema)
    if not schema_path.is_file():
        sys.stderr.write(f"validate_log.py: schema not found: {args.schema}\n")
        return 2
    validator = Draft202012Validator(load_schema(schema_path))

    all_ok = True
    for arg in args.inputs:
        for source, record in iter_records(arg):
            if not validate_record(validator, record, source):
                all_ok = False
            else:
                sys.stdout.write(f"OK       {source}\n")

    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
