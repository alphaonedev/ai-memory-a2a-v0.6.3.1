#!/usr/bin/env python3
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
"""
Phase 0 preflight — orchestrator-side aggregator.

Runs the three sub-checks (check_droplets.py, check_mtls.sh,
check_federation.sh) as subprocesses, aggregates their JSON output,
and emits the canonical `a2a-baseline.json` exit artifact required by
docs/governance.md §3.

Outputs:
  - file: $RUN_OUT_DIR/a2a-baseline.json   (or ./a2a-baseline.json if RUN_OUT_DIR unset)
  - file: ./a2a-baseline.json              (always — for the workflow's artifact upload step)

Exit codes:
  0 — overall_pass=true (Phase 1 may proceed)
  1 — overall_pass=false (Phase 1 must NOT run; signals to a2a-gate.yml
      to skip Phases 1–5 via the conditional `if: <phase0 outcome>`)

Schema of a2a-baseline.json:
  {
    "schema":         "a2a-baseline/v1",
    "campaign_id":    "<from CAMPAIGN_ID>",
    "release":        "v0.6.3.1",
    "node_id":        "<orchestrator's view; do-<region>-<id>>",
    "generated_at_utc": "<ISO-8601>",
    "droplets":       [...],
    "mtls":           { "ok": ..., "details": {...} },
    "federation":     { "ok": ..., "details": {...} },
    "overall_pass":   <bool>,
    "blockers":       [...]
  }

Inputs (env):
  CAMPAIGN_ID                                   required (e.g. a2a-ironclaw-v0.6.3.1-r2)
  NODE1_IP, NODE2_IP, NODE3_IP                  required (public IPs)
  NODE4_IP or MEMORY_NODE_IP                    required (public IP)
  NODE1_PRIV, NODE2_PRIV, NODE3_PRIV, MEMORY_PRIV   optional (improves federation match)
  TLS_MODE                                      optional, default "off"
  RUN_OUT_DIR                                   optional (defaults to cwd)
  REGION                                        optional (defaults to "do" prefix only)
"""
from __future__ import annotations

import datetime as _dt
import json
import os
import pathlib
import subprocess
import sys
from typing import Any


HERE = pathlib.Path(__file__).resolve().parent
DROPLETS_PY = HERE / "check_droplets.py"
MTLS_SH = HERE / "check_mtls.sh"
FED_SH = HERE / "check_federation.sh"

# Schema regex from scripts/schema/phase-log.schema.json:
#   campaign_id: ^a2a-(ironclaw|hermes)-v0\.6\.3\.1-r[0-9]+$
#   node_id:     ^do-[a-z0-9-]+$
NODE_ID_PREFIX = "do"


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def utcnow_iso() -> str:
    """ISO-8601 UTC with trailing Z, matching the schema pattern."""
    return _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def build_node_id() -> str:
    """Synthesize an orchestrator-view node_id matching ^do-[a-z0-9-]+$.

    Per docs/governance.md §6 ("Scope discipline"), every artifact carries
    a node_id metadata tag. The orchestrator runs in GitHub Actions, not
    on a DO droplet — but the artifact is still tied to the campaign's
    DO region + campaign_id so cross-scope contamination is detectable.
    """
    region = os.environ.get("REGION", "nyc3").lower().strip() or "nyc3"
    campaign_id = os.environ.get("CAMPAIGN_ID", "unknown").lower().strip()
    # Strip campaign_id of '.' which schema rejects in node_id.
    safe_campaign = "".join(c if (c.isalnum() or c == "-") else "-" for c in campaign_id)
    raw = f"{NODE_ID_PREFIX}-{region}-{safe_campaign}"
    # Collapse double dashes & trim trailing dashes.
    while "--" in raw:
        raw = raw.replace("--", "-")
    return raw.strip("-")


def run_check(label: str, argv: list[str], *, env: dict[str, str], timeout: int = 240
              ) -> tuple[bool, dict[str, Any], str]:
    """Run a sub-check; return (succeeded, parsed_json_or_error, raw_stdout).

    `succeeded` is True iff the subprocess exited 0 AND its stdout parsed
    as JSON. Sub-check failures (e.g. ssh unreachable on one droplet)
    show up as `all_ok=false` inside parsed JSON, NOT as `succeeded=False`.
    """
    log(f"=== running {label}: {' '.join(argv)} ===")
    try:
        r = subprocess.run(
            argv, env=env, capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired as e:
        log(f"!! {label} TIMEOUT after {timeout}s")
        return False, {"error": "timeout", "timeout_s": timeout}, (e.stdout or "") if isinstance(e.stdout, str) else ""
    raw = (r.stdout or "").strip()
    if r.stderr:
        # forward sub-check stderr to ours so the workflow log shows progress
        for line in r.stderr.splitlines():
            log(f"  [{label}] {line}")
    if r.returncode != 0:
        log(f"!! {label} exited {r.returncode}")
    if not raw:
        return False, {"error": "no-stdout", "exit": r.returncode}, ""
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as e:
        log(f"!! {label} stdout not JSON: {e}")
        return False, {"error": "non-json-stdout", "raw_head": raw[:500]}, raw
    return r.returncode == 0, parsed, raw


def collect_blockers(droplets_out: dict[str, Any], mtls_out: dict[str, Any],
                     federation_out: dict[str, Any]) -> list[str]:
    blockers: list[str] = []
    # Droplets
    for d in droplets_out.get("droplets") or []:
        node = d.get("node", "?")
        if not d.get("ssh_reachable"):
            blockers.append(f"{node}: ssh unreachable")
            continue
        if not d.get("version_ok"):
            blockers.append(f"{node}: ai-memory version mismatch (got {d.get('ai_memory_version','?')})")
        if not d.get("doctor_ok"):
            blockers.append(f"{node}: doctor overall={d.get('doctor', {}).get('overall', '?')}")
        if not d.get("env_file_present"):
            blockers.append(f"{node}: /etc/ai-memory-a2a/env missing")
        elif not d.get("env_file_required_vars_present"):
            miss = d.get("env_file_missing_vars", [])
            blockers.append(f"{node}: env vars missing: {miss}")
        if not d.get("schema_version_ok"):
            blockers.append(f"{node}: schema_version!={droplets_out.get('expected_schema_version','v19')} (got {d.get('schema_version', '?')})")
    # mTLS — only blocker if not skipped and all_ok=false
    if not mtls_out.get("skipped") and not mtls_out.get("all_ok"):
        for d in mtls_out.get("droplets") or []:
            if not d.get("ok"):
                node = d.get("node", "?")
                why = []
                if not d.get("cert_files_present"):
                    why.append(f"missing cert files {d.get('missing_cert_files')}")
                if not d.get("https_listener_up"):
                    why.append("https listener down")
                if d.get("mtls_rejects_anon") is False:
                    why.append("mTLS does not reject anonymous client")
                blockers.append(f"{node}: mTLS — {'; '.join(why) or 'unknown'}")
    # Federation
    if not federation_out.get("all_ok"):
        for d in federation_out.get("agents") or []:
            if not d.get("ok"):
                node = d.get("node", "?")
                why = []
                if not d.get("peers_endpoint_reachable"):
                    why.append("/api/v1/peers not reachable")
                if d.get("missing_peers"):
                    why.append(f"missing peers {d.get('missing_peers')}")
                if not d.get("federation_status_healthy"):
                    why.append("federation status not healthy")
                blockers.append(f"{node}: federation — {'; '.join(why) or 'unknown'}")
    return blockers


def main() -> int:
    campaign_id = os.environ.get("CAMPAIGN_ID", "")
    if not campaign_id:
        log("FATAL: CAMPAIGN_ID env var is required")
        return 1

    # Resolve out-dir; mirror the artifact at ./a2a-baseline.json so the
    # workflow's actions/upload-artifact step can find it without
    # knowing RUN_OUT_DIR.
    run_out_dir = os.environ.get("RUN_OUT_DIR", "").strip()
    out_paths: list[pathlib.Path] = []
    if run_out_dir:
        p = pathlib.Path(run_out_dir)
        p.mkdir(parents=True, exist_ok=True)
        out_paths.append(p / "a2a-baseline.json")
    out_paths.append(pathlib.Path.cwd() / "a2a-baseline.json")

    # Pass-through env with a couple of sub-check expectations normalized.
    sub_env = os.environ.copy()
    if "NODE4_IP" not in sub_env and "MEMORY_NODE_IP" in sub_env:
        sub_env["NODE4_IP"] = sub_env["MEMORY_NODE_IP"]
    elif "MEMORY_NODE_IP" not in sub_env and "NODE4_IP" in sub_env:
        sub_env["MEMORY_NODE_IP"] = sub_env["NODE4_IP"]
    sub_env.setdefault("TLS_MODE", "off")

    # ---- 1. Per-droplet -------------------------------------------------
    drop_ok, droplets_out, _ = run_check(
        "check_droplets.py",
        ["python3", str(DROPLETS_PY)],
        env=sub_env, timeout=300,
    )
    if not drop_ok and "error" in droplets_out:
        droplets_out = {"droplets": [], "all_ok": False, "error": droplets_out.get("error")}

    # ---- 2. mTLS --------------------------------------------------------
    mtls_ok_run, mtls_out, _ = run_check(
        "check_mtls.sh",
        ["bash", str(MTLS_SH)],
        env=sub_env, timeout=180,
    )
    if not mtls_ok_run and "error" in mtls_out:
        mtls_out = {"droplets": [], "all_ok": False, "skipped": False, "error": mtls_out.get("error"), "tls_mode": sub_env.get("TLS_MODE", "off")}

    # ---- 3. Federation --------------------------------------------------
    fed_ok_run, fed_out, _ = run_check(
        "check_federation.sh",
        ["bash", str(FED_SH)],
        env=sub_env, timeout=180,
    )
    if not fed_ok_run and "error" in fed_out:
        fed_out = {"agents": [], "all_ok": False, "error": fed_out.get("error"), "tls_mode": sub_env.get("TLS_MODE", "off")}

    # ---- Aggregate ------------------------------------------------------
    blockers = collect_blockers(droplets_out, mtls_out, fed_out)
    overall_pass = (
        droplets_out.get("all_ok") is True
        and (mtls_out.get("skipped") is True or mtls_out.get("all_ok") is True)
        and fed_out.get("all_ok") is True
        and not blockers
    )

    artifact: dict[str, Any] = {
        "schema": "a2a-baseline/v1",
        "campaign_id": campaign_id,
        "release": "v0.6.3.1",
        "node_id": build_node_id(),
        "generated_at_utc": utcnow_iso(),
        "droplets": droplets_out.get("droplets") or [],
        "mtls": {
            "ok": bool(mtls_out.get("skipped") or mtls_out.get("all_ok")),
            "details": mtls_out,
        },
        "federation": {
            "ok": bool(fed_out.get("all_ok")),
            "details": fed_out,
        },
        "overall_pass": overall_pass,
        "blockers": blockers,
    }

    body = json.dumps(artifact, sort_keys=True, indent=2)
    for p in out_paths:
        try:
            p.write_text(body + "\n")
            log(f"wrote {p}")
        except OSError as e:
            log(f"!! could not write {p}: {e}")
    print(body)

    if overall_pass:
        log(f"Phase 0 PASS — {campaign_id}")
        return 0
    log(f"Phase 0 FAIL — {campaign_id}: {len(blockers)} blocker(s)")
    for b in blockers:
        log(f"  blocker: {b}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
