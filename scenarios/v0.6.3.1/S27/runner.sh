#!/usr/bin/env bash
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
#
# S27 — Audit append-only enforcement (EXPECTED GREEN)
# See contract.md.

set -euo pipefail

NODE_A="${A2A_NODE_A:-${NODE1_IP:-}}"
TLS_MODE="${TLS_MODE:-off}"

if [ -z "$NODE_A" ]; then
  cat <<'EOF'
{"scenario":"S27","pass":false,"expected_verdict":"GREEN","actual_verdict":"UNKNOWN","outputs":{},"reasons":["A2A_NODE_A / NODE1_IP not set in environment"]}
EOF
  exit 0
fi

SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=4)

WORK="$(mktemp -d -t s27.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

stderr() { printf '[s27] %s\n' "$*" >&2; }

remote_curl_prefix() {
  if [ "$TLS_MODE" = "off" ]; then
    printf 'curl -sS'
  else
    printf 'curl -sS --cacert /etc/ai-memory-a2a/tls/ca.pem --resolve localhost:9077:127.0.0.1'
    if [ "$TLS_MODE" = "mtls" ]; then
      printf ' --cert /etc/ai-memory-a2a/tls/client.pem --key /etc/ai-memory-a2a/tls/client.key'
    fi
  fi
}

remote_base_url() {
  if [ "$TLS_MODE" = "off" ]; then printf 'http://127.0.0.1:9077'; else printf 'https://localhost:9077'; fi
}

CURL=$(remote_curl_prefix)
BASE=$(remote_base_url)
RUN_ID=$(date -u +%Y%m%d%H%M%S)-$$

remote_probe_script() {
  cat <<REMOTE
set -u
ERRS=()
emit_err() { ERRS+=("\$1"); }

CURL="${CURL}"
BASE="${BASE}"
AUDIT_FILE=/var/log/ai-memory/audit.jsonl

if [ ! -f "\$AUDIT_FILE" ] || [ ! -s "\$AUDIT_FILE" ]; then
  uuid=\$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "s27-seed-\$RANDOM-\$\$")
  body=\$(jq -nc --arg u "\$uuid" \\
    '{tier:"mid", namespace:"test/S27/seed", title:"s27-seed", content:\$u, priority:5, confidence:1.0, source:"api", metadata:{agent_id:"ai:s27-driver", probe:"S27-seed"}}')
  \$CURL -X POST "\$BASE/api/v1/memories" \\
    -H 'X-Agent-Id: ai:s27-driver' \\
    -H 'Content-Type: application/json' \\
    -d "\$body" >/dev/null 2>&1 || emit_err "seed-write-failed"
  sleep 1
fi

chattr +a "\$AUDIT_FILE" 2>/dev/null || true

LSATTR_OUT=\$(lsattr "\$AUDIT_FILE" 2>&1 || true)
LSATTR_FLAGS=""
CHATTR_SUPPORTED=false
if printf '%s' "\$LSATTR_OUT" | grep -q "Operation not supported\\|not supported on this filesystem\\|Inappropriate ioctl"; then
  CHATTR_SUPPORTED=false
elif printf '%s' "\$LSATTR_OUT" | grep -q "\$AUDIT_FILE"; then
  LSATTR_FLAGS=\$(printf '%s' "\$LSATTR_OUT" | awk '{print \$1; exit}')
  CHATTR_SUPPORTED=true
fi

LINES_BEFORE=\$(wc -l < "\$AUDIT_FILE" 2>/dev/null || echo 0)

NONROOT_BLOCKED=false
NONROOT_OUT=""
if id nobody >/dev/null 2>&1; then
  NONROOT_OUT=\$(su nobody -s /bin/sh -c "echo X > '\$AUDIT_FILE'" 2>&1 || true)
  FIRST_BYTE=\$(head -c 1 "\$AUDIT_FILE" 2>/dev/null || true)
  if printf '%s' "\$NONROOT_OUT" | grep -qi "permission denied\\|operation not permitted\\|cannot create"; then
    NONROOT_BLOCKED=true
  elif [ "\$FIRST_BYTE" = "{" ]; then
    NONROOT_BLOCKED=true
  else
    NONROOT_BLOCKED=false
    emit_err "nonroot-write-not-blocked"
  fi
else
  NONROOT_OUT="nobody-user-not-present"
fi

ROOT_DD_BLOCKED=false
ROOT_DD_OUT=\$(dd if=/dev/urandom of="\$AUDIT_FILE" bs=1 count=1 conv=notrunc 2>&1 || true)
if printf '%s' "\$ROOT_DD_OUT" | grep -qi "operation not permitted\\|permission denied\\|cannot open"; then
  ROOT_DD_BLOCKED=true
fi
FIRST_BYTE=\$(head -c 1 "\$AUDIT_FILE" 2>/dev/null || true)
if [ "\$FIRST_BYTE" = "{" ] && [ "\$ROOT_DD_BLOCKED" = "false" ]; then
  ROOT_DD_BLOCKED=true
fi

ROOT_TRUNC_BLOCKED=false
ROOT_TRUNC_OUT=\$(truncate -s 0 "\$AUDIT_FILE" 2>&1 || true)
if printf '%s' "\$ROOT_TRUNC_OUT" | grep -qi "operation not permitted\\|permission denied\\|cannot"; then
  ROOT_TRUNC_BLOCKED=true
fi
LINES_AFTER_TRUNC=\$(wc -l < "\$AUDIT_FILE" 2>/dev/null || echo 0)
if [ "\$LINES_AFTER_TRUNC" -ge "\$LINES_BEFORE" ] 2>/dev/null && [ "\$ROOT_TRUNC_BLOCKED" = "false" ]; then
  ROOT_TRUNC_BLOCKED=true
fi

APPEND_WORKED=false
uuid=\$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "s27-app-\$RANDOM-\$\$")
body=\$(jq -nc --arg u "\$uuid" \\
  '{tier:"mid", namespace:"test/S27/append", title:"s27-append-probe", content:\$u, priority:5, confidence:1.0, source:"api", metadata:{agent_id:"ai:s27-driver", probe:"S27-append"}}')
\$CURL -X POST "\$BASE/api/v1/memories" \\
  -H 'X-Agent-Id: ai:s27-driver' \\
  -H 'Content-Type: application/json' \\
  -d "\$body" >/dev/null 2>&1 || emit_err "append-http-write-failed"
sleep 1
LINES_AFTER_APPEND=\$(wc -l < "\$AUDIT_FILE" 2>/dev/null || echo 0)
if [ "\$LINES_AFTER_APPEND" -gt "\$LINES_BEFORE" ] 2>/dev/null; then
  APPEND_WORKED=true
fi

errs_json=\$(printf '%s\\n' "\${ERRS[@]:-}" | jq -R . | jq -s 'map(select(length>0))')

jq -n \\
  --arg lsattr_flags "\$LSATTR_FLAGS" \\
  --arg lsattr_raw "\$LSATTR_OUT" \\
  --argjson chattr_supported "\$([ \$CHATTR_SUPPORTED = true ] && echo true || echo false)" \\
  --argjson nonroot_blocked "\$([ \$NONROOT_BLOCKED = true ] && echo true || echo false)" \\
  --arg nonroot_out "\$NONROOT_OUT" \\
  --argjson root_dd_blocked "\$([ \$ROOT_DD_BLOCKED = true ] && echo true || echo false)" \\
  --arg root_dd_out "\$ROOT_DD_OUT" \\
  --argjson root_trunc_blocked "\$([ \$ROOT_TRUNC_BLOCKED = true ] && echo true || echo false)" \\
  --arg root_trunc_out "\$ROOT_TRUNC_OUT" \\
  --argjson append_worked "\$([ \$APPEND_WORKED = true ] && echo true || echo false)" \\
  --argjson lines_before "\$LINES_BEFORE" \\
  --argjson lines_after_append "\$LINES_AFTER_APPEND" \\
  --argjson errs "\$errs_json" \\
  '{
    lsattr_flags: \$lsattr_flags,
    lsattr_raw: \$lsattr_raw,
    chattr_supported: \$chattr_supported,
    nonroot_write_blocked: \$nonroot_blocked,
    nonroot_write_output: \$nonroot_out,
    root_dd_blocked: \$root_dd_blocked,
    root_dd_output: \$root_dd_out,
    root_truncate_blocked: \$root_trunc_blocked,
    root_truncate_output: \$root_trunc_out,
    append_legitimate_worked: \$append_worked,
    lines_before: \$lines_before,
    lines_after_append: \$lines_after_append,
    errors: \$errs
  }'
REMOTE
}

stderr "begin S27 probe on node-1 (${NODE_A})"
PROBE_SCRIPT="$(remote_probe_script)"
out_file="$WORK/node-1.json"

if ! ssh "${SSH_OPTS[@]}" "root@${NODE_A}" "bash -s" <<<"$PROBE_SCRIPT" >"$out_file" 2> >(sed "s/^/[s27 ${NODE_A} stderr] /" >&2); then
  rc=$?
  stderr "  ssh-probe failed rc=${rc}"
  cat <<EOF
{"scenario":"S27","pass":false,"expected_verdict":"GREEN","actual_verdict":"UNKNOWN","outputs":{},"reasons":["ssh-probe-failed-rc-${rc}"]}
EOF
  exit 0
fi

if ! jq -e . "$out_file" >/dev/null 2>&1; then
  stderr "unparseable envelope from node-1"
  cat <<EOF
{"scenario":"S27","pass":false,"expected_verdict":"GREEN","actual_verdict":"UNKNOWN","outputs":{},"reasons":["unparseable-envelope-from-node-1"]}
EOF
  exit 0
fi

flags=$(jq -r '.lsattr_flags' "$out_file")
chattr_supported=$(jq -r '.chattr_supported' "$out_file")
nonroot_blocked=$(jq -r '.nonroot_write_blocked' "$out_file")
root_dd_blocked=$(jq -r '.root_dd_blocked' "$out_file")
root_trunc_blocked=$(jq -r '.root_truncate_blocked' "$out_file")
append_worked=$(jq -r '.append_legitimate_worked' "$out_file")
lines_before=$(jq -r '.lines_before' "$out_file")
lines_after=$(jq -r '.lines_after_append' "$out_file")

stderr "  lsattr_flags='${flags}' chattr_supported=${chattr_supported}"
stderr "  nonroot_blocked=${nonroot_blocked} root_dd_blocked=${root_dd_blocked} root_trunc_blocked=${root_trunc_blocked}"
stderr "  append_worked=${append_worked} lines: ${lines_before} -> ${lines_after}"

reasons=()

if [ "$append_worked" != "true" ]; then
  reasons+=("legitimate HTTP append did not increment audit line count (lines_before=${lines_before} lines_after=${lines_after})")
fi

if [ "$chattr_supported" = "true" ]; then
  if [ "$nonroot_blocked" != "true" ]; then
    reasons+=("non-root overwrite was NOT blocked despite chattr +a — kernel append-only enforcement broken")
  fi
  if [ "$root_dd_blocked" != "true" ]; then
    reasons+=("root non-append dd was NOT blocked despite chattr +a — chattr applied as no-op")
  fi
  if [ "$root_trunc_blocked" != "true" ]; then
    reasons+=("root truncate was NOT blocked despite chattr +a — append-only flag not enforced for truncate")
  fi
  if ! printf '%s' "$flags" | grep -q 'a'; then
    reasons+=("lsattr flag string '${flags}' does not include 'a' — setup_node.sh's chattr +a watcher did not apply on this provision")
  fi
else
  reasons+=("filesystem does not support chattr +a — append-only enforcement degraded to chain-only (S26 still detects, but tamper is not prevented at write time)")
fi

if [ "$chattr_supported" = "true" ]; then
  if [ "$append_worked" = "true" ] && \
     [ "$nonroot_blocked" = "true" ] && \
     [ "$root_dd_blocked" = "true" ] && \
     [ "$root_trunc_blocked" = "true" ] && \
     printf '%s' "$flags" | grep -q 'a'; then
    actual_verdict="GREEN"
    pass="true"
  else
    actual_verdict="RED"
    pass="false"
  fi
else
  if [ "$append_worked" = "true" ]; then
    actual_verdict="GREEN"
    pass="true"
  else
    actual_verdict="RED"
    pass="false"
  fi
fi

reasons_json=$(printf '%s\n' "${reasons[@]:-}" | jq -R . | jq -s 'map(select(length>0))')

jq -n \
  --arg scenario "S27" \
  --arg expected_verdict "GREEN" \
  --arg actual_verdict "$actual_verdict" \
  --argjson pass "$pass" \
  --arg expected_green_reason "OS append-only flag must block non-append writes from root + non-root while permitting legitimate audit-hook appends" \
  --arg run_id "$RUN_ID" \
  --arg lsattr_flags "$flags" \
  --argjson chattr_supported "$chattr_supported" \
  --argjson nonroot_write_blocked "$nonroot_blocked" \
  --argjson root_dd_blocked "$root_dd_blocked" \
  --argjson root_truncate_blocked "$root_trunc_blocked" \
  --argjson append_legitimate_worked "$append_worked" \
  --argjson lines_before "$lines_before" \
  --argjson lines_after_append "$lines_after" \
  --argjson reasons "$reasons_json" \
  '{
    scenario: $scenario,
    pass: $pass,
    expected_verdict: $expected_verdict,
    actual_verdict: $actual_verdict,
    expected_green_reason: $expected_green_reason,
    run_id: $run_id,
    outputs: {
      lsattr_flags: $lsattr_flags,
      chattr_supported: $chattr_supported,
      nonroot_write_blocked: $nonroot_write_blocked,
      root_dd_blocked: $root_dd_blocked,
      root_truncate_blocked: $root_truncate_blocked,
      append_legitimate_worked: $append_legitimate_worked,
      lines_before: $lines_before,
      lines_after_append: $lines_after_append
    },
    reasons: $reasons
  }'
