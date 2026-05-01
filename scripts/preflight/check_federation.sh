#!/usr/bin/env bash
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
#
# Phase 0 preflight — peer-to-peer federation health.
#
# Confirms each agent node sees the expected peer set:
#   * node-1 must see node-2, node-3, node-4 in its /api/v1/peers
#   * node-2 must see node-1, node-3, node-4
#   * node-3 must see node-1, node-2, node-4
# And confirms `ai-memory federation status` reports healthy on every
# agent node. (Node-4 is the authoritative memory store; it participates
# in the peer mesh but isn't asserted to be the source of an /api/v1/peers
# query in this preflight — its peer-listing behavior differs by build.)
#
# Inputs (env, public IPs of the 4 droplets + private IPs for peer match):
#   NODE1_IP NODE2_IP NODE3_IP NODE4_IP (or MEMORY_NODE_IP)
#   NODE1_PRIV NODE2_PRIV NODE3_PRIV MEMORY_PRIV  (optional — improves match)
#   TLS_MODE   (off | tls | mtls) — controls which curl flags to use
#
# Output:
#   stdout — single-line JSON. Schema:
#     {
#       "schema": "a2a-preflight-federation/v1",
#       "tls_mode": "off|tls|mtls",
#       "agents": [
#         {
#           "node": "node-N",
#           "ip": "<public ip>",
#           "peers_endpoint_reachable": bool,
#           "peer_count": <int>,
#           "expected_peer_count": 3,
#           "missing_peers": [...],         // expected node ids not present
#           "raw_peers": [...],              // peers as the node reported them
#           "federation_status_healthy": bool,
#           "federation_status_raw": "...",
#           "ok": bool
#         }, ...
#       ],
#       "all_ok": bool
#     }
#   exit 0 always.

set -u

SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ServerAliveInterval=5 -o BatchMode=yes)
TLS_MODE="${TLS_MODE:-off}"

log() { printf '[preflight-fed %s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

ssh_exec() {
  local ip="$1"; shift
  ssh "${SSH_OPTS[@]}" "root@${ip}" "$@" 2>/dev/null
}

curl_prefix() {
  if [ "$TLS_MODE" = "off" ]; then
    printf 'curl -sS --max-time 8'
  elif [ "$TLS_MODE" = "mtls" ]; then
    printf 'curl -sS --max-time 8 --cacert /etc/ai-memory-a2a/tls/ca.pem --resolve localhost:9077:127.0.0.1 --cert /etc/ai-memory-a2a/tls/client.pem --key /etc/ai-memory-a2a/tls/client.key'
  else
    printf 'curl -sS --max-time 8 --cacert /etc/ai-memory-a2a/tls/ca.pem --resolve localhost:9077:127.0.0.1'
  fi
}

base_url() {
  if [ "$TLS_MODE" = "off" ]; then
    printf 'http://127.0.0.1:9077'
  else
    printf 'https://localhost:9077'
  fi
}

# Required env
N1="${NODE1_IP:-}"; N2="${NODE2_IP:-}"; N3="${NODE3_IP:-}"
N4="${NODE4_IP:-${MEMORY_NODE_IP:-}}"
P1="${NODE1_PRIV:-}"; P2="${NODE2_PRIV:-}"; P3="${NODE3_PRIV:-}"
P4="${MEMORY_PRIV:-}"

if [ -z "$N1" ] || [ -z "$N2" ] || [ -z "$N3" ] || [ -z "$N4" ]; then
  log "FATAL: NODE{1,2,3}_IP and NODE4_IP/MEMORY_NODE_IP all required"
  cat <<EOF
{"schema":"a2a-preflight-federation/v1","tls_mode":"$TLS_MODE","agents":[],"all_ok":false,"error":"missing-node-ip-env"}
EOF
  exit 0
fi

# ---- Per-agent probe ---------------------------------------------------
check_agent() {
  local node="$1" ip="$2" expect_priv_csv="$3"
  log "  $node ($ip) expects peers: $expect_priv_csv"
  local cp; cp="$(curl_prefix)"
  local url; url="$(base_url)/api/v1/peers"

  # /api/v1/peers
  local peers_raw rc
  peers_raw="$(ssh_exec "$ip" "$cp $url; echo __rc__\$?" 2>/dev/null || true)"
  rc="$(printf '%s' "$peers_raw" | sed -n 's/.*__rc__\([0-9]\+\).*/\1/p' | tail -1)"
  rc="${rc:-1}"
  # strip the rc marker so the body is parseable
  peers_raw="$(printf '%s' "$peers_raw" | sed 's/__rc__[0-9]\+$//')"

  local peers_endpoint_reachable=false
  local peer_count=0
  local raw_peers='[]'
  local missing_peers='[]'
  local matched_peers=()
  local unmatched=()

  if [ "$rc" = "0" ] && [ -n "$peers_raw" ]; then
    peers_endpoint_reachable=true
    # Extract list of peer URLs / addresses heuristically. Several
    # ai-memory builds spell it differently:
    #   * { "peers": ["http://10.10.0.5:9077", ...] }
    #   * { "peers": [{ "url": "...", "private_ip": "..." }, ...] }
    # We let python+jq-equivalent handle both shapes.
    local parsed
    parsed="$(printf '%s' "$peers_raw" | python3 - <<'PY' 2>/dev/null || true
import json, sys
try:
    d = json.loads(sys.stdin.read())
except Exception:
    print(json.dumps({"peers": [], "error": "not-json"}))
    sys.exit(0)
peers = d.get("peers") if isinstance(d, dict) else None
if peers is None and isinstance(d, list):
    peers = d
out = []
for p in (peers or []):
    if isinstance(p, str):
        out.append(p)
    elif isinstance(p, dict):
        out.append(p.get("url") or p.get("private_ip") or p.get("address") or json.dumps(p, sort_keys=True))
print(json.dumps({"peers": out}))
PY
)"
    if [ -n "$parsed" ]; then
      raw_peers="$(printf '%s' "$parsed" | python3 -c 'import json,sys; print(json.dumps(json.loads(sys.stdin.read())["peers"]))')"
      peer_count="$(printf '%s' "$parsed" | python3 -c 'import json,sys; print(len(json.loads(sys.stdin.read())["peers"]))')"
    fi
  fi

  # Compute missing peers — substring match each expected priv IP against
  # the raw peer list. Empty expected (no priv known) → can't compute,
  # we fall back to peer_count >= 3.
  local IFS=','
  local expected_count=0
  if [ -n "$expect_priv_csv" ]; then
    for priv in $expect_priv_csv; do
      [ -z "$priv" ] && continue
      expected_count=$((expected_count + 1))
      if printf '%s' "$raw_peers" | grep -q "$priv"; then
        matched_peers+=("$priv")
      else
        unmatched+=("$priv")
      fi
    done
  fi
  if [ ${#unmatched[@]} -gt 0 ]; then
    missing_peers="[$(printf '"%s",' "${unmatched[@]}" | sed 's/,$//')]"
  fi

  # `ai-memory federation status` — JSON form preferred, else parse text.
  local fed_raw fed_healthy=false
  fed_raw="$(ssh_exec "$ip" "ai-memory federation status --format json 2>/dev/null" || true)"
  if [ -z "$fed_raw" ]; then
    fed_raw="$(ssh_exec "$ip" "ai-memory federation status 2>&1" || true)"
  fi
  if [ -n "$fed_raw" ]; then
    if printf '%s' "$fed_raw" | grep -qiE '"healthy"[[:space:]]*:[[:space:]]*true|status[[:space:]]*:[[:space:]]*"?(ok|healthy|green|info)"?'; then
      fed_healthy=true
    elif printf '%s' "$fed_raw" | grep -qiE '\bhealthy\b|\bok\b' && ! printf '%s' "$fed_raw" | grep -qiE '\b(error|fail|degraded)\b'; then
      fed_healthy=true
    fi
  fi

  # ok = peers endpoint reachable AND (>=3 peers OR all expected priv IPs matched) AND federation healthy
  local ok=false
  if [ "$peers_endpoint_reachable" = "true" ] && [ "$fed_healthy" = "true" ]; then
    if [ "$expected_count" -gt 0 ]; then
      if [ ${#unmatched[@]} -eq 0 ]; then ok=true; fi
    else
      if [ "$peer_count" -ge 3 ]; then ok=true; fi
    fi
  fi

  # JSON-encode federation_status_raw safely (truncate to keep payload bounded)
  local fed_truncated
  fed_truncated="$(printf '%s' "$fed_raw" | head -c 1024 | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""')"

  cat <<JSON
{"node":"$node","ip":"$ip","peers_endpoint_reachable":$peers_endpoint_reachable,"peer_count":$peer_count,"expected_peer_count":$expected_count,"missing_peers":$missing_peers,"raw_peers":$raw_peers,"federation_status_healthy":$fed_healthy,"federation_status_raw":$fed_truncated,"ok":$ok}
JSON
}

# Each agent's expected peer-priv set is the OTHER 3 nodes' private IPs.
EXPECT_1="$P2,$P3,$P4"
EXPECT_2="$P1,$P3,$P4"
EXPECT_3="$P1,$P2,$P4"

ALL_OK=true
RECS=()
for trip in "node-1:$N1:$EXPECT_1" "node-2:$N2:$EXPECT_2" "node-3:$N3:$EXPECT_3"; do
  name="${trip%%:*}"
  rest="${trip#*:}"
  ip="${rest%%:*}"
  expect="${rest#*:}"
  rec="$(check_agent "$name" "$ip" "$expect")"
  RECS+=("$rec")
  if ! printf '%s' "$rec" | grep -q '"ok":true'; then
    ALL_OK=false
  fi
done

joined=""
for r in "${RECS[@]}"; do
  if [ -z "$joined" ]; then joined="$r"; else joined="$joined,$r"; fi
done

cat <<EOF
{"schema":"a2a-preflight-federation/v1","tls_mode":"$TLS_MODE","agents":[$joined],"all_ok":$ALL_OK}
EOF
exit 0
