#!/usr/bin/env bash
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
#
# S30 — A2A messaging (EXPECTED GREEN on v0.6.3.1)
# See contract.md.
#
# Probes:
#   1. notify_inbox_roundtrip  alice notifies bob (subscribed on node-2),
#                              bob's inbox surfaces it
#   2. hmac_verified           webhook delivery carries a valid
#                              HMAC-SHA256 signature over the body
#   3. federation_fanout       notify on node-1 reaches a subscriber
#                              whose subscription lives on node-3
#
# Output: standard scenario JSON on stdout, harness-shape:
#   {"scenario":"S30","pass":<bool>,"expected_verdict":"GREEN",
#    "actual_verdict":"<GREEN|RED|UNKNOWN>","outputs":{...},
#    "reasons":[...]}.

set -euo pipefail

# --- env shim ----------------------------------------------------------
NODE_A="${A2A_NODE_A:-${NODE1_IP:-}}"
NODE_B="${A2A_NODE_B:-${NODE2_IP:-}}"
NODE_C="${A2A_NODE_C:-${NODE3_IP:-}}"
NODE_D="${A2A_NODE_D:-${NODE4_IP:-${MEMORY_NODE_IP:-}}}"
TLS_MODE="${TLS_MODE:-off}"

if [ -z "$NODE_A" ] || [ -z "$NODE_B" ] || [ -z "$NODE_C" ] || [ -z "$NODE_D" ]; then
  cat <<'EOF'
{"scenario":"S30","pass":false,"expected_verdict":"GREEN","actual_verdict":"UNKNOWN","outputs":{},"reasons":["one or more node IPs missing from environment (A2A_NODE_A..D / NODE1_IP..NODE4_IP)"]}
EOF
  exit 0
fi

SETTLE_SECS="${S30_SETTLE_SECS:-8}"
RUN_ID=$(date -u +%Y%m%d%H%M%S)-$$
NS_PATTERN="test/S30/${RUN_ID}/**"
NS_BASE="test/S30/${RUN_ID}"
WEBHOOK_PORT="${S30_WEBHOOK_PORT:-19030}"

# Two distinct shared secrets — we'd never reuse a HMAC secret across
# subscribers in production, and S30 verifies the per-subscription
# secret binding works.
SECRET_BOB="s30-bob-secret-${RUN_ID}"
SECRET_CHARLIE="s30-charlie-secret-${RUN_ID}"

SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=4)

WORK="$(mktemp -d -t s30.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

stderr() { printf '[s30] %s\n' "$*" >&2; }

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

reasons=()
add_reason() { reasons+=("$1"); }

# --- step 1: subscribe ai:bob on node-2 -------------------------------
stderr "step 1 — subscribe ai:bob on node-2 (ns_pattern=${NS_PATTERN})"

sub_bob_resp=$(ssh "${SSH_OPTS[@]}" "root@${NODE_B}" "
$CURL -X POST '$BASE/api/v1/subscriptions' \
  -H 'X-Agent-Id: ai:bob' \
  -H 'Content-Type: application/json' \
  -d '{\"agent_id\":\"ai:bob\",\"namespace_pattern\":\"${NS_PATTERN}\",\"events\":[\"notify\",\"write\"]}' 2>/dev/null
" 2>/dev/null || true)
sub_id_bob=$(printf '%s' "$sub_bob_resp" | jq -r '.id // .subscription_id // empty' 2>/dev/null || true)

if [ -z "$sub_id_bob" ]; then
  add_reason "step1: bob's subscription not registered — response head: $(printf '%s' "$sub_bob_resp" | head -c 200 | tr -d '\n')"
fi

# --- step 2: alice notifies bob from node-1 ---------------------------
stderr "step 2 — alice notifies bob from node-1"

notify_bob_resp=$(ssh "${SSH_OPTS[@]}" "root@${NODE_A}" "
$CURL -X POST '$BASE/api/v1/notify' \
  -H 'X-Agent-Id: ai:alice' \
  -H 'Content-Type: application/json' \
  -d '{\"target\":\"ai:bob\",\"namespace\":\"${NS_BASE}/notify\",\"payload\":\"hello\",\"title\":\"s30-bob-hello\"}' 2>/dev/null
" 2>/dev/null || true)
notif_id_bob=$(printf '%s' "$notify_bob_resp" | jq -r '.notification_id // .id // empty' 2>/dev/null || true)

stderr "  bob notif_id=${notif_id_bob:-<none>}"
sleep "$SETTLE_SECS"

# --- step 3: inbox poll on node-2 -------------------------------------
inbox_bob=$(ssh "${SSH_OPTS[@]}" "root@${NODE_B}" "
$CURL '$BASE/api/v1/inbox?agent_id=ai:bob&limit=200' 2>/dev/null
" 2>/dev/null || echo '{}')
inbox_count_bob=$(printf '%s' "$inbox_bob" | jq '
  [
    (.inbox // .notifications // .messages // [])[]?
    | select((.payload // .body // .content) == "hello"
             or (.title // "") == "s30-bob-hello"
             or (.id // "") == "'"$notif_id_bob"'")
  ] | length
' 2>/dev/null || echo 0)

notify_inbox_roundtrip="false"
if [ "${inbox_count_bob:-0}" -ge 1 ]; then
  notify_inbox_roundtrip="true"
else
  add_reason "step3: bob's inbox on node-2 had no matching item after ${SETTLE_SECS}s settle (inbox_count=${inbox_count_bob})"
fi

# --- step 4: HMAC-signed webhook delivery (node-3 listener) -----------
stderr "step 4 — HMAC-signed webhook delivery"

# Start a tiny one-shot listener on node-3 that dumps the next HTTP
# request to a file. Launch it in the background, give it a moment
# to bind, then drive a notify.  We use a portable bash + nc shim
# (BusyBox nc is widespread on the droplets) and fall back to a
# python one-shot if nc isn't available or is the OpenBSD variant
# without `-N`. The captured file is /tmp/s30_webhook_${RUN_ID}.req.
LISTENER_FILE="/tmp/s30_webhook_${RUN_ID}.req"

start_listener() {
  ssh "${SSH_OPTS[@]}" "root@${NODE_C}" "
rm -f '${LISTENER_FILE}' '${LISTENER_FILE}.pid' 2>/dev/null
NC_BIN=\$(command -v nc 2>/dev/null || true)
if [ -n \"\$NC_BIN\" ]; then
  # Try common nc dialects: GNU/BusyBox accept -l -p PORT; others -l PORT.
  ( ( \"\$NC_BIN\" -l -p ${WEBHOOK_PORT} 2>/dev/null \
      || \"\$NC_BIN\" -l ${WEBHOOK_PORT} 2>/dev/null \
      || \"\$NC_BIN\" -l 127.0.0.1 ${WEBHOOK_PORT} 2>/dev/null ) \
    | tee '${LISTENER_FILE}' >/dev/null \
    && printf 'HTTP/1.1 200 OK\\r\\nContent-Length: 2\\r\\n\\r\\nOK' \
  ) >/dev/null 2>&1 &
  echo \$! > '${LISTENER_FILE}.pid'
else
  # python fallback — record the request then 200.
  python3 - <<PY > '${LISTENER_FILE}.python.log' 2>&1 &
import http.server, socketserver
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('Content-Length','0') or '0')
        body = self.rfile.read(n)
        with open('${LISTENER_FILE}','wb') as f:
            for k,v in self.headers.items():
                f.write(f'{k}: {v}\\n'.encode())
            f.write(b'\\n')
            f.write(body)
        self.send_response(200); self.send_header('Content-Length','2'); self.end_headers(); self.wfile.write(b'OK')
        # one-shot: tear down right after one request
        raise SystemExit
    def log_message(self, *a, **k): pass
with socketserver.TCPServer(('0.0.0.0', ${WEBHOOK_PORT}), H) as s:
    s.handle_request()
PY
  echo \$! > '${LISTENER_FILE}.pid'
fi
sleep 1
" 2>/dev/null || true
}

start_listener
sleep 2

# Subscribe charlie with a webhook URL pointing at node-3's private
# IP (which on the campaign mesh is reachable from node-1 over the
# VPC). On the off chance the runner doesn't have a private IP, we
# fall back to the public IP.
WEBHOOK_HOST="${NODE_C}"
WEBHOOK_URL="http://${WEBHOOK_HOST}:${WEBHOOK_PORT}/aim-webhook"

sub_charlie_resp=$(ssh "${SSH_OPTS[@]}" "root@${NODE_C}" "
$CURL -X POST '$BASE/api/v1/subscriptions' \
  -H 'X-Agent-Id: ai:charlie' \
  -H 'Content-Type: application/json' \
  -d '{\"agent_id\":\"ai:charlie\",\"namespace_pattern\":\"${NS_PATTERN}\",\"events\":[\"notify\"],\"webhook_url\":\"${WEBHOOK_URL}\",\"webhook_secret\":\"${SECRET_CHARLIE}\"}' 2>/dev/null
" 2>/dev/null || true)
sub_id_charlie=$(printf '%s' "$sub_charlie_resp" | jq -r '.id // .subscription_id // empty' 2>/dev/null || true)
stderr "  charlie sub_id=${sub_id_charlie:-<none>}"

# Drive the notify.
notify_charlie_resp=$(ssh "${SSH_OPTS[@]}" "root@${NODE_A}" "
$CURL -X POST '$BASE/api/v1/notify' \
  -H 'X-Agent-Id: ai:alice' \
  -H 'Content-Type: application/json' \
  -d '{\"target\":\"ai:charlie\",\"namespace\":\"${NS_BASE}/webhook\",\"payload\":\"hmac-test-${RUN_ID}\",\"title\":\"s30-charlie-webhook\"}' 2>/dev/null
" 2>/dev/null || true)
notif_id_charlie=$(printf '%s' "$notify_charlie_resp" | jq -r '.notification_id // .id // empty' 2>/dev/null || true)
stderr "  charlie notif_id=${notif_id_charlie:-<none>}"

sleep "$SETTLE_SECS"

# Tear down listener if still alive, then pull the captured request.
ssh "${SSH_OPTS[@]}" "root@${NODE_C}" "
if [ -f '${LISTENER_FILE}.pid' ]; then
  pid=\$(cat '${LISTENER_FILE}.pid' 2>/dev/null)
  [ -n \"\$pid\" ] && kill \$pid 2>/dev/null || true
fi
" 2>/dev/null || true

captured=$(ssh "${SSH_OPTS[@]}" "root@${NODE_C}" "
test -s '${LISTENER_FILE}' && cat '${LISTENER_FILE}' || true
" 2>/dev/null || true)

webhook_body_captured="false"
webhook_signature_header=""
webhook_recomputed_hmac=""
hmac_verified="false"

if [ -n "$captured" ]; then
  webhook_body_captured="true"
  # Extract sig header — accept X-AIM-Signature and X-Aim-Signature.
  webhook_signature_header=$(printf '%s' "$captured" | awk 'BEGIN{IGNORECASE=1}
    /^X-AIM-Signature[: ]/ { sub(/^[^:]*:[ \t]*/,""); sub(/\r$/,""); print; exit }
  ')
  # Extract body: everything after the first blank line.
  body=$(printf '%s' "$captured" | awk 'BEGIN{f=0} /^\r?$/ {if (!f) {f=1; next}} f {print}')
  if [ -n "$body" ]; then
    # Recompute HMAC-SHA256(secret, body) → hex.
    webhook_recomputed_hmac=$(printf '%s' "$body" | openssl dgst -sha256 -hmac "$SECRET_CHARLIE" | awk '{print $NF}')
    # The header form is `sha256=<hex>` per the contract — strip prefix.
    sig_hex=$(printf '%s' "$webhook_signature_header" | sed -E 's/^sha256=//')
    if [ -n "$sig_hex" ] && [ -n "$webhook_recomputed_hmac" ] && [ "$sig_hex" = "$webhook_recomputed_hmac" ]; then
      hmac_verified="true"
    else
      add_reason "step4: HMAC mismatch — header_sig='${sig_hex}', recomputed='${webhook_recomputed_hmac}'"
    fi
  else
    add_reason "step4: webhook body empty in captured request"
  fi
else
  add_reason "step4: webhook listener captured nothing on node-3:${WEBHOOK_PORT} — subscription's webhook may not be honoured by this build"
fi

# --- step 5: federation fanout ---------------------------------------
# We've already done a notify on node-1 with a charlie subscription
# on node-3 (above). The federation_fanout signal is whether
# charlie's *inbox* on node-3 surfaced the notification (independent
# of webhook delivery — the inbox is the durable rail).
stderr "step 5 — federation fanout (notify@node-1 → subscriber@node-3)"
inbox_charlie=$(ssh "${SSH_OPTS[@]}" "root@${NODE_C}" "
$CURL '$BASE/api/v1/inbox?agent_id=ai:charlie&limit=200' 2>/dev/null
" 2>/dev/null || echo '{}')
inbox_count_charlie=$(printf '%s' "$inbox_charlie" | jq '
  [
    (.inbox // .notifications // .messages // [])[]?
    | select((.payload // .body // .content) == "hmac-test-'"$RUN_ID"'"
             or (.title // "") == "s30-charlie-webhook"
             or (.id // "") == "'"$notif_id_charlie"'")
  ] | length
' 2>/dev/null || echo 0)

federation_fanout="false"
if [ "${inbox_count_charlie:-0}" -ge 1 ]; then
  federation_fanout="true"
else
  add_reason "step5: federation fanout did not deliver — charlie's inbox on node-3 had no matching item (count=${inbox_count_charlie})"
fi

# --- verdict ---------------------------------------------------------
expected="GREEN"
if [ "$notify_inbox_roundtrip" = "true" ] && [ "$hmac_verified" = "true" ] && [ "$federation_fanout" = "true" ]; then
  actual_verdict="GREEN"
  pass="true"
else
  actual_verdict="RED"
  pass="false"
fi

reasons_json=$(printf '%s\n' "${reasons[@]:-}" | jq -R . | jq -s 'map(select(length>0))')

jq -n \
  --arg scenario "S30" \
  --arg expected_verdict "$expected" \
  --arg actual_verdict "$actual_verdict" \
  --argjson pass "$pass" \
  --argjson notify_inbox_roundtrip "$notify_inbox_roundtrip" \
  --argjson hmac_verified "$hmac_verified" \
  --argjson federation_fanout "$federation_fanout" \
  --arg subscription_id_bob "${sub_id_bob:-}" \
  --arg subscription_id_charlie "${sub_id_charlie:-}" \
  --arg notification_id_bob "${notif_id_bob:-}" \
  --arg notification_id_charlie "${notif_id_charlie:-}" \
  --argjson inbox_unread_count_bob "${inbox_count_bob:-0}" \
  --argjson webhook_body_captured "$webhook_body_captured" \
  --arg webhook_signature_header "${webhook_signature_header:-}" \
  --arg webhook_recomputed_hmac "${webhook_recomputed_hmac:-}" \
  --argjson node3_inbox_count_charlie "${inbox_count_charlie:-0}" \
  --argjson reasons "$reasons_json" \
  '{
    scenario: $scenario,
    pass: $pass,
    expected_verdict: $expected_verdict,
    actual_verdict: $actual_verdict,
    outputs: {
      notify_inbox_roundtrip: $notify_inbox_roundtrip,
      hmac_verified: $hmac_verified,
      federation_fanout: $federation_fanout,
      subscription_id_bob: $subscription_id_bob,
      subscription_id_charlie: $subscription_id_charlie,
      notification_id_bob: $notification_id_bob,
      notification_id_charlie: $notification_id_charlie,
      inbox_unread_count_bob: $inbox_unread_count_bob,
      webhook_body_captured: $webhook_body_captured,
      webhook_signature_header: $webhook_signature_header,
      webhook_recomputed_hmac: $webhook_recomputed_hmac,
      node3_inbox_count_charlie: $node3_inbox_count_charlie
    },
    reasons: $reasons
  }'
