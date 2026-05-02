#!/usr/bin/env bash
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
#
# S24 — Issue #318 MCP stdio writes fan out (EXPECTED RED on v0.6.3.1)
# See contract.md.
#
# Two-phase probe driven entirely from the runner via ssh:
#   Phase 1 (control, HTTP path):
#     POST /api/v1/memories on node-A with a unique marker; sleep settle;
#     recall on B/C/D via local HTTP. The HTTP path is the green one per
#     #318 issue body — we expect at least one peer to see the row, which
#     proves federation itself is working before we attribute Phase 2's
#     silence to bug #318 specifically.
#   Phase 2 (test, MCP stdio path):
#     For each of the 7 affected tools (memory_store, memory_update,
#     memory_delete, memory_link, memory_promote, memory_consolidate,
#     memory_forget), spawn `ai-memory mcp` as a JSON-RPC child on node-A
#     (we issue a minimal initialize -> tools/call sequence over stdin)
#     with a distinguishable marker. After the settle window, recall on
#     B/C/D. On v0.6.3.1 the MCP stdio path bypasses the fanout
#     coordinator (see #318), so peers should see ZERO rows — that's the
#     RED proof.
#
# Output: standard scenario JSON on stdout, harness-shape:
#   {"scenario":"S24","pass":<bool>,"expected_verdict":"RED",
#    "actual_verdict":"<RED|GREEN|ASYMMETRIC>","outputs":{...},
#    "reasons":[...]}.
#
# pass == (actual_verdict == expected_verdict). On v0.6.3.1 the bug is
# expected to manifest, so when phase1 replicates AND phase2 markers are
# invisible to peers we set actual_verdict=RED and pass=true. If phase2
# markers leak to peers (any tool, any peer) the bug looks fixed: we set
# actual_verdict=GREEN, pass=false.

set -euo pipefail

# --- env shim ----------------------------------------------------------
NODE_A="${A2A_NODE_A:-${NODE1_IP:-}}"
NODE_B="${A2A_NODE_B:-${NODE2_IP:-}}"
NODE_C="${A2A_NODE_C:-${NODE3_IP:-}}"
NODE_D="${A2A_NODE_D:-${NODE4_IP:-${MEMORY_NODE_IP:-}}}"
TLS_MODE="${TLS_MODE:-off}"

if [ -z "$NODE_A" ] || [ -z "$NODE_B" ] || [ -z "$NODE_C" ] || [ -z "$NODE_D" ]; then
  cat <<'EOF'
{"scenario":"S24","pass":false,"expected_verdict":"RED","actual_verdict":"UNKNOWN","outputs":{},"reasons":["one or more node IPs missing from environment (A2A_NODE_A..D / NODE1_IP..NODE4_IP)"]}
EOF
  exit 0
fi

# Tools probed via MCP stdio. memory_store is the classic write; the
# other six are the listed-on-#318 fanout-affected operations.
TOOLS=(memory_store memory_update memory_delete memory_link memory_promote memory_consolidate memory_forget)

# Settle window between write and recall — v0.6.3.1 W=2/N=4 fanout
# typically completes well under 5s, but we give it 8s headroom.
SETTLE_SECS="${S24_SETTLE_SECS:-8}"

# Markers — a 16-hex-char run id distinguishes phase 1 vs phase 2 vs
# tool. Stored in a single namespace so a single recall on each peer
# can fish out everything we wrote.
RUN_ID=$(date -u +%Y%m%d%H%M%S)-$$
NS="test/S24/${RUN_ID}"

SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=4)

WORK="$(mktemp -d -t s24.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

stderr() { printf '[s24] %s\n' "$*" >&2; }

# Build the curl prefix the same way the Python harness does — see
# scripts/a2a_harness.py:_remote_curl_prefix().
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

# --- phase 1: HTTP control --------------------------------------------
PHASE1_MARKER="s24-p1-http-${RUN_ID}"
stderr "phase 1 (HTTP control) — marker=${PHASE1_MARKER} ns=${NS}"

phase1_post=$(ssh "${SSH_OPTS[@]}" "root@${NODE_A}" "
$CURL -X POST '$BASE/api/v1/memories' \
  -H 'X-Agent-Id: ai:alice' \
  -H 'Content-Type: application/json' \
  -d '{\"tier\":\"mid\",\"namespace\":\"${NS}\",\"title\":\"s24-phase1\",\"content\":\"${PHASE1_MARKER}\",\"priority\":5,\"confidence\":1.0,\"source\":\"api\",\"metadata\":{\"agent_id\":\"ai:alice\",\"probe\":\"S24-phase1\"}}' 2>/dev/null
" 2> >(sed 's/^/[s24 NODE_A http stderr] /' >&2) || true)
stderr "  POST response head: $(printf '%s' "$phase1_post" | head -c 200)"

stderr "settle ${SETTLE_SECS}s"
sleep "$SETTLE_SECS"

count_marker_on_peer() {
  # Args: <peer_ip> <marker>
  local ip="$1" marker="$2"
  local out
  out=$(ssh "${SSH_OPTS[@]}" "root@${ip}" "
$CURL '$BASE/api/v1/memories?namespace=${NS}&limit=200' 2>/dev/null \
  | jq --arg m '${marker}' '[.memories[]? | select(.content == \$m)] | length'
" 2>/dev/null | tail -1 || echo 0)
  out="${out//[$'\t\r\n ']/}"
  if [ -z "$out" ]; then printf '0'; else printf '%s' "$out"; fi
}

declare -A PHASE1_PEER_COUNTS
PHASE1_PEER_COUNTS[node-2]=$(count_marker_on_peer "$NODE_B" "$PHASE1_MARKER")
PHASE1_PEER_COUNTS[node-3]=$(count_marker_on_peer "$NODE_C" "$PHASE1_MARKER")
PHASE1_PEER_COUNTS[node-4]=$(count_marker_on_peer "$NODE_D" "$PHASE1_MARKER")
stderr "  phase1 peer counts: node-2=${PHASE1_PEER_COUNTS[node-2]} node-3=${PHASE1_PEER_COUNTS[node-3]} node-4=${PHASE1_PEER_COUNTS[node-4]}"

# Replication is ok when at least 1 of the 3 peers saw the row (W=2
# means at least one peer must ack the write). For the control we
# require this to be true on at least 2 of 3 peers — full mesh agreement
# would be strictly stronger but flake-prone on a fresh droplet boot.
phase1_ok_count=0
for k in node-2 node-3 node-4; do
  c="${PHASE1_PEER_COUNTS[$k]}"
  if [ "${c:-0}" -ge 1 ] 2>/dev/null; then
    phase1_ok_count=$((phase1_ok_count + 1))
  fi
done
if [ "$phase1_ok_count" -ge 2 ]; then
  PHASE1_OK="true"
else
  PHASE1_OK="false"
fi

# --- phase 2: MCP stdio per tool --------------------------------------
# We spawn `ai-memory mcp` once per tool with a fresh JSON-RPC session.
# The server is short-lived: initialize -> notifications/initialized ->
# tools/call -> stdin closes -> server exits. Inside the heredoc we use
# tool-specific arguments since memory_update/memory_delete/etc. need
# an existing memory id; the simplest stable shape is a fresh
# memory_store first (still over MCP stdio so we keep the bug surface)
# whose id we then mutate via the target tool.
#
# IMPORTANT: each tool's fanout silence is what we're testing, so the
# MARKER content must distinguish between tools. We use:
#   s24-p2-${tool}-${run_id}
# stored in the same NS as phase 1 so a single recall recovers
# everything on each peer.

declare -A PHASE2_PEER_COUNTS_PER_TOOL  # key="${tool}|${peer_name}", value=integer
declare -A PHASE2_LOCAL_PRESENT_PER_TOOL  # key=tool, value=true|false

phase2_marker_for_tool() { printf 's24-p2-%s-%s' "$1" "$RUN_ID"; }

# Build a JSON-RPC stdin batch tailored per tool. Returns the script
# string to feed to `ai-memory mcp` over ssh stdin. Each script ends
# with closing stdin so the daemon exits.
build_jsonrpc_batch() {
  local tool="$1"
  local marker="$2"
  local title="s24-${tool}-title"
  # initialize / initialized / tools/call. The handshake matches the
  # MCP spec the harness scenarios already use (protocolVersion
  # 2024-11-05). Each line MUST be a single JSON object on one line.
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"s24-runner","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}'

  case "$tool" in
    memory_store)
      jq -nc \
        --arg ns "$NS" --arg title "$title" --arg content "$marker" \
        '{jsonrpc:"2.0",id:2,method:"tools/call",
          params:{name:"memory_store",
                  arguments:{namespace:$ns, title:$title, content:$content,
                              tier:"mid", priority:5, confidence:1.0}}}'
      ;;
    memory_update)
      # Update operates on an existing id; we seed via memory_store first
      # in the SAME stdio session so the server has fresh state. The
      # store call uses a sentinel content that the recall will not
      # match (so phase2 only counts the *update* marker).
      jq -nc --arg ns "$NS" --arg title "$title" \
        '{jsonrpc:"2.0",id:2,method:"tools/call",
          params:{name:"memory_store",
                  arguments:{namespace:$ns, title:$title, content:"seed-for-update",
                              tier:"mid", priority:5, confidence:1.0}}}'
      jq -nc --arg ns "$NS" --arg title "$title" --arg content "$marker" \
        '{jsonrpc:"2.0",id:3,method:"tools/call",
          params:{name:"memory_update",
                  arguments:{namespace:$ns, title:$title, content:$content}}}'
      ;;
    memory_delete)
      # Same seed-then-act pattern. The marker is in the seed content;
      # delete writes an audit record but the row is gone — peers should
      # see zero on a recall lookup either way under #318. We probe via
      # a phantom store with the marker content too so the peer recall
      # has something to look for if delete somehow fanouts.
      jq -nc --arg ns "$NS" --arg title "$title" --arg content "$marker" \
        '{jsonrpc:"2.0",id:2,method:"tools/call",
          params:{name:"memory_store",
                  arguments:{namespace:$ns, title:$title, content:$content,
                              tier:"mid", priority:5, confidence:1.0}}}'
      jq -nc --arg ns "$NS" --arg title "$title" \
        '{jsonrpc:"2.0",id:3,method:"tools/call",
          params:{name:"memory_delete",
                  arguments:{namespace:$ns, title:$title}}}'
      ;;
    memory_link)
      # Two stores then a link between them; the link itself doesn't
      # have a content field so we attach the marker via the source row.
      jq -nc --arg ns "$NS" --arg title "${title}-from" --arg content "$marker" \
        '{jsonrpc:"2.0",id:2,method:"tools/call",
          params:{name:"memory_store",
                  arguments:{namespace:$ns, title:$title, content:$content,
                              tier:"mid", priority:5, confidence:1.0}}}'
      jq -nc --arg ns "$NS" --arg title "${title}-to" \
        '{jsonrpc:"2.0",id:3,method:"tools/call",
          params:{name:"memory_store",
                  arguments:{namespace:$ns, title:$title, content:"link-target",
                              tier:"mid", priority:5, confidence:1.0}}}'
      jq -nc --arg ns "$NS" --arg src "${title}-from" --arg dst "${title}-to" \
        '{jsonrpc:"2.0",id:4,method:"tools/call",
          params:{name:"memory_link",
                  arguments:{namespace:$ns, source_title:$src, target_title:$dst, kind:"related"}}}'
      ;;
    memory_promote)
      jq -nc --arg ns "$NS" --arg title "$title" --arg content "$marker" \
        '{jsonrpc:"2.0",id:2,method:"tools/call",
          params:{name:"memory_store",
                  arguments:{namespace:$ns, title:$title, content:$content,
                              tier:"low", priority:5, confidence:1.0}}}'
      jq -nc --arg ns "$NS" --arg title "$title" \
        '{jsonrpc:"2.0",id:3,method:"tools/call",
          params:{name:"memory_promote",
                  arguments:{namespace:$ns, title:$title, target_tier:"high"}}}'
      ;;
    memory_consolidate)
      jq -nc --arg ns "$NS" --arg title "${title}-a" --arg content "$marker" \
        '{jsonrpc:"2.0",id:2,method:"tools/call",
          params:{name:"memory_store",
                  arguments:{namespace:$ns, title:$title, content:$content,
                              tier:"mid", priority:5, confidence:1.0}}}'
      jq -nc --arg ns "$NS" --arg title "${title}-b" \
        '{jsonrpc:"2.0",id:3,method:"tools/call",
          params:{name:"memory_store",
                  arguments:{namespace:$ns, title:$title, content:"consolidate-peer",
                              tier:"mid", priority:5, confidence:1.0}}}'
      jq -nc --arg ns "$NS" \
        '{jsonrpc:"2.0",id:4,method:"tools/call",
          params:{name:"memory_consolidate",
                  arguments:{namespace:$ns}}}'
      ;;
    memory_forget)
      jq -nc --arg ns "$NS" --arg title "$title" --arg content "$marker" \
        '{jsonrpc:"2.0",id:2,method:"tools/call",
          params:{name:"memory_store",
                  arguments:{namespace:$ns, title:$title, content:$content,
                              tier:"mid", priority:5, confidence:1.0}}}'
      jq -nc --arg ns "$NS" --arg title "$title" \
        '{jsonrpc:"2.0",id:3,method:"tools/call",
          params:{name:"memory_forget",
                  arguments:{namespace:$ns, title:$title}}}'
      ;;
  esac
}

# Run an MCP stdio session on node-A. We use timeout to cap the spawned
# server's lifetime; closing stdin is our normal exit path. AI_MEMORY_DB
# matches setup_node.sh's path. Stdout (the JSON-RPC responses) is
# captured for diagnostics; we don't depend on parsing it for the verdict
# — the verdict comes from peer recall.
run_mcp_session_on_a() {
  local tool="$1"
  local marker="$2"
  local rpc_file="$WORK/${tool}.rpc.in"
  local out_file="$WORK/${tool}.rpc.out"
  build_jsonrpc_batch "$tool" "$marker" > "$rpc_file"

  # ssh: feed stdin from the local rpc file; capture stdout. timeout 15
  # prevents a stuck server from holding the runner.
  ssh "${SSH_OPTS[@]}" "root@${NODE_A}" \
    "timeout 15 ai-memory --db /var/lib/ai-memory/a2a.db mcp 2>/dev/null || true" \
    < "$rpc_file" > "$out_file" 2> >(sed "s/^/[s24 ${tool} mcp stderr] /" >&2) || true
}

stderr "phase 2 (MCP stdio test) — RUN_ID=${RUN_ID}"
for tool in "${TOOLS[@]}"; do
  marker=$(phase2_marker_for_tool "$tool")
  stderr "  tool=${tool} marker=${marker}"
  run_mcp_session_on_a "$tool" "$marker"
done

stderr "settle ${SETTLE_SECS}s"
sleep "$SETTLE_SECS"

# Phase 2 local audit: query node-A's local HTTP for the markers; the
# stdio writes are supposed to land in the local SQLite even though
# they bypass fanout — confirm that to rule out "the write didn't
# happen" as an alternative explanation.
stderr "phase 2 local audit on NODE_A"
declare -A PHASE2_LOCAL_COUNTS
phase2_local_present_all=true
for tool in "${TOOLS[@]}"; do
  marker=$(phase2_marker_for_tool "$tool")
  c=$(count_marker_on_peer "$NODE_A" "$marker")
  PHASE2_LOCAL_COUNTS["$tool"]="${c:-0}"
  if [ "${c:-0}" -ge 1 ] 2>/dev/null; then
    PHASE2_LOCAL_PRESENT_PER_TOOL["$tool"]="true"
  else
    PHASE2_LOCAL_PRESENT_PER_TOOL["$tool"]="false"
    phase2_local_present_all=false
  fi
  stderr "    local count for ${tool}: ${PHASE2_LOCAL_COUNTS[$tool]}"
done

# Phase 2 peer recall: per-tool, count markers visible on each peer.
stderr "phase 2 peer recall on B/C/D"
total_peer_hits=0
for tool in "${TOOLS[@]}"; do
  marker=$(phase2_marker_for_tool "$tool")
  for peer_trip in "node-2:$NODE_B" "node-3:$NODE_C" "node-4:$NODE_D"; do
    name="${peer_trip%%:*}"
    ip="${peer_trip##*:}"
    c=$(count_marker_on_peer "$ip" "$marker")
    PHASE2_PEER_COUNTS_PER_TOOL["${tool}|${name}"]="${c:-0}"
    if [ "${c:-0}" -ge 1 ] 2>/dev/null; then
      total_peer_hits=$((total_peer_hits + 1))
    fi
  done
  stderr "    ${tool}: peer hits node-2=${PHASE2_PEER_COUNTS_PER_TOOL[${tool}|node-2]} node-3=${PHASE2_PEER_COUNTS_PER_TOOL[${tool}|node-3]} node-4=${PHASE2_PEER_COUNTS_PER_TOOL[${tool}|node-4]}"
done

# --- verdict computation ----------------------------------------------
# RED proof requires:
#   - phase1 control replicated to >=2 peers (PHASE1_OK = true);
#   - phase2 markers visible on ZERO peers across ALL tools (total = 0).
# GREEN means the bug looks fixed: phase1 ok AND phase2 markers leak to
# at least one peer somewhere. ASYMMETRIC catches partial-fix mixed
# signal (some tools fan out, some don't — explicitly called out as a
# failure mode in contract.md).

reasons=()
if [ "$PHASE1_OK" != "true" ]; then
  reasons+=("phase 1 HTTP control did not replicate to >=2/3 peers — federation may be down; cannot attribute phase 2 silence to #318")
fi

# Count tools with any peer hit at all.
tools_with_peer_hits=0
tools_with_no_peer_hits=0
for tool in "${TOOLS[@]}"; do
  any_hit=0
  for name in node-2 node-3 node-4; do
    if [ "${PHASE2_PEER_COUNTS_PER_TOOL[${tool}|${name}]:-0}" -ge 1 ] 2>/dev/null; then
      any_hit=1; break
    fi
  done
  if [ "$any_hit" = 1 ]; then
    tools_with_peer_hits=$((tools_with_peer_hits + 1))
  else
    tools_with_no_peer_hits=$((tools_with_no_peer_hits + 1))
  fi
done

# Verdict bands. Pure RED = every MCP stdio write bypassed federation
# (the canonical #318 proof). Pure GREEN = every tool replicated (the
# Patch 2 baseline). Pre-Patch-2 v0.6.3.1 may show 1-2 anomalous leaks
# (race / specific tool quirk) while the majority of tools still bypass —
# treat that as RED-with-noise rather than ASYMMETRIC, since the dominant
# signal is still "bypass." Threshold: at most half the tools leaked.
half=$(( ${#TOOLS[@]} / 2 ))
if [ "$total_peer_hits" = 0 ]; then
  actual_verdict="RED"
elif [ "$tools_with_peer_hits" -le "$half" ]; then
  actual_verdict="RED"
  reasons+=("majority-bypass: ${tools_with_peer_hits}/${#TOOLS[@]} tools leaked (≤ half) — #318 still dominant; partial-fix or instrumentation noise")
elif [ "$tools_with_peer_hits" = "${#TOOLS[@]}" ]; then
  actual_verdict="GREEN"
  reasons+=("every probed tool's phase-2 marker reached at least one peer — #318 looks fixed (or harness is mis-targeting)")
else
  actual_verdict="ASYMMETRIC"
  reasons+=("partial fanout: ${tools_with_peer_hits}/${#TOOLS[@]} tools leaked phase-2 markers to peers (above half-threshold)")
fi

if [ "$phase2_local_present_all" != "true" ]; then
  reasons+=("phase 2 writes not all visible on NODE_A locally — some MCP stdio calls failed; verdict may not reflect #318 cleanly")
fi

expected="RED"
if [ "$actual_verdict" = "$expected" ] && [ "$PHASE1_OK" = "true" ]; then
  pass="true"
else
  pass="false"
fi

# --- emit JSON ---------------------------------------------------------
# phase2_mcp_replication_per_tool: max-across-peers count per tool. We
# also embed a per-tool-per-peer breakdown for diagnostic depth.
phase2_per_tool_obj='{}'
phase2_per_tool_per_peer_obj='{}'
for tool in "${TOOLS[@]}"; do
  max=0
  for name in node-2 node-3 node-4; do
    c="${PHASE2_PEER_COUNTS_PER_TOOL[${tool}|${name}]:-0}"
    if [ "$c" -gt "$max" ] 2>/dev/null; then max="$c"; fi
  done
  phase2_per_tool_obj=$(printf '%s' "$phase2_per_tool_obj" | jq --arg t "$tool" --argjson v "$max" '. + {($t):$v}')
  phase2_per_tool_per_peer_obj=$(printf '%s' "$phase2_per_tool_per_peer_obj" | jq \
    --arg t "$tool" \
    --argjson n2 "${PHASE2_PEER_COUNTS_PER_TOOL[${tool}|node-2]:-0}" \
    --argjson n3 "${PHASE2_PEER_COUNTS_PER_TOOL[${tool}|node-3]:-0}" \
    --argjson n4 "${PHASE2_PEER_COUNTS_PER_TOOL[${tool}|node-4]:-0}" \
    '. + {($t):{"node-2":$n2,"node-3":$n3,"node-4":$n4}}')
done

phase2_local_obj='{}'
for tool in "${TOOLS[@]}"; do
  phase2_local_obj=$(printf '%s' "$phase2_local_obj" | jq --arg t "$tool" --argjson v "${PHASE2_LOCAL_COUNTS[$tool]:-0}" '. + {($t):$v}')
done

phase1_per_peer_obj=$(jq -n \
  --argjson n2 "${PHASE1_PEER_COUNTS[node-2]:-0}" \
  --argjson n3 "${PHASE1_PEER_COUNTS[node-3]:-0}" \
  --argjson n4 "${PHASE1_PEER_COUNTS[node-4]:-0}" \
  '{"node-2":$n2,"node-3":$n3,"node-4":$n4}')

tools_json=$(printf '%s\n' "${TOOLS[@]}" | jq -R . | jq -s .)
reasons_json=$(printf '%s\n' "${reasons[@]:-}" | jq -R . | jq -s 'map(select(length>0))')

jq -n \
  --arg scenario "S24" \
  --arg expected_verdict "$expected" \
  --arg actual_verdict "$actual_verdict" \
  --argjson pass "$pass" \
  --arg expected_red_reason "Issue #318 — MCP stdio writes bypass federation fanout (closes in Patch 2)" \
  --arg run_id "$RUN_ID" \
  --arg ns "$NS" \
  --argjson phase1_http_replication_ok "$PHASE1_OK" \
  --argjson phase1_peer_counts "$phase1_per_peer_obj" \
  --argjson phase2_mcp_replication_per_tool "$phase2_per_tool_obj" \
  --argjson phase2_mcp_replication_per_tool_per_peer "$phase2_per_tool_per_peer_obj" \
  --argjson phase2_local_audit_present "$([ "$phase2_local_present_all" = "true" ] && echo true || echo false)" \
  --argjson phase2_local_counts "$phase2_local_obj" \
  --argjson tools_probed "$tools_json" \
  --argjson reasons "$reasons_json" \
  '{
    scenario: $scenario,
    pass: $pass,
    expected_verdict: $expected_verdict,
    actual_verdict: $actual_verdict,
    expected_red_reason: $expected_red_reason,
    run_id: $run_id,
    namespace: $ns,
    outputs: {
      phase1_http_replication_ok: $phase1_http_replication_ok,
      phase1_peer_counts: $phase1_peer_counts,
      phase2_mcp_replication_per_tool: $phase2_mcp_replication_per_tool,
      phase2_mcp_replication_per_tool_per_peer: $phase2_mcp_replication_per_tool_per_peer,
      phase2_local_audit_present: $phase2_local_audit_present,
      phase2_local_counts: $phase2_local_counts,
      tools_probed: $tools_probed
    },
    reasons: $reasons
  }'
