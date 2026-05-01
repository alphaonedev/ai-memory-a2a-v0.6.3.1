#!/usr/bin/env bash
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
#
# Phase 0 preflight — mTLS material + listener verification.
#
# When TLS_MODE=mtls, every droplet should have:
#   * /etc/ai-memory-a2a/tls/{ca,server,server.key,client,client.key}.pem
#   * `ai-memory serve` HTTPS listener up on :9077 reachable with the CA
#   * mTLS rejection of an anonymous (no client cert) request
#
# When TLS_MODE=tls, only the server cert chain is required and mTLS
# rejection is not asserted (a no-client-cert connection succeeds).
#
# When TLS_MODE=off, the script emits a JSON report with skipped=true
# and exits 0 — the aggregator treats this as a non-blocking pass for
# Phase 0.
#
# Inputs (env, public IPs of the 4 droplets):
#   NODE1_IP NODE2_IP NODE3_IP NODE4_IP (or MEMORY_NODE_IP)
#   TLS_MODE  (off | tls | mtls)
#
# Output:
#   stdout — single-line JSON. Schema:
#     {
#       "schema": "a2a-preflight-mtls/v1",
#       "tls_mode": "off|tls|mtls",
#       "skipped": bool,
#       "droplets": [
#         {
#           "node": "node-N",
#           "ip": "<public ip>",
#           "cert_files_present": bool,
#           "missing_cert_files": [...],
#           "https_listener_up": bool,
#           "mtls_rejects_anon": bool | null,   # null when tls_mode != mtls
#           "ok": bool
#         }, ...
#       ],
#       "all_ok": bool
#     }
#   exit 0 always (per a2a-harness convention; aggregator reads JSON)

set -u

SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ServerAliveInterval=5 -o BatchMode=yes)
TLS_MODE="${TLS_MODE:-off}"

log() { printf '[preflight-mtls %s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

REQUIRED_BASE=(ca.pem server.pem server.key)
REQUIRED_MTLS=(client.pem client.key)

ssh_exec() {
  # ssh_exec <ip> <cmd>
  local ip="$1"; shift
  ssh "${SSH_OPTS[@]}" "root@${ip}" "$@" 2>/dev/null
}

# json_string — emit a JSON-safe string literal (handles backslash + quote).
json_string() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

check_one_droplet() {
  local node="$1" ip="$2"
  local cert_files_present=true
  local missing="[]"
  local missing_list=()
  local https_up=false
  local mtls_rej_field='"mtls_rejects_anon": null'

  local req_files=("${REQUIRED_BASE[@]}")
  if [ "$TLS_MODE" = "mtls" ]; then
    req_files+=("${REQUIRED_MTLS[@]}")
  fi
  for f in "${req_files[@]}"; do
    if ! ssh_exec "$ip" "test -s /etc/ai-memory-a2a/tls/$f" >/dev/null 2>&1; then
      cert_files_present=false
      missing_list+=("$f")
    fi
  done
  if [ ${#missing_list[@]} -gt 0 ]; then
    missing="[$(printf '"%s",' "${missing_list[@]}" | sed 's/,$//')]"
  fi

  # HTTPS listener probe (loopback, with CA pinning + --resolve so SAN
  # lookup works against 127.0.0.1).
  local https_cmd
  if [ "$TLS_MODE" = "mtls" ]; then
    https_cmd='curl -sS --max-time 6 --cacert /etc/ai-memory-a2a/tls/ca.pem --resolve localhost:9077:127.0.0.1 --cert /etc/ai-memory-a2a/tls/client.pem --key /etc/ai-memory-a2a/tls/client.key https://localhost:9077/health'
  else
    https_cmd='curl -sS --max-time 6 --cacert /etc/ai-memory-a2a/tls/ca.pem --resolve localhost:9077:127.0.0.1 https://localhost:9077/health'
  fi
  local body
  body="$(ssh_exec "$ip" "$https_cmd" 2>/dev/null || true)"
  if printf '%s' "$body" | grep -q '"ok"'; then
    https_up=true
  fi

  # mTLS rejection probe — only when mtls. We expect curl to FAIL
  # (handshake rejected by the server's client-cert requirement).
  if [ "$TLS_MODE" = "mtls" ]; then
    local rej_cmd='curl -sS --max-time 6 --cacert /etc/ai-memory-a2a/tls/ca.pem --resolve localhost:9077:127.0.0.1 https://localhost:9077/health; echo "__exit__$?"'
    local rej_out rej_rc
    rej_out="$(ssh_exec "$ip" "$rej_cmd" 2>&1 || true)"
    rej_rc="$(printf '%s' "$rej_out" | sed -n 's/.*__exit__\([0-9]\+\).*/\1/p' | tail -1)"
    rej_rc="${rej_rc:-0}"
    # rc != 0 = curl/handshake failed = mTLS correctly rejected anon.
    if [ "$rej_rc" != "0" ]; then
      mtls_rej_field='"mtls_rejects_anon": true'
    else
      mtls_rej_field='"mtls_rejects_anon": false'
    fi
  fi

  local ok=false
  if [ "$cert_files_present" = "true" ] && [ "$https_up" = "true" ]; then
    if [ "$TLS_MODE" = "mtls" ]; then
      if [[ "$mtls_rej_field" == *"true"* ]]; then ok=true; fi
    else
      ok=true
    fi
  fi

  cat <<JSON
{"node":"$node","ip":"$ip","cert_files_present":$cert_files_present,"missing_cert_files":$missing,"https_listener_up":$https_up,$mtls_rej_field,"ok":$ok}
JSON
}

# ---- TLS_MODE off → skip ------------------------------------------------
if [ "$TLS_MODE" = "off" ]; then
  log "TLS_MODE=off; mTLS preflight skipped (non-blocking pass)"
  cat <<EOF
{"schema":"a2a-preflight-mtls/v1","tls_mode":"off","skipped":true,"droplets":[],"all_ok":true}
EOF
  exit 0
fi

# ---- Required env -------------------------------------------------------
N1="${NODE1_IP:-}"
N2="${NODE2_IP:-}"
N3="${NODE3_IP:-}"
N4="${NODE4_IP:-${MEMORY_NODE_IP:-}}"
if [ -z "$N1" ] || [ -z "$N2" ] || [ -z "$N3" ] || [ -z "$N4" ]; then
  log "FATAL: NODE{1,2,3}_IP and NODE4_IP/MEMORY_NODE_IP all required"
  cat <<EOF
{"schema":"a2a-preflight-mtls/v1","tls_mode":"$TLS_MODE","skipped":false,"droplets":[],"all_ok":false,"error":"missing-node-ip-env"}
EOF
  exit 0
fi

log "checking mTLS preflight on 4 droplets (mode=$TLS_MODE)"
ALL_OK=true
DROPLETS=()
for trip in "node-1:$N1" "node-2:$N2" "node-3:$N3" "node-4:$N4"; do
  name="${trip%%:*}"
  ip="${trip##*:}"
  log "  $name ($ip)"
  rec="$(check_one_droplet "$name" "$ip")"
  DROPLETS+=("$rec")
  if ! printf '%s' "$rec" | grep -q '"ok":true'; then
    ALL_OK=false
  fi
done

# Join with commas
joined=""
for r in "${DROPLETS[@]}"; do
  if [ -z "$joined" ]; then joined="$r"; else joined="$joined,$r"; fi
done

cat <<EOF
{"schema":"a2a-preflight-mtls/v1","tls_mode":"$TLS_MODE","skipped":false,"droplets":[$joined],"all_ok":$ALL_OK}
EOF
exit 0
