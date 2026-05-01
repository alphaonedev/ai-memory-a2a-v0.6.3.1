#!/usr/bin/env bash
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
#
# drive_agent_autonomous.sh — Phase 3 autonomous agent driver.
#
# Contract (per scripts/phase3_autonomous.py::_run_droplet):
#   stdin  : UTF-8 prompt string (the full Phase 3 turn prompt)
#   stdout : a single §7-shaped JSON object with at minimum:
#              {"tools_called":[...], "ai_memory_ops":[...],
#               "termination_reason":"...", "notes":"..."}
#   exit   : 0 on every clean run (failures are reported in JSON, not exit code)
#
# Required env (caller-supplied):
#   AI_MEMORY_ARM       — cold | isolated | stubbed | treatment
#   AI_MEMORY_NS_PREFIX — namespace prefix for "isolated" arm; empty otherwise
#   AI_MEMORY_FEDERATED — 0|1
#   AI_MEMORY_USE_STUB  — 0|1
#   AGENT_ID            — ai:alice | ai:bob
#   PHASE3_SCENARIO     — A|B|C|D
#   PHASE3_ARM          — cold|isolated|stubbed|treatment
#   PHASE3_RUN          — 1|2|3
#   LLM_MODEL_SKU       — exact SKU string
#
# Required env (sourced from /etc/ai-memory-a2a/env, written by setup_node.sh):
#   AGENT_TYPE          — ironclaw | hermes (only these are in scope for v0.6.3.1)
#   LOCAL_MEMORY_URL    — http(s)://127.0.0.1:9077
#   MCP_CONFIG          — /etc/ai-memory-a2a/mcp-config/config.json
#
# This script is intentionally self-contained: no project-path imports,
# no Python except for the optional in-process stub server (stubbed arm).
# Runs as root on the agent droplet via ssh.

set -uo pipefail
# NOTE: -e is intentionally OFF. We must always emit a JSON record on
# stdout and exit 0 even if the agent CLI fails — `set -e` would
# short-circuit error-recovery paths that are part of the contract.

# ---------------------------------------------------------------------------
# 1. Source env. If the env file is missing, that is a hard misconfig at
#    provisioning time, but we still need to emit valid JSON + exit 0.
# ---------------------------------------------------------------------------
emit_error_json() {
  local reason="$1"
  local note="${2:-}"
  # jq -n builds the JSON with proper escaping of the note string.
  jq -cn \
    --arg reason "$reason" \
    --arg note "$note" \
    '{tools_called:[], ai_memory_ops:[], termination_reason:$reason, notes:$note}'
  exit 0
}

if [ ! -r /etc/ai-memory-a2a/env ]; then
  emit_error_json "error" "drive_agent_autonomous: /etc/ai-memory-a2a/env missing"
fi
# shellcheck disable=SC1091
source /etc/ai-memory-a2a/env

# ---------------------------------------------------------------------------
# 2. Validate AGENT_TYPE — only ironclaw + hermes are in scope for v0.6.3.1.
# ---------------------------------------------------------------------------
case "${AGENT_TYPE:-}" in
  ironclaw|hermes) ;;
  *)
    emit_error_json "error" "drive_agent_autonomous: AGENT_TYPE=${AGENT_TYPE:-unset} not in {ironclaw,hermes}"
    ;;
esac

# Required jq for everything below.
if ! command -v jq >/dev/null 2>&1; then
  emit_error_json "error" "drive_agent_autonomous: jq not on PATH"
fi

# ---------------------------------------------------------------------------
# 3. Compute a unique session marker for this run.
# ---------------------------------------------------------------------------
SCEN="${PHASE3_SCENARIO:-X}"
ARM="${PHASE3_ARM:-${AI_MEMORY_ARM:-unset}}"
RUN="${PHASE3_RUN:-0}"
SESSION_MARKER="phase3_${SCEN}_${ARM}_r${RUN}_$(date +%s%N 2>/dev/null || date +%s)"
TMPDIR_RUN="/tmp/${SESSION_MARKER}"
mkdir -p "$TMPDIR_RUN" 2>/dev/null || true

# Cleanup hook so we don't leak per-run files. We keep stderr/stdout
# of the agent CLI under TMPDIR_RUN until we've parsed them.
cleanup() {
  # Stop the stubbed-arm Python server if we started one.
  if [ -n "${STUB_PID:-}" ] && kill -0 "$STUB_PID" 2>/dev/null; then
    kill "$STUB_PID" 2>/dev/null || true
  fi
  rm -rf "$TMPDIR_RUN" 2>/dev/null || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 4. Read the prompt off stdin into a variable. Read FIRST so we still
#    own stdin when later steps run sub-commands.
# ---------------------------------------------------------------------------
PROMPT="$(cat)"

# ---------------------------------------------------------------------------
# 5. Configure MCP per arm. We write a per-run MCP config under
#    $TMPDIR_RUN/mcp-config.json and point the agent at it via
#    AGENT-specific config knobs.
# ---------------------------------------------------------------------------
RUN_MCP_CONFIG="$TMPDIR_RUN/mcp-config.json"
ARM_NOTE=""

# Helper: read the existing MCP config, with safe fallback. The config
# we ship via setup_node.sh registers a single "memory" server pointing
# at `ai-memory ... mcp`. We modify it per-arm.
default_memory_block() {
  cat <<'JSON'
{
  "command": "ai-memory",
  "args": ["--db", "/var/lib/ai-memory/a2a.db", "mcp"],
  "env": {}
}
JSON
}

case "$AI_MEMORY_ARM" in
  cold)
    # ai-memory tool removed entirely from the agent's MCP surface.
    echo '{"mcpServers": {}}' > "$RUN_MCP_CONFIG"
    ARM_NOTE="arm=cold; ai-memory MCP server removed"
    ;;

  isolated)
    # ai-memory enabled, but the namespace prefix is FORCED via env so
    # any write/recall the agent issues lands under <agent_id>/ scope.
    # GAP: ai-memory v0.6.3.1 does NOT advertise a `--namespace-prefix`
    # CLI flag (see setup_node.sh: `ai-memory --db ... mcp --tier ...`).
    # We pass AI_MEMORY_NAMESPACE_PREFIX as an env var on the spawned
    # MCP subprocess; if ai-memory v0.6.3.1 doesn't honor that env, the
    # isolation guarantee degrades to "agents see each other unless
    # they explicitly pick distinct namespaces in the prompt." The
    # arm-vs-arm comparison (treatment minus isolated) becomes noisy
    # rather than null in that case. TODO: confirm ai-memory honors
    # AI_MEMORY_NAMESPACE_PREFIX or add a wrapper that rewrites
    # JSON-RPC tool args inline before passing them to ai-memory mcp.
    if [ -r "${MCP_CONFIG:-/etc/ai-memory-a2a/mcp-config/config.json}" ]; then
      jq --arg ns "${AI_MEMORY_NS_PREFIX:-}" \
         '.mcpServers.memory.env.AI_MEMORY_NAMESPACE_PREFIX = $ns
          | .mcpServers.memory.env.AI_MEMORY_AGENT_ID = (.mcpServers.memory.env.AI_MEMORY_AGENT_ID // env.AGENT_ID)' \
         "$MCP_CONFIG" > "$RUN_MCP_CONFIG" 2>/dev/null
    fi
    if [ ! -s "$RUN_MCP_CONFIG" ]; then
      jq -n --arg ns "${AI_MEMORY_NS_PREFIX:-}" --arg aid "$AGENT_ID" \
        '{mcpServers:{memory:{command:"ai-memory",
                               args:["--db","/var/lib/ai-memory/a2a.db","mcp"],
                               env:{AI_MEMORY_AGENT_ID:$aid,
                                    AI_MEMORY_NAMESPACE_PREFIX:$ns}}}}' \
        > "$RUN_MCP_CONFIG"
    fi
    ARM_NOTE="arm=isolated; ns_prefix=${AI_MEMORY_NS_PREFIX:-}; namespace-prefix support in ai-memory v0.6.3.1 unverified (TODO)"
    ;;

  stubbed)
    # In-process Python dict stub. The MCP tool dispatches to a tiny
    # JSON-RPC stdio server we write here. Persists ONLY within this run.
    if ! command -v python3 >/dev/null 2>&1; then
      emit_error_json "error" "stubbed arm requires python3 on droplet"
    fi
    STUB_PY="$TMPDIR_RUN/ai_memory_stub.py"
    cat > "$STUB_PY" <<'PYEOF'
#!/usr/bin/env python3
# Phase 3 "stubbed" arm — minimal in-process MCP stdio server.
# Speaks just enough JSON-RPC 2.0 to satisfy ironclaw + hermes
# tool-dispatch for memory_store / memory_recall / memory_list.
# State lives in a single dict; lost when the process exits.
# This is a substitute for ai-memory's distinctive features
# (federation, persistence, scope, audit) — see governance §6.2.
import json, sys, hashlib, time

STORE = {}  # (namespace, title) -> {"content": str, "ts": int}

def _ok(req_id, result):
    sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": req_id, "result": result}) + "\n")
    sys.stdout.flush()

def _err(req_id, code, msg):
    sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": req_id,
                                  "error": {"code": code, "message": msg}}) + "\n")
    sys.stdout.flush()

TOOLS = [
    {"name": "memory_store",
     "description": "Store a memory (stub).",
     "inputSchema": {"type": "object", "properties": {
         "namespace": {"type": "string"}, "title": {"type": "string"},
         "content": {"type": "string"}}}},
    {"name": "memory_recall",
     "description": "Recall memories (stub).",
     "inputSchema": {"type": "object", "properties": {
         "namespace": {"type": "string"}, "query": {"type": "string"}}}},
    {"name": "memory_list",
     "description": "List memories (stub).",
     "inputSchema": {"type": "object", "properties": {
         "namespace": {"type": "string"}}}},
]

def handle(msg):
    method = msg.get("method", "")
    rid = msg.get("id")
    params = msg.get("params") or {}
    if method == "initialize":
        _ok(rid, {"protocolVersion": "2024-11-05",
                   "serverInfo": {"name": "ai-memory-stub", "version": "phase3"},
                   "capabilities": {"tools": {}}})
    elif method == "tools/list":
        _ok(rid, {"tools": TOOLS})
    elif method == "tools/call":
        name = params.get("name", "")
        args = params.get("arguments", {}) or {}
        ns = str(args.get("namespace") or "default")
        if name == "memory_store":
            title = str(args.get("title") or "untitled")
            content = str(args.get("content") or "")
            STORE[(ns, title)] = {"content": content, "ts": int(time.time())}
            _ok(rid, {"content": [{"type": "text",
                                     "text": json.dumps({"ok": True, "namespace": ns, "title": title,
                                                          "sha256": hashlib.sha256(content.encode("utf-8")).hexdigest()})}]})
        elif name == "memory_recall":
            q = str(args.get("query") or "")
            hits = [{"namespace": k[0], "title": k[1], "content": v["content"]}
                    for k, v in STORE.items() if k[0] == ns and (q in k[1] or q in v["content"])]
            _ok(rid, {"content": [{"type": "text",
                                     "text": json.dumps({"memories": hits})}]})
        elif name == "memory_list":
            hits = [{"namespace": k[0], "title": k[1], "content": v["content"]}
                    for k, v in STORE.items() if k[0] == ns]
            _ok(rid, {"content": [{"type": "text",
                                     "text": json.dumps({"memories": hits})}]})
        else:
            _err(rid, -32601, f"unknown tool: {name}")
    elif method == "notifications/initialized":
        # No response for notifications.
        pass
    else:
        if rid is not None:
            _err(rid, -32601, f"unknown method: {method}")

def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        try:
            handle(msg)
        except Exception as e:
            if isinstance(msg, dict) and msg.get("id") is not None:
                _err(msg["id"], -32603, f"stub internal error: {e}")

if __name__ == "__main__":
    main()
PYEOF
    chmod +x "$STUB_PY"
    jq -n --arg py "$STUB_PY" --arg aid "$AGENT_ID" \
      '{mcpServers:{memory:{command:"python3",
                             args:[$py],
                             env:{AI_MEMORY_AGENT_ID:$aid}}}}' \
      > "$RUN_MCP_CONFIG"
    ARM_NOTE="arm=stubbed; in-process python dict at $STUB_PY"
    ;;

  treatment)
    # Live ai-memory at LOCAL_MEMORY_URL with full federation. Use the
    # MCP_CONFIG that setup_node.sh wrote, unchanged.
    if [ -r "${MCP_CONFIG:-/etc/ai-memory-a2a/mcp-config/config.json}" ]; then
      cp "${MCP_CONFIG}" "$RUN_MCP_CONFIG"
    else
      jq -n --arg aid "$AGENT_ID" \
        '{mcpServers:{memory:{command:"ai-memory",
                               args:["--db","/var/lib/ai-memory/a2a.db","mcp"],
                               env:{AI_MEMORY_AGENT_ID:$aid}}}}' \
        > "$RUN_MCP_CONFIG"
    fi
    ARM_NOTE="arm=treatment; live ai-memory @ ${LOCAL_MEMORY_URL:-unset}; federated=${AI_MEMORY_FEDERATED:-0}"
    ;;

  *)
    emit_error_json "error" "drive_agent_autonomous: unknown AI_MEMORY_ARM=${AI_MEMORY_ARM:-unset}"
    ;;
esac

# ---------------------------------------------------------------------------
# 6. Capture audit-log offset BEFORE invoking the agent. Used in step 8
#    to slice the audit tail to just THIS run's events.
# ---------------------------------------------------------------------------
AUDIT_PRE_FILE="$TMPDIR_RUN/audit_pre.seq"
AUDIT_AVAILABLE=true
# `ai-memory audit tail 1 --format json` is best-effort — older or
# non-treatment configurations may not expose a meaningful audit log.
if ! ai-memory audit tail 1 --format json 2>/dev/null \
     | jq -r '.sequence // empty' \
     > "$AUDIT_PRE_FILE" 2>/dev/null; then
  AUDIT_AVAILABLE=false
fi
if [ ! -s "$AUDIT_PRE_FILE" ]; then
  # Audit either empty or unavailable.
  echo 0 > "$AUDIT_PRE_FILE"
  if [ "$AI_MEMORY_ARM" = "treatment" ] || [ "$AI_MEMORY_ARM" = "isolated" ]; then
    : # legitimate: this is the first event on a fresh node
  fi
fi
AUDIT_PRE_SEQ="$(cat "$AUDIT_PRE_FILE")"

# ---------------------------------------------------------------------------
# 7. Invoke the agent CLI with the prompt; bound by 600s walltime per
#    governance §6.3. Capture exit code + stdout + stderr.
# ---------------------------------------------------------------------------
AGENT_OUT="$TMPDIR_RUN/agent.stdout"
AGENT_ERR="$TMPDIR_RUN/agent.stderr"
AGENT_RC=0
T_START=$(date +%s)

# Export the per-run MCP config to the agent process so ironclaw/hermes
# pick it up if they consult AI_MEMORY_MCP_CONFIG / MCP_CONFIG. We also
# leave the original MCP_CONFIG env in place as a fallback.
export AI_MEMORY_MCP_CONFIG="$RUN_MCP_CONFIG"
export MCP_CONFIG="$RUN_MCP_CONFIG"

case "$AGENT_TYPE" in
  ironclaw)
    # Headless prompt with JSON output and bounded tool rounds. Per
    # docs.ironclaw / setup_node.sh: ironclaw spawns `ai-memory mcp`
    # using the registration written via `ironclaw mcp add memory`.
    # We can't redirect that registration mid-run, but ironclaw also
    # honors AI_MEMORY_MCP_CONFIG/MCP_CONFIG when set in the env.
    # NOTE: if ironclaw v0.x ignores AI_MEMORY_MCP_CONFIG, the cold/
    # stubbed/isolated arm wiring may degrade — TODO: confirm against
    # the running ironclaw version.
    timeout 600 ironclaw run \
      --non-interactive \
      --format json \
      --max-tool-rounds 12 \
      -p "$PROMPT" \
      > "$AGENT_OUT" 2> "$AGENT_ERR"
    AGENT_RC=$?
    ;;

  hermes)
    # Hermes reads XAI_API_KEY from /etc/ai-memory-a2a/hermes.env (per
    # setup_node.sh). Sourcing it scopes the secret to this subshell;
    # we never echo it back out.
    if [ -r /etc/ai-memory-a2a/hermes.env ]; then
      set -a
      # shellcheck disable=SC1091
      . /etc/ai-memory-a2a/hermes.env
      set +a
    fi
    timeout 600 hermes chat -Q \
      --provider xai \
      --model "${LLM_MODEL_SKU:-grok-4-fast-non-reasoning}" \
      -q "$PROMPT" \
      > "$AGENT_OUT" 2> "$AGENT_ERR"
    AGENT_RC=$?
    ;;
esac

T_END=$(date +%s)
WALL_SECS=$(( T_END - T_START ))

# ---------------------------------------------------------------------------
# Translate exit code → termination_reason.
# 124 is GNU coreutils' `timeout` exit code.
# ---------------------------------------------------------------------------
TERMINATION=""
if [ "$AGENT_RC" -eq 124 ]; then
  TERMINATION="cap_reached_walltime"
elif [ "$AGENT_RC" -ne 0 ]; then
  TERMINATION="error"
else
  TERMINATION="task_complete"
fi

# ---------------------------------------------------------------------------
# 8. Diff the audit log to extract THIS run's ai-memory ops. We map
#    each post-pre audit entry into a §7 ai_memory_ops[] item.
#
# Audit schema fields we depend on (per docs/security/audit-trail.md
# and S13/contract.md): sequence, timestamp, actor, action, target,
# scope, transport, payload, payload_size, duration_ms, ok.
# Older builds may use slightly different names; the jq mapping is
# defensive and falls back to empty strings / 0 / true rather than
# failing loudly.
# ---------------------------------------------------------------------------
AI_MEMORY_OPS_JSON="[]"
if [ "$AUDIT_AVAILABLE" = "true" ] && [ "$AI_MEMORY_ARM" != "cold" ] && [ "$AI_MEMORY_ARM" != "stubbed" ]; then
  AUDIT_POST_FILE="$TMPDIR_RUN/audit_post.jsonl"
  # Pull a generous tail; we slice by sequence > pre below. 500 covers
  # the §6.3 cap (50 ops * 12 turns = 600 worst-case) for one agent.
  if ai-memory audit tail 500 --format json > "$AUDIT_POST_FILE" 2>/dev/null; then
    # Some ai-memory versions emit one JSON record per line; others
    # emit a single JSON array. We try both shapes.
    NEW_EVENTS_FILE="$TMPDIR_RUN/audit_new.jsonl"
    if jq -e 'type == "array"' "$AUDIT_POST_FILE" >/dev/null 2>&1; then
      jq -c --argjson pre "${AUDIT_PRE_SEQ:-0}" \
        '.[] | select((.sequence // 0) > $pre)' \
        "$AUDIT_POST_FILE" > "$NEW_EVENTS_FILE" 2>/dev/null || true
    else
      # JSONL — one record per line.
      jq -c --argjson pre "${AUDIT_PRE_SEQ:-0}" \
        'select((.sequence // 0) > $pre)' \
        "$AUDIT_POST_FILE" > "$NEW_EVENTS_FILE" 2>/dev/null || true
    fi

    # Map each audit entry to a §7 ai_memory_ops item. Field names
    # below tolerate either v0.6.3.1's canonical schema or older
    # variants (.action vs .op, .target vs .target_key, etc.).
    if [ -s "$NEW_EVENTS_FILE" ]; then
      AI_MEMORY_OPS_JSON=$(jq -cs '
        map({
          op: ((.action // .op // "write")
               | if . == "store" or . == "memory_store" then "write"
                 elif . == "query" or . == "memory_recall" then "recall"
                 elif . == "memory_list" then "recall"
                 else . end),
          namespace:        ((.namespace // .scope_namespace // "default") | tostring),
          key_or_query:     ((.target // .target_key // .key // .query // "unknown") | tostring),
          scope:            ((.scope // "team")
                             | if . == "private" or . == "team" or . == "unit" or . == "org" or . == "collective" then . else "team" end),
          transport:        ((.transport // "mcp_stdio")
                             | if . == "http" then "http" else "mcp_stdio" end),
          payload_sha256:   ((.payload_sha256 // .payload_hash // "0000000000000000000000000000000000000000000000000000000000000000") | tostring),
          returned_records: ((.returned_records // .result_count // 0) | tonumber? // 0),
          duration_ms:      ((.duration_ms // 0) | tonumber? // 0),
          ok:               ((.ok // (.error == null) // true))
        })
      ' "$NEW_EVENTS_FILE" 2>/dev/null) || AI_MEMORY_OPS_JSON="[]"
      [ -z "$AI_MEMORY_OPS_JSON" ] && AI_MEMORY_OPS_JSON="[]"
    fi
  fi
fi

# Defensive: ensure AI_MEMORY_OPS_JSON is a JSON array.
if ! echo "$AI_MEMORY_OPS_JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
  AI_MEMORY_OPS_JSON="[]"
fi

# ---------------------------------------------------------------------------
# 9. Tools-called extraction. ironclaw --format json emits a structured
#    trace; hermes does not (as of the v0.6.3.1 baseline). Be honest
#    about what's not exposed: leave [] and explain in `notes`.
# ---------------------------------------------------------------------------
TOOLS_CALLED_JSON="[]"
TOOLS_NOTE=""

case "$AGENT_TYPE" in
  ironclaw)
    # Best effort: try to find a tool-trace array in the JSON output.
    # We accept either top-level .tool_calls[] or nested
    # .turns[].tool_calls[] shapes. If the parse fails, leave []
    # and surface a note.
    if [ -s "$AGENT_OUT" ] && jq -e . "$AGENT_OUT" >/dev/null 2>&1; then
      TOOLS_CALLED_JSON=$(jq -c '
        ( .tool_calls // [.turns? // [] | .[]?.tool_calls // []] | flatten )
        | map({
            tool_name:         ((.name // .tool // "unknown") | tostring),
            args_sha256:       ((.args_sha256 // "0000000000000000000000000000000000000000000000000000000000000000") | tostring),
            args_size_bytes:   ((.args_size_bytes // (.args | tostring | length) // 0) | tonumber? // 0),
            result_sha256:     ((.result_sha256 // "0000000000000000000000000000000000000000000000000000000000000000") | tostring),
            result_size_bytes: ((.result_size_bytes // (.result | tostring | length) // 0) | tonumber? // 0),
            duration_ms:       ((.duration_ms // 0) | tonumber? // 0),
            ok:                ((.ok // (.error == null) // true))
          })
      ' "$AGENT_OUT" 2>/dev/null) || TOOLS_CALLED_JSON="[]"
      [ -z "$TOOLS_CALLED_JSON" ] && TOOLS_CALLED_JSON="[]"
      if ! echo "$TOOLS_CALLED_JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
        TOOLS_CALLED_JSON="[]"
        TOOLS_NOTE="tools_called: ironclaw JSON output did not expose a tool-trace array"
      fi
    else
      TOOLS_NOTE="tools_called: ironclaw stdout was empty or non-JSON"
    fi
    ;;
  hermes)
    # Hermes -Q quiet mode prints just the assistant content; tool
    # traces are not exposed on stdout. The audit log captures the
    # ai-memory side; tools_called[] therefore stays empty and we say so.
    TOOLS_NOTE="tools_called: not exposed by hermes -Q (only ai-memory ops are recoverable, via audit log)"
    ;;
esac

# ---------------------------------------------------------------------------
# 10. Compose the final JSON. Note text is bounded to 500 chars per the
#     §7 schema constraint on `notes`.
# ---------------------------------------------------------------------------
NOTES_FULL="${ARM_NOTE}${TOOLS_NOTE:+ | $TOOLS_NOTE} | wall=${WALL_SECS}s rc=${AGENT_RC} session=${SESSION_MARKER}"
# Truncate to <= 500 chars defensively.
NOTES_TRUNC=$(printf '%s' "$NOTES_FULL" | cut -c1-500)

jq -cn \
  --argjson tools_called "$TOOLS_CALLED_JSON" \
  --argjson ai_memory_ops "$AI_MEMORY_OPS_JSON" \
  --arg termination "$TERMINATION" \
  --arg notes "$NOTES_TRUNC" \
  '{tools_called:$tools_called,
    ai_memory_ops:$ai_memory_ops,
    termination_reason:$termination,
    notes:$notes}'

exit 0
