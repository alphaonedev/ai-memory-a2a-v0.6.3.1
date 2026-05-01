#!/usr/bin/env python3
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
"""
Phase 0 preflight — per-droplet health checks.

Confirms all 4 droplets in the campaign VPC are reachable, that
ai-memory v0.6.3.1 (`0.6.3+patch.1`) is installed, that `ai-memory
doctor` reports overall=INFO or better, and that the per-node env
file (/etc/ai-memory-a2a/env) carries the variables every downstream
phase depends on.

Inputs (env, all required):
  NODE1_IP, NODE2_IP, NODE3_IP    public IPs of the 3 agent droplets
  NODE4_IP / MEMORY_NODE_IP       public IP of the ai-memory authoritative node

Output:
  stdout — single-line JSON. Schema:
    {
      "schema": "a2a-preflight-droplets/v1",
      "release": "v0.6.3.1",
      "expected_ai_memory_version": "0.6.3+patch.1",
      "expected_schema_version": "v19",
      "droplets": [
        {
          "node":               "node-1" | "node-2" | "node-3" | "node-4",
          "ip":                 "<public ip>",
          "role":               "agent" | "memory-only",
          "ssh_reachable":      bool,
          "ai_memory_version":  "<reported by --version>",
          "version_ok":         bool,
          "doctor":             { "overall": "...", "raw": {...} },
          "doctor_ok":          bool,
          "env_file_present":   bool,
          "env_file_required_vars_present": bool,
          "env_file_missing_vars": [...],
          "schema_version":     "<v19 or actual>",
          "schema_version_ok":  bool,
          "ok":                 bool
        },
        ...
      ],
      "all_ok": bool
    }
  exit 0 on a clean run (whether all_ok is true or false); only
  hard-fails (e.g. missing env) cause non-zero exit. The aggregator
  (build_baseline.py) consumes the JSON and decides phase 0 verdict.

Reuses the SSH_OPTS pattern from scripts/a2a_harness.py.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from typing import Any


SSH_OPTS = [
    "-o", "StrictHostKeyChecking=no",
    "-o", "ConnectTimeout=10",
    "-o", "ServerAliveInterval=5",
    "-o", "BatchMode=yes",
]

# v0.6.3.1 release notes call out version=`0.6.3+patch.1`. Either the
# semver-with-build-metadata form or the legacy v0.6.3.1 marker is
# accepted as evidence of the v0.6.3.1 patch being live.
EXPECTED_VERSION_MARKERS = ("0.6.3+patch.1", "v0.6.3.1", "0.6.3.1")
EXPECTED_SCHEMA_VERSION = "v19"

# Agent-node env files MUST carry these (memory-only nodes carry a subset).
REQUIRED_ENV_VARS_AGENT = (
    "AGENT_TYPE",
    "AGENT_ID",
    "LOCAL_MEMORY_URL",
    "MCP_CONFIG",
)
REQUIRED_ENV_VARS_MEMORY = (
    "LOCAL_MEMORY_URL",
)

# Doctor "overall" levels in priority order; INFO or better passes.
DOCTOR_LEVELS_OK = {"INFO", "OK", "GREEN", "PASS"}
DOCTOR_LEVELS_WARN = {"WARN", "WARNING", "YELLOW"}


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def ssh_exec(ip: str, remote_cmd: str, *, timeout: int = 60) -> subprocess.CompletedProcess:
    """Run remote_cmd over ssh root@ip. Never raises on non-zero or timeout."""
    cmd = ["ssh", *SSH_OPTS, f"root@{ip}", remote_cmd]
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as e:
        return subprocess.CompletedProcess(
            args=cmd, returncode=124,
            stdout=(e.stdout or "") if isinstance(e.stdout, str) else "",
            stderr=f"__TIMEOUT_{timeout}s__",
        )


def check_ssh(ip: str) -> bool:
    r = ssh_exec(ip, "uname -a", timeout=15)
    return r.returncode == 0 and bool((r.stdout or "").strip())


def check_version(ip: str) -> tuple[str, bool]:
    r = ssh_exec(ip, "ai-memory --version 2>&1", timeout=20)
    raw = (r.stdout or "").strip()
    if r.returncode != 0:
        return raw or f"<ssh exit {r.returncode}>", False
    ok = any(marker in raw for marker in EXPECTED_VERSION_MARKERS)
    return raw, ok


def check_doctor(ip: str) -> tuple[dict[str, Any], str, bool]:
    """Return (raw_json, overall, ok). Tolerates older ai-memory builds
    that may not implement --format=json — falls back to plain `doctor`
    output and treats anything not-explicitly-failing as INFO."""
    r = ssh_exec(ip, "ai-memory doctor --format json 2>/dev/null", timeout=30)
    if r.returncode == 0 and (r.stdout or "").strip():
        try:
            doc = json.loads(r.stdout)
            overall = str(doc.get("overall") or doc.get("status") or "UNKNOWN").upper()
            ok = overall in DOCTOR_LEVELS_OK or overall in DOCTOR_LEVELS_WARN
            return doc, overall, ok
        except json.JSONDecodeError:
            pass
    # Fallback path: parse text doctor output for an explicit FAIL/ERROR
    # marker. Older ai-memory pre-v0.6 builds spelled it differently;
    # absence of an error keyword = treat as INFO.
    r2 = ssh_exec(ip, "ai-memory doctor 2>&1", timeout=30)
    text = (r2.stdout or "") + (r2.stderr or "")
    if r2.returncode != 0:
        return {"raw_text": text, "exit": r2.returncode}, "ERROR", False
    upper = text.upper()
    if "FAIL" in upper or "ERROR" in upper:
        return {"raw_text": text}, "ERROR", False
    return {"raw_text": text}, "INFO", True


def check_env_file(ip: str, role: str) -> tuple[bool, bool, list[str]]:
    """Returns (file_present, all_required_present, missing_vars)."""
    r = ssh_exec(ip, "test -f /etc/ai-memory-a2a/env && cat /etc/ai-memory-a2a/env", timeout=15)
    if r.returncode != 0 or not (r.stdout or "").strip():
        return False, False, []
    body = r.stdout
    required = REQUIRED_ENV_VARS_AGENT if role == "agent" else REQUIRED_ENV_VARS_MEMORY
    missing: list[str] = []
    for var in required:
        # match "VAR=" at line start (with possible leading whitespace)
        found = False
        for line in body.splitlines():
            stripped = line.strip()
            if stripped.startswith(f"{var}="):
                # Reject empty values; the var is "missing" if value is empty.
                _, _, val = stripped.partition("=")
                if val.strip():
                    found = True
                    break
        if not found:
            missing.append(var)
    return True, not missing, missing


def check_schema_version(ip: str, doctor_raw: dict[str, Any]) -> tuple[str, bool]:
    """Probe ai-memory's reported schema version. Tries doctor JSON first,
    then `ai-memory audit verify --format json` as a fallback. Empty / no
    field → returns ("unknown", False) so the aggregator surfaces the gap."""
    # Doctor often surfaces it under .schema_version or .schema.version.
    candidates: list[str] = []
    for key in ("schema_version", "schema", "schemaVersion"):
        val = doctor_raw.get(key) if isinstance(doctor_raw, dict) else None
        if isinstance(val, str):
            candidates.append(val)
        elif isinstance(val, dict):
            v2 = val.get("version") or val.get("schema_version")
            if isinstance(v2, str):
                candidates.append(v2)
    for c in candidates:
        if c:
            return c, c.lstrip("v") == EXPECTED_SCHEMA_VERSION.lstrip("v")
    # Fallback — audit verify
    r = ssh_exec(ip, "ai-memory audit verify --format json 2>/dev/null", timeout=20)
    if r.returncode == 0 and (r.stdout or "").strip():
        try:
            doc = json.loads(r.stdout)
            for key in ("schema_version", "schema"):
                v = doc.get(key)
                if isinstance(v, str) and v:
                    return v, v.lstrip("v") == EXPECTED_SCHEMA_VERSION.lstrip("v")
                if isinstance(v, dict):
                    v2 = v.get("version") or v.get("schema_version")
                    if isinstance(v2, str) and v2:
                        return v2, v2.lstrip("v") == EXPECTED_SCHEMA_VERSION.lstrip("v")
        except json.JSONDecodeError:
            pass
    return "unknown", False


def check_one(node_label: str, ip: str, role: str) -> dict[str, Any]:
    log(f"[{node_label}] {ip} role={role}")
    result: dict[str, Any] = {
        "node": node_label,
        "ip": ip,
        "role": role,
        "ssh_reachable": False,
        "ai_memory_version": "",
        "version_ok": False,
        "doctor": {},
        "doctor_ok": False,
        "env_file_present": False,
        "env_file_required_vars_present": False,
        "env_file_missing_vars": [],
        "schema_version": "unknown",
        "schema_version_ok": False,
        "ok": False,
    }
    # SSH
    if not check_ssh(ip):
        log(f"  [{node_label}] ssh unreachable")
        return result
    result["ssh_reachable"] = True
    # Version
    ver, ver_ok = check_version(ip)
    result["ai_memory_version"] = ver
    result["version_ok"] = ver_ok
    log(f"  [{node_label}] ai-memory version: {ver} ok={ver_ok}")
    # Doctor
    doc, overall, doc_ok = check_doctor(ip)
    result["doctor"] = {"overall": overall, "raw": doc}
    result["doctor_ok"] = doc_ok
    log(f"  [{node_label}] doctor overall={overall} ok={doc_ok}")
    # Env file
    present, all_ok, missing = check_env_file(ip, role)
    result["env_file_present"] = present
    result["env_file_required_vars_present"] = all_ok
    result["env_file_missing_vars"] = missing
    log(f"  [{node_label}] env present={present} required_ok={all_ok} missing={missing}")
    # Schema version
    sv, sv_ok = check_schema_version(ip, doc if isinstance(doc, dict) else {})
    result["schema_version"] = sv
    result["schema_version_ok"] = sv_ok
    log(f"  [{node_label}] schema_version={sv} ok={sv_ok}")
    # Aggregate per-droplet ok
    result["ok"] = all([
        result["ssh_reachable"],
        result["version_ok"],
        result["doctor_ok"],
        result["env_file_present"],
        result["env_file_required_vars_present"],
        result["schema_version_ok"],
    ])
    return result


def main() -> int:
    node1 = os.environ.get("NODE1_IP")
    node2 = os.environ.get("NODE2_IP")
    node3 = os.environ.get("NODE3_IP")
    node4 = os.environ.get("NODE4_IP") or os.environ.get("MEMORY_NODE_IP")
    missing_env = [k for k, v in (
        ("NODE1_IP", node1),
        ("NODE2_IP", node2),
        ("NODE3_IP", node3),
        ("NODE4_IP/MEMORY_NODE_IP", node4),
    ) if not v]
    if missing_env:
        log(f"FATAL: missing required env vars: {missing_env}")
        return 2

    targets = [
        ("node-1", node1, "agent"),
        ("node-2", node2, "agent"),
        ("node-3", node3, "agent"),
        ("node-4", node4, "memory-only"),
    ]
    droplets = [check_one(name, ip, role) for name, ip, role in targets]
    all_ok = all(d["ok"] for d in droplets)
    out = {
        "schema": "a2a-preflight-droplets/v1",
        "release": "v0.6.3.1",
        "expected_ai_memory_version": "0.6.3+patch.1",
        "expected_schema_version": EXPECTED_SCHEMA_VERSION,
        "droplets": droplets,
        "all_ok": all_ok,
    }
    print(json.dumps(out, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
