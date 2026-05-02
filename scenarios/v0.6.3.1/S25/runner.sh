#!/usr/bin/env bash
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
#
# S25 — Audit hash-chain integrity over a populated log (EXPECTED GREEN)
# See contract.md.
#
# For each of the 4 nodes:
#   1. ssh in, capture pre-state line count of /var/log/ai-memory/audit.jsonl
#      (informational; we don't depend on it).
#   2. Drive 25 HTTP writes via POST /api/v1/memories with synthetic content.
#      Each write hits the local ai-memory serve on 127.0.0.1:9077.
#   3. Run `ai-memory audit verify --format json`. Capture rc + parsed JSON
#      (ok, line_count, head_hash).
# Pass = every node satisfies (rc=0 AND ok=true AND line_count>=25 AND
# head_hash non-empty). Total 100 writes across the mesh.
#
# Output: standard scenario JSON on stdout, harness-shape:
#   {"scenario":"S25","pass":<bool>,"expected_verdict":"GREEN",
#    "actual_verdict":"<GREEN|RED>",
#    "outputs":{"per_node_audit":{...}, "writes_per_node":25, "total_writes":100},
#    "reasons":[...]}.

set -euo pipefail

NODE_A="${A2A_NODE_A:-${NODE1_IP:-}}"
NODE_B="${A2A_NODE_B:-${NODE2_IP:-}}"
NODE_C="${A2A_NODE_C:-${NODE3_IP:-}}"
NODE_D="${A2A_NODE_D:-${NODE4_IP:-${MEMORY_NODE_IP:-}}}"
TLS_MODE="${TLS_MODE:-off}"

if [ -z "$NODE_A" ] || [ -z "$NODE_B" ] || [ -z "$NODE_C" ] || [ -z "$NODE_D" ]; then
  cat <<'EOF'
{"scenario":"S25","pass":false,"expected_verdict":"GREEN","actual_verdict":"UNKNOWN","outputs":{},"reasons":["one or more node IPs missing from environment (A2A_NODE_A..D / NODE1_IP..NODE4_IP)"]}
EOF
  exit 0
fi

NODES=("node-1:$NODE_A" "node-2:$NODE_B" "node-3:$NODE_C" "node-4:$NODE_D")
WRITES_PER_NODE="${S25_WRITES_PER_NODE:-25}"

SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=4)

WORK="$(mktemp -d -t s25.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

stderr() { printf '[s25] %s\n' "$*" >&2; }

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
NS_PREFIX="test/S25/${RUN_ID}"

declare -A AUDIT_RC
declare -A AUDIT_OK
declare -A AUDIT_LINES
declare -A AUDIT_HEAD
declare -A NODE_REASONS

remote_driver_script() {
  local writes="$1"
  local ns="$2"
  cat <<REMOTE
set -u
WRITES=${writes}
NS="${ns}"
CURL="${CURL}"
BASE="${BASE}"

ERRS=()
emit_err() { ERRS+=("\$1"); }

AUDIT_FILE=/var/log/ai-memory/audit.jsonl
PRE_LINES=0
if [ -f "\$AUDIT_FILE" ]; then
  PRE_LINES=\$(wc -l < "\$AUDIT_FILE" 2>/dev/null || echo 0)
fi

WROTE_OK=0
WROTE_FAIL=0
for i in \$(seq 1 \$WRITES); do
  uuid=\$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "s25-\$RANDOM-\$i-\$\$")
  body=\$(jq -nc \\
    --arg ns "\$NS" \\
    --arg title "s25-\${i}" \\
    --arg content "\$uuid" \\
    --arg agent "ai:s25-driver" \\
    --arg probe "S25" \\
    '{
      tier: "mid", namespace: \$ns, title: \$title, content: \$content,
      priority: 5, confidence: 1.0, source: "api",
      metadata: {agent_id: \$agent, probe: \$probe}
    }')
  rc=0
  resp=\$(\$CURL -X POST "\$BASE/api/v1/memories" \\
    -H 'X-Agent-Id: ai:s25-driver' \\
    -H 'Content-Type: application/json' \\
    -d "\$body" 2>/dev/null) || rc=\$?
  if [ \$rc -ne 0 ]; then
    WROTE_FAIL=\$((WROTE_FAIL + 1))
  elif printf '%s' "\$resp" | jq -e '.id // .memory_id // .uuid // empty' >/dev/null 2>&1; then
    WROTE_OK=\$((WROTE_OK + 1))
  else
    if printf '%s' "\$resp" | jq -e 'has("error") | not' >/dev/null 2>&1; then
      WROTE_OK=\$((WROTE_OK + 1))
    else
      WROTE_FAIL=\$((WROTE_FAIL + 1))
    fi
  fi
done

sleep 1

POST_LINES=0
if [ -f "\$AUDIT_FILE" ]; then
  POST_LINES=\$(wc -l < "\$AUDIT_FILE" 2>/dev/null || echo 0)
fi

VERIFY_RC=0
VERIFY_RAW=\$(timeout 30 ai-memory audit verify --format json 2>/dev/null) || VERIFY_RC=\$?
if [ -z "\$VERIFY_RAW" ]; then
  VERIFY_JSON='{"error":"empty-verify-output"}'
elif printf '%s' "\$VERIFY_RAW" | jq -e . >/dev/null 2>&1; then
  VERIFY_JSON="\$VERIFY_RAW"
else
  cleaned=\$(printf '%s' "\$VERIFY_RAW" | awk 'f{print} /^{/{f=1; print}' | head -200)
  if [ -n "\$cleaned" ] && printf '%s' "\$cleaned" | jq -e . >/dev/null 2>&1; then
    VERIFY_JSON="\$cleaned"
  else
    VERIFY_JSON=\$(printf '{"error":"unparseable-verify-output","raw":%s}' "\$(printf '%s' "\$VERIFY_RAW" | jq -Rs .)")
  fi
fi

errs_json=\$(printf '%s\\n' "\${ERRS[@]:-}" | jq -R . | jq -s 'map(select(length>0))')

jq -n \\
  --argjson pre "\$PRE_LINES" \\
  --argjson post "\$POST_LINES" \\
  --argjson wrote_ok "\$WROTE_OK" \\
  --argjson wrote_fail "\$WROTE_FAIL" \\
  --argjson rc "\$VERIFY_RC" \\
  --argjson v "\$VERIFY_JSON" \\
  --argjson errs "\$errs_json" \\
  '{
    pre_lines: \$pre,
    post_lines: \$post,
    wrote_ok: \$wrote_ok,
    wrote_fail: \$wrote_fail,
    verify_rc: \$rc,
    verify: \$v,
    errors: \$errs
  }'
REMOTE
}

stderr "begin S25 probe across 4 nodes (writes_per_node=${WRITES_PER_NODE})"

for entry in "${NODES[@]}"; do
  name="${entry%%:*}"
  ip="${entry##*:}"
  out_file="$WORK/${name}.json"
  ns="${NS_PREFIX}/${name}"
  stderr "probing ${name} (${ip}) ns=${ns}"
  driver=$(remote_driver_script "$WRITES_PER_NODE" "$ns")
  if ! ssh "${SSH_OPTS[@]}" "root@${ip}" "bash -s" <<<"$driver" >"$out_file" 2> >(sed "s/^/[s25 ${ip} stderr] /" >&2); then
    rc=$?
    stderr "  ssh-driver failed on ${name} rc=${rc}"
    NODE_REASONS["$name"]="ssh-driver-failed-rc-${rc}"
    AUDIT_RC["$name"]=99
    AUDIT_OK["$name"]="false"
    AUDIT_LINES["$name"]=0
    AUDIT_HEAD["$name"]=""
    continue
  fi

  if ! jq -e . "$out_file" >/dev/null 2>&1; then
    stderr "  unparseable envelope from ${name}"
    NODE_REASONS["$name"]="unparseable-envelope"
    AUDIT_RC["$name"]=99
    AUDIT_OK["$name"]="false"
    AUDIT_LINES["$name"]=0
    AUDIT_HEAD["$name"]=""
    continue
  fi

  rc=$(jq -r '.verify_rc' "$out_file")
  ok=$(jq -r '.verify | if .error then "false" else (.ok // (if .verified == true then "true" else "false" end)) end' "$out_file")
  lines=$(jq -r '.verify | (.line_count // .lines // .total_lines // 0)' "$out_file")
  if [ -z "$lines" ] || [ "$lines" = "null" ]; then lines=0; fi
  head=$(jq -r '.verify | (.head_hash // .chain_head // .head // "")' "$out_file")
  if [ "$head" = "null" ]; then head=""; fi

  AUDIT_RC["$name"]="$rc"
  AUDIT_OK["$name"]="$ok"
  AUDIT_LINES["$name"]="$lines"
  AUDIT_HEAD["$name"]="$head"

  wrote_ok=$(jq -r '.wrote_ok' "$out_file")
  pre=$(jq -r '.pre_lines' "$out_file")
  post=$(jq -r '.post_lines' "$out_file")
  stderr "  ${name} writes_ok=${wrote_ok}/${WRITES_PER_NODE} pre_lines=${pre} post_lines=${post} verify_rc=${rc} ok=${ok} lines=${lines} head=${head:0:16}…"

  errs=$(jq -r '.errors // [] | join(",")' "$out_file" 2>/dev/null || true)
  if [ -n "$errs" ]; then
    NODE_REASONS["$name"]="$errs"
  fi
done

reasons=()
green_signals=0
red_signals=0
total=4

for entry in "${NODES[@]}"; do
  name="${entry%%:*}"
  rc="${AUDIT_RC[$name]:-99}"
  ok="${AUDIT_OK[$name]:-false}"
  lines="${AUDIT_LINES[$name]:-0}"
  head="${AUDIT_HEAD[$name]:-}"

  node_green=true
  if [ "$rc" != "0" ]; then
    node_green=false
    reasons+=("${name} verify rc=${rc} (expected 0)")
  fi
  if [ "$ok" != "true" ]; then
    node_green=false
    reasons+=("${name} verify ok=${ok} (expected true)")
  fi
  if [ "${lines:-0}" -lt "$WRITES_PER_NODE" ] 2>/dev/null; then
    node_green=false
    reasons+=("${name} line_count=${lines} (expected >=${WRITES_PER_NODE})")
  fi
  if [ -z "$head" ]; then
    node_green=false
    reasons+=("${name} head_hash empty (expected non-empty)")
  fi

  if [ "$node_green" = "true" ]; then
    green_signals=$((green_signals + 1))
  else
    red_signals=$((red_signals + 1))
  fi
done

if [ "$green_signals" = "$total" ]; then
  actual_verdict="GREEN"
elif [ "$red_signals" = "$total" ]; then
  actual_verdict="RED"
else
  actual_verdict="ASYMMETRIC"
  reasons+=("asymmetric: ${green_signals}/${total} nodes verified clean; ${red_signals}/${total} did not — substrate inconsistent across mesh")
fi

expected="GREEN"
if [ "$actual_verdict" = "$expected" ]; then
  pass="true"
else
  pass="false"
fi

per_node_obj='{}'
for entry in "${NODES[@]}"; do
  name="${entry%%:*}"
  per_node_obj=$(printf '%s' "$per_node_obj" | jq \
    --arg n "$name" \
    --argjson rc "${AUDIT_RC[$name]:-99}" \
    --arg ok "${AUDIT_OK[$name]:-false}" \
    --argjson lines "${AUDIT_LINES[$name]:-0}" \
    --arg head "${AUDIT_HEAD[$name]:-}" \
    '. + {($n): {rc: $rc, ok: ($ok == "true"), lines: $lines, head_hash: $head}}')
done

total_writes=$(( WRITES_PER_NODE * total ))
reasons_json=$(printf '%s\n' "${reasons[@]:-}" | jq -R . | jq -s 'map(select(length>0))')

jq -n \
  --arg scenario "S25" \
  --arg expected_verdict "$expected" \
  --arg actual_verdict "$actual_verdict" \
  --argjson pass "$pass" \
  --arg expected_green_reason "v0.6.3.1 audit substrate enabled; HTTP writes must produce a chained, verifiable trail" \
  --arg run_id "$RUN_ID" \
  --argjson per_node_audit "$per_node_obj" \
  --argjson writes_per_node "$WRITES_PER_NODE" \
  --argjson total_writes "$total_writes" \
  --argjson reasons "$reasons_json" \
  '{
    scenario: $scenario,
    pass: $pass,
    expected_verdict: $expected_verdict,
    actual_verdict: $actual_verdict,
    expected_green_reason: $expected_green_reason,
    run_id: $run_id,
    outputs: {
      per_node_audit: $per_node_audit,
      writes_per_node: $writes_per_node,
      total_writes: $total_writes
    },
    reasons: $reasons
  }'
