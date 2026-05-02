#!/usr/bin/env bash
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
#
# S26 — Audit tamper detection (EXPECTED GREEN)
# See contract.md.

set -euo pipefail

NODE_A="${A2A_NODE_A:-${NODE1_IP:-}}"
TLS_MODE="${TLS_MODE:-off}"

if [ -z "$NODE_A" ]; then
  cat <<'EOF'
{"scenario":"S26","pass":false,"expected_verdict":"GREEN","actual_verdict":"UNKNOWN","outputs":{},"reasons":["A2A_NODE_A / NODE1_IP not set in environment"]}
EOF
  exit 0
fi

SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=4)

WORK="$(mktemp -d -t s26.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

stderr() { printf '[s26] %s\n' "$*" >&2; }

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
BAK="\${AUDIT_FILE}.s26.bak"

verify_audit() {
  local rc=0
  local raw cleaned
  raw=\$(timeout 30 ai-memory audit verify --format json 2>/dev/null) || rc=\$?
  if [ -z "\$raw" ]; then
    printf '{"verify_rc":%d,"verify":{"error":"empty-verify-output"}}' "\$rc"
    return 0
  fi
  if printf '%s' "\$raw" | jq -e . >/dev/null 2>&1; then
    cleaned="\$raw"
  else
    cleaned=\$(printf '%s' "\$raw" | awk 'f{print} /^{/{f=1; print}' | head -200)
    if [ -z "\$cleaned" ] || ! printf '%s' "\$cleaned" | jq -e . >/dev/null 2>&1; then
      cleaned=\$(printf '{"error":"unparseable","raw":%s}' "\$(printf '%s' "\$raw" | jq -Rs .)")
    fi
  fi
  jq -n --argjson rc "\$rc" --argjson v "\$cleaned" '{verify_rc:\$rc, verify:\$v}'
}

if [ ! -f "\$AUDIT_FILE" ] || [ ! -s "\$AUDIT_FILE" ]; then
  uuid=\$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "s26-seed-\$RANDOM-\$\$")
  body=\$(jq -nc --arg u "\$uuid" \\
    '{tier:"mid", namespace:"test/S26/seed", title:"s26-seed", content:\$u, priority:5, confidence:1.0, source:"api", metadata:{agent_id:"ai:s26-driver", probe:"S26-seed"}}')
  \$CURL -X POST "\$BASE/api/v1/memories" \\
    -H 'X-Agent-Id: ai:s26-driver' \\
    -H 'Content-Type: application/json' \\
    -d "\$body" >/dev/null 2>&1 || emit_err "seed-write-failed"
  sleep 1
fi

BEFORE_JSON=\$(verify_audit)
BEFORE_LINE_COUNT=0
if [ -f "\$AUDIT_FILE" ]; then
  BEFORE_LINE_COUNT=\$(wc -l < "\$AUDIT_FILE" 2>/dev/null || echo 0)
fi

BACKUP_OK=true
if cp -p "\$AUDIT_FILE" "\$BAK" 2>/dev/null; then
  :
else
  BACKUP_OK=false
  emit_err "backup-failed"
fi

CHATTR_REMOVED=false
if chattr -a "\$AUDIT_FILE" 2>/dev/null; then
  CHATTR_REMOVED=true
fi

TAMPER_RC=0
printf X | dd of="\$AUDIT_FILE" bs=1 count=1 conv=notrunc 2>/dev/null || TAMPER_RC=\$?
if [ \$TAMPER_RC -ne 0 ]; then
  emit_err "tamper-write-failed-rc-\$TAMPER_RC"
fi

AFTER_JSON=\$(verify_audit)

RESTORE_OK=true
if [ "\$BACKUP_OK" = "true" ] && [ -f "\$BAK" ]; then
  if cp -p "\$BAK" "\$AUDIT_FILE" 2>/dev/null; then
    rm -f "\$BAK" 2>/dev/null || true
  else
    RESTORE_OK=false
    emit_err "restore-cp-failed"
  fi
else
  RESTORE_OK=false
fi

RESTORED_JSON=\$(verify_audit)
RESTORE_LINE_COUNT=0
if [ -f "\$AUDIT_FILE" ]; then
  RESTORE_LINE_COUNT=\$(wc -l < "\$AUDIT_FILE" 2>/dev/null || echo 0)
fi

if [ "\$CHATTR_REMOVED" = "true" ]; then
  chattr +a "\$AUDIT_FILE" 2>/dev/null || true
fi

errs_json=\$(printf '%s\\n' "\${ERRS[@]:-}" | jq -R . | jq -s 'map(select(length>0))')

jq -n \\
  --argjson before "\$BEFORE_JSON" \\
  --argjson after "\$AFTER_JSON" \\
  --argjson restored "\$RESTORED_JSON" \\
  --argjson before_lines "\$BEFORE_LINE_COUNT" \\
  --argjson restore_lines "\$RESTORE_LINE_COUNT" \\
  --argjson backup_ok "\$([ \$BACKUP_OK = true ] && echo true || echo false)" \\
  --argjson restore_ok "\$([ \$RESTORE_OK = true ] && echo true || echo false)" \\
  --argjson chattr_removed "\$([ \$CHATTR_REMOVED = true ] && echo true || echo false)" \\
  --argjson errs "\$errs_json" \\
  '{
    before: \$before, after: \$after, restored: \$restored,
    before_line_count: \$before_lines, restore_line_count: \$restore_lines,
    backup_ok: \$backup_ok, restore_ok: \$restore_ok, chattr_removed: \$chattr_removed,
    errors: \$errs
  }'
REMOTE
}

stderr "begin S26 probe on node-1 (${NODE_A})"
PROBE_SCRIPT="$(remote_probe_script)"
out_file="$WORK/node-1.json"

if ! ssh "${SSH_OPTS[@]}" "root@${NODE_A}" "bash -s" <<<"$PROBE_SCRIPT" >"$out_file" 2> >(sed "s/^/[s26 ${NODE_A} stderr] /" >&2); then
  rc=$?
  stderr "  ssh-probe failed rc=${rc}"
  cat <<EOF
{"scenario":"S26","pass":false,"expected_verdict":"GREEN","actual_verdict":"UNKNOWN","outputs":{},"reasons":["ssh-probe-failed-rc-${rc}"]}
EOF
  exit 0
fi

if ! jq -e . "$out_file" >/dev/null 2>&1; then
  stderr "unparseable envelope from node-1"
  cat <<EOF
{"scenario":"S26","pass":false,"expected_verdict":"GREEN","actual_verdict":"UNKNOWN","outputs":{},"reasons":["unparseable-envelope-from-node-1"]}
EOF
  exit 0
fi

before_rc=$(jq -r '.before.verify_rc' "$out_file")
before_ok=$(jq -r '.before.verify | (.ok // .verified // (.chain_ok // false))' "$out_file")
before_head=$(jq -r '.before.verify | (.head_hash // .chain_head // .head // "")' "$out_file")
before_lines_field=$(jq -r '.before_line_count' "$out_file")

after_rc=$(jq -r '.after.verify_rc' "$out_file")
after_ok=$(jq -r '.after.verify | (.ok // .verified // (.chain_ok // false))' "$out_file")
after_tamper=$(jq -r '.after.verify | (.tamper_detected // .chain_broken // .failed // false) | tostring' "$out_file")
after_err_field=$(jq -r '.after.verify | (.error // .failed_line // .message // "")' "$out_file")

restored_rc=$(jq -r '.restored.verify_rc' "$out_file")
restored_ok=$(jq -r '.restored.verify | (.ok // .verified // (.chain_ok // false))' "$out_file")
restored_head=$(jq -r '.restored.verify | (.head_hash // .chain_head // .head // "")' "$out_file")
restore_lines_field=$(jq -r '.restore_line_count' "$out_file")

backup_ok=$(jq -r '.backup_ok' "$out_file")
restore_ok=$(jq -r '.restore_ok' "$out_file")
chattr_removed=$(jq -r '.chattr_removed' "$out_file")
errors=$(jq -c '.errors // []' "$out_file")

stderr "  before: rc=${before_rc} ok=${before_ok} head=${before_head:0:16}… lines=${before_lines_field}"
stderr "  after:  rc=${after_rc} ok=${after_ok} tamper=${after_tamper} err='${after_err_field:0:80}'"
stderr "  restored: rc=${restored_rc} ok=${restored_ok} head=${restored_head:0:16}… lines=${restore_lines_field}"

tamper_detection_fired=false
if [ "$after_rc" != "0" ] && [ "$after_ok" != "true" ]; then
  tamper_detection_fired=true
fi

restore_succeeded=false
if [ "$restored_rc" = "0" ] && [ "$restored_ok" = "true" ] && [ "$restore_ok" = "true" ]; then
  restore_succeeded=true
fi

reasons=()
if [ "$tamper_detection_fired" != "true" ]; then
  reasons+=("tamper detection did not fire: after rc=${after_rc} ok=${after_ok} (expected rc!=0 + ok=false)")
fi
if [ "$restore_succeeded" != "true" ]; then
  reasons+=("restore did not re-verify clean: rc=${restored_rc} ok=${restored_ok} (expected rc=0 + ok=true; restore_ok=${restore_ok})")
fi
if [ "$backup_ok" != "true" ]; then
  reasons+=("backup of audit.jsonl failed before tamper — test may not be reliable")
fi

if [ "$tamper_detection_fired" = "true" ] && [ "$restore_succeeded" = "true" ]; then
  actual_verdict="GREEN"
  pass="true"
else
  actual_verdict="RED"
  pass="false"
fi

before_obj=$(jq -nc \
  --argjson rc "$before_rc" \
  --arg ok "$before_ok" \
  --arg head "$before_head" \
  --argjson lines "$before_lines_field" \
  '{rc: $rc, ok: ($ok == "true"), head_hash: $head, line_count: $lines}')

after_obj=$(jq -nc \
  --argjson rc "$after_rc" \
  --arg ok "$after_ok" \
  --arg tamper "$after_tamper" \
  --arg err "$after_err_field" \
  '{rc: $rc, ok: ($ok == "true"), tamper_detected: ($tamper == "true"), error_field: $err}')

restored_obj=$(jq -nc \
  --argjson rc "$restored_rc" \
  --arg ok "$restored_ok" \
  --arg head "$restored_head" \
  --argjson lines "$restore_lines_field" \
  '{rc: $rc, ok: ($ok == "true"), head_hash: $head, line_count: $lines}')

reasons_json=$(printf '%s\n' "${reasons[@]:-}" | jq -R . | jq -s 'map(select(length>0))')

jq -n \
  --arg scenario "S26" \
  --arg expected_verdict "GREEN" \
  --arg actual_verdict "$actual_verdict" \
  --argjson pass "$pass" \
  --arg expected_green_reason "byte-level mutation of audit.jsonl must trigger ai-memory audit verify rc!=0 + ok=false; restore from backup must re-verify clean" \
  --arg run_id "$RUN_ID" \
  --argjson before_tamper "$before_obj" \
  --argjson after_tamper "$after_obj" \
  --argjson after_restore "$restored_obj" \
  --argjson tamper_detection_fired "$tamper_detection_fired" \
  --argjson restore_succeeded "$restore_succeeded" \
  --argjson chattr_removed "$chattr_removed" \
  --argjson backup_ok "$backup_ok" \
  --argjson errors "$errors" \
  --argjson reasons "$reasons_json" \
  '{
    scenario: $scenario,
    pass: $pass,
    expected_verdict: $expected_verdict,
    actual_verdict: $actual_verdict,
    expected_green_reason: $expected_green_reason,
    run_id: $run_id,
    outputs: {
      before_tamper: $before_tamper,
      after_tamper: $after_tamper,
      after_restore: $after_restore,
      tamper_detection_fired: $tamper_detection_fired,
      restore_succeeded: $restore_succeeded,
      chattr_removed_for_tamper: $chattr_removed,
      backup_ok: $backup_ok,
      remote_errors: $errors
    },
    reasons: $reasons
  }'
