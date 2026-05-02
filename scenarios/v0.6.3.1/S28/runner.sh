#!/usr/bin/env bash
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
#
# S28 — NHI agent_id immutability (EXPECTED GREEN on v0.6.3.1)
# See contract.md.
#
# Probes four mutation surfaces and asserts metadata.agent_id is
# sticky / preserved across each:
#   1. update_immutability   PUT from ai:bob does not rewrite ai:alice
#   2. dedup_preserves       consolidate keeps BOTH writers' agent_ids
#   3. sync_preserves        federated copy on node-2 keeps origin
#   4. import_preserves      export+import round-trip keeps agent_id
#
# Output: standard scenario JSON on stdout, harness-shape:
#   {"scenario":"S28","pass":<bool>,"expected_verdict":"GREEN",
#    "actual_verdict":"<GREEN|RED|UNKNOWN>","outputs":{...},
#    "reasons":[...]}.
#
# pass == (actual_verdict == expected_verdict). All four sub-checks
# must hold for actual_verdict=GREEN. Any failure => RED + pass=false.

set -euo pipefail

# --- env shim ----------------------------------------------------------
NODE_A="${A2A_NODE_A:-${NODE1_IP:-}}"
NODE_B="${A2A_NODE_B:-${NODE2_IP:-}}"
NODE_C="${A2A_NODE_C:-${NODE3_IP:-}}"
NODE_D="${A2A_NODE_D:-${NODE4_IP:-${MEMORY_NODE_IP:-}}}"
TLS_MODE="${TLS_MODE:-off}"

if [ -z "$NODE_A" ] || [ -z "$NODE_B" ] || [ -z "$NODE_C" ] || [ -z "$NODE_D" ]; then
  cat <<'EOF'
{"scenario":"S28","pass":false,"expected_verdict":"GREEN","actual_verdict":"UNKNOWN","outputs":{},"reasons":["one or more node IPs missing from environment (A2A_NODE_A..D / NODE1_IP..NODE4_IP)"]}
EOF
  exit 0
fi

SETTLE_SECS="${S28_SETTLE_SECS:-8}"
RUN_ID=$(date -u +%Y%m%d%H%M%S)-$$
NS="test/S28/${RUN_ID}"

SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=4)

WORK="$(mktemp -d -t s28.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

stderr() { printf '[s28] %s\n' "$*" >&2; }

# Build the curl prefix used inside ssh-shells (mirrors S24).
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

# --- step 1: update_immutability --------------------------------------
stderr "step 1 — update immutability (ns=${NS})"

post_resp=$(ssh "${SSH_OPTS[@]}" "root@${NODE_A}" "
$CURL -X POST '$BASE/api/v1/memories' \
  -H 'X-Agent-Id: ai:alice' \
  -H 'Content-Type: application/json' \
  -d '{\"tier\":\"mid\",\"namespace\":\"${NS}\",\"title\":\"s28-original\",\"content\":\"s28-original-payload-${RUN_ID}\",\"priority\":5,\"confidence\":1.0,\"source\":\"api\",\"metadata\":{\"agent_id\":\"ai:alice\",\"probe\":\"S28-step1\"}}' 2>/dev/null
" 2> >(sed 's/^/[s28 NODE_A http stderr] /' >&2) || true)

m1_id=$(printf '%s' "$post_resp" | jq -r '.id // .memory.id // empty' 2>/dev/null || true)
m1_initial_agent=$(printf '%s' "$post_resp" | jq -r '.metadata.agent_id // .memory.metadata.agent_id // empty' 2>/dev/null || true)
stderr "  M1 id=${m1_id:-<none>}  initial agent_id=${m1_initial_agent:-<none>}"

original_agent_id="${m1_initial_agent:-}"
update_immutability="false"
post_update_agent_id=""

if [ -z "$m1_id" ]; then
  add_reason "step1: POST did not return an id; response head: $(printf '%s' "$post_resp" | head -c 200 | tr -d '\n')"
else
  # PUT from ai:bob attempting to change content (and incidentally
  # the agent_id metadata). The server SHOULD update the content
  # but pin the agent_id to the original writer.
  put_resp=$(ssh "${SSH_OPTS[@]}" "root@${NODE_A}" "
$CURL -X PUT '$BASE/api/v1/memories/${m1_id}' \
  -H 'X-Agent-Id: ai:bob' \
  -H 'Content-Type: application/json' \
  -d '{\"content\":\"s28-bob-attempted-rewrite-${RUN_ID}\",\"metadata\":{\"agent_id\":\"ai:bob\",\"probe\":\"S28-step1-rewrite\"}}' 2>/dev/null
" 2> >(sed 's/^/[s28 NODE_A http stderr] /' >&2) || true)

  # GET back. We trust the GET more than the PUT response body —
  # some builds echo the request body, others echo the canonical row.
  get_resp=$(ssh "${SSH_OPTS[@]}" "root@${NODE_A}" "
$CURL '$BASE/api/v1/memories/${m1_id}' 2>/dev/null
" 2>/dev/null || true)
  post_update_agent_id=$(printf '%s' "$get_resp" | jq -r '.metadata.agent_id // .memory.metadata.agent_id // empty' 2>/dev/null || true)

  if [ "$post_update_agent_id" = "ai:alice" ]; then
    update_immutability="true"
  else
    add_reason "step1: agent_id was rewritten by PUT — got '${post_update_agent_id}', expected 'ai:alice'"
  fi
fi

# --- step 2: dedup_preserves ------------------------------------------
stderr "step 2 — dedup preserves both agent_ids"

DEDUP_NS="${NS}/dedup"
dedup_content="s28-dedup-collide-${RUN_ID}"

dpost1=$(ssh "${SSH_OPTS[@]}" "root@${NODE_A}" "
$CURL -X POST '$BASE/api/v1/memories' \
  -H 'X-Agent-Id: ai:alice' \
  -H 'Content-Type: application/json' \
  -d '{\"tier\":\"mid\",\"namespace\":\"${DEDUP_NS}\",\"title\":\"s28-dedup-a\",\"content\":\"${dedup_content}\",\"priority\":5,\"confidence\":1.0,\"source\":\"api\",\"metadata\":{\"agent_id\":\"ai:alice\",\"probe\":\"S28-dedup\"}}' 2>/dev/null
" 2>/dev/null || true)
dpost2=$(ssh "${SSH_OPTS[@]}" "root@${NODE_A}" "
$CURL -X POST '$BASE/api/v1/memories' \
  -H 'X-Agent-Id: ai:bob' \
  -H 'Content-Type: application/json' \
  -d '{\"tier\":\"mid\",\"namespace\":\"${DEDUP_NS}\",\"title\":\"s28-dedup-b\",\"content\":\"${dedup_content}\",\"priority\":5,\"confidence\":1.0,\"source\":\"api\",\"metadata\":{\"agent_id\":\"ai:bob\",\"probe\":\"S28-dedup\"}}' 2>/dev/null
" 2>/dev/null || true)

# Trigger consolidate (POST /api/v1/memories/consolidate). Some
# builds expose only memory_consolidate via MCP; if HTTP returns 404
# we fall back to recall-only and assert the curator daemon's
# natural pass either consolidated them or left both visible (with
# both agent_ids reachable in either case).
ssh "${SSH_OPTS[@]}" "root@${NODE_A}" "
$CURL -X POST '$BASE/api/v1/memories/consolidate' \
  -H 'X-Agent-Id: ai:operator' \
  -H 'Content-Type: application/json' \
  -d '{\"namespace\":\"${DEDUP_NS}\"}' 2>/dev/null
" >/dev/null 2>&1 || true

sleep "$SETTLE_SECS"

dedup_recall=$(ssh "${SSH_OPTS[@]}" "root@${NODE_A}" "
$CURL '$BASE/api/v1/memories?namespace=${DEDUP_NS}&limit=200' 2>/dev/null
" 2>/dev/null || echo '{}')

# Walk every memory in the dedup namespace and union all agent_id
# bindings we can find: metadata.agent_id, metadata.source_agents[],
# metadata.consolidated_from_agents[], metadata.agents[]. The
# invariant we're testing is "both ai:alice AND ai:bob remain
# attributable", regardless of which field carries the set.
agents_found=$(printf '%s' "$dedup_recall" | jq -r '
  ([ .memories[]?
     | ( .metadata.agent_id,
         (.metadata.source_agents // [])[]?,
         (.metadata.consolidated_from_agents // [])[]?,
         (.metadata.agents // [])[]? )
   ] // [])
  | map(select(. != null and . != ""))
  | unique
  | join(",")
' 2>/dev/null || echo "")
stderr "  dedup agents observed: ${agents_found}"

dedup_preserves="false"
if printf '%s' ",${agents_found}," | grep -q ',ai:alice,' && printf '%s' ",${agents_found}," | grep -q ',ai:bob,'; then
  dedup_preserves="true"
else
  add_reason "step2: consolidated row(s) lost an agent_id — observed=[${agents_found}], expected to contain both ai:alice and ai:bob"
fi

# Build a JSON array of the agents we found for the outputs envelope.
consolidated_source_agents_json="[]"
if [ -n "$agents_found" ]; then
  consolidated_source_agents_json=$(printf '%s' "$agents_found" | jq -Rc 'split(",") | map(select(length>0))')
fi

# --- step 3: sync_preserves -------------------------------------------
stderr "step 3 — federation sync preserves origin agent_id (settle ${SETTLE_SECS}s)"
sleep "$SETTLE_SECS"

sync_preserves="false"
node2_synced_agent_id=""
if [ -n "$m1_id" ]; then
  node2_resp=$(ssh "${SSH_OPTS[@]}" "root@${NODE_B}" "
$CURL '$BASE/api/v1/memories/${m1_id}' 2>/dev/null
" 2>/dev/null || true)
  node2_synced_agent_id=$(printf '%s' "$node2_resp" | jq -r '.metadata.agent_id // .memory.metadata.agent_id // empty' 2>/dev/null || true)
  if [ -z "$node2_synced_agent_id" ]; then
    # Try a namespace-scoped recall on node-2 — the row may exist
    # without a local index entry by id depending on the build.
    node2_ns_resp=$(ssh "${SSH_OPTS[@]}" "root@${NODE_B}" "
$CURL '$BASE/api/v1/memories?namespace=${NS}&limit=200' 2>/dev/null
" 2>/dev/null || true)
    node2_synced_agent_id=$(printf '%s' "$node2_ns_resp" | jq -r --arg id "$m1_id" '
      .memories[]? | select(.id == $id) | .metadata.agent_id // empty
    ' 2>/dev/null | head -n1 || true)
  fi
  if [ "$node2_synced_agent_id" = "ai:alice" ]; then
    sync_preserves="true"
  else
    add_reason "step3: node-2 sync of M1 has agent_id='${node2_synced_agent_id}', expected 'ai:alice'"
  fi
else
  add_reason "step3: skipped — no M1 id captured in step1"
fi

# --- step 4: import_preserves -----------------------------------------
stderr "step 4 — export + import round-trip preserves agent_id"

import_preserves="false"
imported_agent_id=""
if [ -n "$m1_id" ]; then
  # Export. Some builds use POST /api/v1/memories/export with body,
  # others GET /api/v1/memories/<id>/export. We try POST first and
  # fall back to a self-built dump from the GET we already have.
  export_body=$(ssh "${SSH_OPTS[@]}" "root@${NODE_A}" "
$CURL -X POST '$BASE/api/v1/memories/export' \
  -H 'X-Agent-Id: ai:operator' \
  -H 'Content-Type: application/json' \
  -d '{\"ids\":[\"${m1_id}\"]}' 2>/dev/null
" 2>/dev/null || true)
  if ! printf '%s' "$export_body" | jq -e '.memories | length > 0' >/dev/null 2>&1; then
    # Fallback: synthesise an export envelope from the canonical GET row.
    canonical=$(ssh "${SSH_OPTS[@]}" "root@${NODE_A}" "
$CURL '$BASE/api/v1/memories/${m1_id}' 2>/dev/null
" 2>/dev/null || echo '{}')
    export_body=$(jq -n --argjson m "$canonical" '{memories:[$m]}')
  fi

  IMPORT_NS="${NS}/imported"
  # Re-namespace each memory in the dump so we don't collide with
  # the original. The import endpoint accepts {memories:[...]}.
  import_payload=$(printf '%s' "$export_body" | jq --arg ns "$IMPORT_NS" '
    .memories |= map(.namespace = $ns | .id = null)
  ')

  import_resp=$(ssh "${SSH_OPTS[@]}" "root@${NODE_C}" "
$CURL -X POST '$BASE/api/v1/memories/import' \
  -H 'X-Agent-Id: ai:operator' \
  -H 'Content-Type: application/json' \
  -d $(printf '%s' \"$import_payload\" | jq -Rs .) 2>/dev/null
" 2> >(sed 's/^/[s28 NODE_C import stderr] /' >&2) || true)

  # Some import paths echo the resulting rows; others return only
  # ids/counts. Recall the imported namespace and grab the first row.
  sleep 2
  import_recall=$(ssh "${SSH_OPTS[@]}" "root@${NODE_C}" "
$CURL '$BASE/api/v1/memories?namespace=${IMPORT_NS}&limit=10' 2>/dev/null
" 2>/dev/null || echo '{}')
  imported_agent_id=$(printf '%s' "$import_recall" | jq -r '.memories[0].metadata.agent_id // empty' 2>/dev/null || true)

  if [ "$imported_agent_id" = "ai:alice" ]; then
    import_preserves="true"
  else
    add_reason "step4: imported memory has agent_id='${imported_agent_id}', expected 'ai:alice'"
  fi
else
  add_reason "step4: skipped — no M1 id captured in step1"
fi

# --- verdict ----------------------------------------------------------
expected="GREEN"
if [ "$update_immutability" = "true" ] && [ "$dedup_preserves" = "true" ] && \
   [ "$sync_preserves" = "true" ] && [ "$import_preserves" = "true" ]; then
  actual_verdict="GREEN"
  pass="true"
else
  actual_verdict="RED"
  pass="false"
fi

reasons_json=$(printf '%s\n' "${reasons[@]:-}" | jq -R . | jq -s 'map(select(length>0))')

jq -n \
  --arg scenario "S28" \
  --arg expected_verdict "$expected" \
  --arg actual_verdict "$actual_verdict" \
  --argjson pass "$pass" \
  --argjson update_immutability "$update_immutability" \
  --argjson dedup_preserves "$dedup_preserves" \
  --argjson sync_preserves "$sync_preserves" \
  --argjson import_preserves "$import_preserves" \
  --arg original_agent_id "$original_agent_id" \
  --arg post_update_agent_id "$post_update_agent_id" \
  --argjson consolidated_source_agents "$consolidated_source_agents_json" \
  --arg node2_synced_agent_id "$node2_synced_agent_id" \
  --arg imported_agent_id "$imported_agent_id" \
  --argjson reasons "$reasons_json" \
  '{
    scenario: $scenario,
    pass: $pass,
    expected_verdict: $expected_verdict,
    actual_verdict: $actual_verdict,
    outputs: {
      update_immutability: $update_immutability,
      dedup_preserves: $dedup_preserves,
      sync_preserves: $sync_preserves,
      import_preserves: $import_preserves,
      original_agent_id: $original_agent_id,
      post_update_agent_id: $post_update_agent_id,
      consolidated_source_agents: $consolidated_source_agents,
      node2_synced_agent_id: $node2_synced_agent_id,
      imported_agent_id: $imported_agent_id
    },
    reasons: $reasons
  }'
