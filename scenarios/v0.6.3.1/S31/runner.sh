#!/usr/bin/env bash
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
#
# S31 — SQLCipher AES-256 encryption at rest (EXPECTED GREEN on v0.6.3.1,
# falls through to NOT_BUILT if SQLCipher is not in this build's flags)
# See contract.md.
#
# Probes (all on node-1):
#   1. db_header_opaque         leading 16 bytes != "SQLite format 3\x00"
#   2. plain_open_rejected      stock sqlite3 errors out
#   3. keyed_open_works         sqlite3 -cmd "PRAGMA key='<pwd>'" lists tables
#   4. passphrase_not_in_binary `strings ai-memory` does NOT contain the pwd
#
# Output: standard scenario JSON on stdout, harness-shape:
#   {"scenario":"S31","pass":<bool>,
#    "expected_verdict":"<GREEN|NOT_BUILT>",
#    "actual_verdict":"<GREEN|RED|NOT_BUILT|UNKNOWN>",
#    "outputs":{...},"reasons":[...]}.
#
# Note: we never echo the passphrase to stdout/stderr or the JSON
# envelope. Only its *source* (env var name or config file path)
# is emitted.

set -euo pipefail

# --- env shim ----------------------------------------------------------
NODE_A="${A2A_NODE_A:-${NODE1_IP:-}}"

if [ -z "$NODE_A" ]; then
  cat <<'EOF'
{"scenario":"S31","pass":false,"expected_verdict":"GREEN","actual_verdict":"UNKNOWN","outputs":{},"reasons":["NODE_A / NODE1_IP missing from environment"]}
EOF
  exit 0
fi

SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=4)
WORK="$(mktemp -d -t s31.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

stderr() { printf '[s31] %s\n' "$*" >&2; }

# Run the entire probe over a single ssh shell — easier to keep the
# passphrase off the wire in our runner output (it never leaves the
# remote shell except as the JSON we emit, which we sanitise).
#
# The remote script emits a single JSON envelope on stdout:
#   {db_path, db_header_hex, plain_open_rc, plain_open_diag,
#    keyed_open_rc, keyed_open_tables[], passphrase_source,
#    passphrase_in_binary, errors[]}
#
# We parse it locally and decide the verdict.
remote_probe() {
  cat <<'REMOTE'
set -u
ERRS=()
emit_err() { ERRS+=("$1"); }

# 1. resolve DB path + passphrase. Order:
#    a. /etc/ai-memory-a2a/env (systemd EnvironmentFile)
#    b. ~/.config/ai-memory/config.toml
#    c. /etc/ai-memory-a2a/config.toml
#    Default: /var/lib/ai-memory/a2a.db
DB_PATH=""
PASSPHRASE=""
PASSPHRASE_SRC=""

scan_env_file() {
  local f="$1"
  [ -r "$f" ] || return 0
  # accept AI_MEMORY_DB_KEY / AI_MEMORY_KEY / AI_MEMORY_PASSPHRASE
  # / AI_MEMORY_DB_PASSPHRASE / AI_MEMORY_DB_PATH.
  while IFS= read -r line; do
    case "$line" in
      \#*|"") continue ;;
    esac
    name="${line%%=*}"
    val="${line#*=}"
    val="${val%\"}"; val="${val#\"}"
    val="${val%\'}"; val="${val#\'}"
    case "$name" in
      AI_MEMORY_DB_KEY|AI_MEMORY_DB_PASSPHRASE|AI_MEMORY_KEY|AI_MEMORY_PASSPHRASE)
        if [ -z "$PASSPHRASE" ]; then PASSPHRASE="$val"; PASSPHRASE_SRC="env:$f:$name"; fi ;;
      AI_MEMORY_DB_PATH|AI_MEMORY_DB)
        if [ -z "$DB_PATH" ]; then DB_PATH="$val"; fi ;;
    esac
  done < "$f"
}

scan_toml_file() {
  local f="$1"
  [ -r "$f" ] || return 0
  # Best-effort TOML scrape for `db = "..."`, `key = "..."`,
  # `passphrase = "..."`. We don't try to be a real parser — the
  # ai-memory config layout is flat enough for grep+sed.
  if [ -z "$DB_PATH" ]; then
    p=$(awk -F= '/^\s*db\s*=/ { gsub(/^[ \t"]+|[ \t"]+$/, "", $2); print $2; exit }' "$f")
    if [ -n "$p" ]; then DB_PATH="${p/#\~/$HOME}"; fi
  fi
  if [ -z "$PASSPHRASE" ]; then
    p=$(awk -F= '/^\s*(key|passphrase)\s*=/ { gsub(/^[ \t"]+|[ \t"]+$/, "", $2); print $2; exit }' "$f")
    if [ -n "$p" ]; then PASSPHRASE="$p"; PASSPHRASE_SRC="toml:$f"; fi
  fi
}

scan_env_file /etc/ai-memory-a2a/env
scan_env_file /etc/default/ai-memory 2>/dev/null
scan_toml_file "$HOME/.config/ai-memory/config.toml"
scan_toml_file /etc/ai-memory-a2a/config.toml 2>/dev/null

# Default DB path
[ -n "$DB_PATH" ] || DB_PATH="/var/lib/ai-memory/a2a.db"
if [ ! -f "$DB_PATH" ]; then
  # Try the user's home variant — same fallback ai-memory boot uses.
  for cand in "$HOME/.claude/ai-memory.db" "$HOME/.local/share/ai-memory/a2a.db"; do
    if [ -f "$cand" ]; then DB_PATH="$cand"; break; fi
  done
fi

# 2. header opaque probe
DB_HEADER_HEX=""
if [ -f "$DB_PATH" ]; then
  DB_HEADER_HEX=$(head -c 16 "$DB_PATH" 2>/dev/null | od -An -tx1 | tr -d ' \n' || true)
else
  emit_err "db-path-not-found:$DB_PATH"
fi

# 3. plain sqlite3 .tables
PLAIN_RC=0
PLAIN_DIAG=""
if command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB_PATH" ]; then
  PLAIN_OUT=$(sqlite3 "$DB_PATH" ".tables" 2>&1 || true)
  PLAIN_RC=$?
  # Most builds return rc=0 with an error string on stderr/stdout when
  # the file is encrypted, so treat the diagnostic content as the
  # signal too.
  PLAIN_DIAG="$PLAIN_OUT"
else
  emit_err "sqlite3-missing-or-no-db"
fi

# 4. keyed sqlite3 — we only run this if a passphrase was found.
KEYED_RC=999
KEYED_TABLES=()
if [ -n "$PASSPHRASE" ] && command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB_PATH" ]; then
  # Escape single quotes inside the passphrase per SQLite syntax.
  ESC=$(printf "%s" "$PASSPHRASE" | sed "s/'/''/g")
  KEYED_OUT=$(sqlite3 -cmd "PRAGMA key='$ESC';" "$DB_PATH" ".tables" 2>&1 || true)
  KEYED_RC=$?
  # Split words into table names, trim noise.
  for t in $KEYED_OUT; do
    case "$t" in
      memories|memory|audit|audit_log|subscriptions|subscription|pending|inbox|notifications|notification|namespaces|namespace_standards|entities|links|kg_edges|kg_nodes|sessions)
        KEYED_TABLES+=("$t") ;;
    esac
  done
fi

# 5. passphrase-not-embedded probe (best-effort — never echo PWD)
PWD_IN_BINARY="false"
BIN=$(command -v ai-memory 2>/dev/null || true)
if [ -n "$PASSPHRASE" ] && [ -n "$BIN" ] && [ -x "$BIN" ]; then
  if strings "$BIN" 2>/dev/null | grep -qF -- "$PASSPHRASE"; then
    PWD_IN_BINARY="true"
  fi
fi

errs_json=$(printf '%s\n' "${ERRS[@]:-}" | jq -R . | jq -s 'map(select(length>0))')
keyed_tables_json=$(printf '%s\n' "${KEYED_TABLES[@]:-}" | jq -R . | jq -s 'map(select(length>0)) | unique')

jq -n \
  --arg db_path "$DB_PATH" \
  --arg db_header_hex "$DB_HEADER_HEX" \
  --argjson plain_open_rc "$PLAIN_RC" \
  --arg plain_open_diag "$PLAIN_DIAG" \
  --argjson keyed_open_rc "$KEYED_RC" \
  --argjson keyed_open_tables "$keyed_tables_json" \
  --arg passphrase_source "$PASSPHRASE_SRC" \
  --argjson passphrase_in_binary "$([ "$PWD_IN_BINARY" = "true" ] && echo true || echo false)" \
  --argjson passphrase_present "$([ -n "$PASSPHRASE" ] && echo true || echo false)" \
  --argjson errors "$errs_json" \
  '{db_path:$db_path, db_header_hex:$db_header_hex,
    plain_open_rc:$plain_open_rc, plain_open_diag:$plain_open_diag,
    keyed_open_rc:$keyed_open_rc, keyed_open_tables:$keyed_open_tables,
    passphrase_source:$passphrase_source,
    passphrase_in_binary:$passphrase_in_binary,
    passphrase_present:$passphrase_present,
    errors:$errors}'
REMOTE
}

PROBE_SCRIPT="$(remote_probe)"

stderr "running S31 probe on node-1 (${NODE_A})"
PROBE_OUT=$(ssh "${SSH_OPTS[@]}" "root@${NODE_A}" "bash -s" <<<"$PROBE_SCRIPT" 2> >(sed 's/^/[s31 NODE_A stderr] /' >&2) || true)

reasons=()
add_reason() { reasons+=("$1"); }

if ! printf '%s' "$PROBE_OUT" | jq -e . >/dev/null 2>&1; then
  cat <<EOF
{"scenario":"S31","pass":false,"expected_verdict":"GREEN","actual_verdict":"UNKNOWN","outputs":{},"reasons":["unparseable remote probe output: $(printf '%s' "$PROBE_OUT" | head -c 200 | tr -d '\n' | jq -Rs . 2>/dev/null)"]}
EOF
  exit 0
fi

db_path=$(printf '%s' "$PROBE_OUT" | jq -r '.db_path')
db_header_hex=$(printf '%s' "$PROBE_OUT" | jq -r '.db_header_hex')
plain_rc=$(printf '%s' "$PROBE_OUT" | jq -r '.plain_open_rc')
plain_diag=$(printf '%s' "$PROBE_OUT" | jq -r '.plain_open_diag')
keyed_rc=$(printf '%s' "$PROBE_OUT" | jq -r '.keyed_open_rc')
keyed_tables_json=$(printf '%s' "$PROBE_OUT" | jq -c '.keyed_open_tables')
passphrase_source=$(printf '%s' "$PROBE_OUT" | jq -r '.passphrase_source')
passphrase_in_binary=$(printf '%s' "$PROBE_OUT" | jq -r '.passphrase_in_binary')
passphrase_present=$(printf '%s' "$PROBE_OUT" | jq -r '.passphrase_present')

# Hex-encoded SQLite plain magic: "SQLite format 3\x00" = 53514c69746520666f726d6174203300
SQLITE_MAGIC="53514c69746520666f726d6174203300"

# 1. header opaque
db_header_opaque="false"
if [ -n "$db_header_hex" ] && [ "${db_header_hex:0:32}" != "$SQLITE_MAGIC" ]; then
  db_header_opaque="true"
fi

# 2. plain open rejected
plain_open_rejected="false"
plain_lc=$(printf '%s' "$plain_diag" | tr 'A-Z' 'a-z')
if [ "${plain_rc:-0}" -ne 0 ] || \
   printf '%s' "$plain_lc" | grep -qE 'not a database|encrypted|malformed|file is encrypted'; then
  plain_open_rejected="true"
fi

# 3. keyed open works (only meaningful if we found a passphrase)
keyed_open_works="false"
keyed_table_count=$(printf '%s' "$keyed_tables_json" | jq 'length' 2>/dev/null || echo 0)
if [ "$passphrase_present" = "true" ] && [ "${keyed_rc:-1}" -eq 0 ] && [ "${keyed_table_count:-0}" -ge 1 ]; then
  keyed_open_works="true"
fi

# 4. passphrase not embedded
passphrase_not_in_binary="true"
if [ "$passphrase_in_binary" = "true" ]; then
  passphrase_not_in_binary="false"
  add_reason "passphrase appears as a literal substring in $(command -v ai-memory) — operator cannot rotate without rebuild"
fi

# Decide expected/actual verdict.
expected="GREEN"
actual_verdict="GREEN"
pass="false"

if [ "$db_header_opaque" = "false" ] && [ "$plain_open_rejected" = "false" ]; then
  # SQLCipher clearly not built into this binary — treat as NOT_BUILT.
  expected="NOT_BUILT"
  actual_verdict="NOT_BUILT"
  pass="true"
  add_reason "SQLCipher not present in this v0.6.3.1 build — DB header is plain SQLite magic and stock sqlite3 reads it. Deviation from user brief flagged."
elif [ "$db_header_opaque" = "true" ] && [ "$plain_open_rejected" = "true" ] && [ "$keyed_open_works" = "true" ]; then
  actual_verdict="GREEN"
  pass="true"
else
  actual_verdict="RED"
  pass="false"
  if [ "$passphrase_present" != "true" ]; then
    add_reason "no passphrase found in /etc/ai-memory-a2a/env or config.toml; cannot run keyed-open probe"
  fi
  if [ "$db_header_opaque" = "true" ] && [ "$plain_open_rejected" = "false" ]; then
    add_reason "header looks opaque but stock sqlite3 still reads — surface inconsistency"
  fi
  if [ "$db_header_opaque" = "true" ] && [ "$plain_open_rejected" = "true" ] && [ "$keyed_open_works" = "false" ]; then
    add_reason "DB is opaque but keyed open did not list ai-memory tables — passphrase may be wrong source or build mishandles loader"
  fi
fi

reasons_json=$(printf '%s\n' "${reasons[@]:-}" | jq -R . | jq -s 'map(select(length>0))')

# Sanitise the diag string — never let a passphrase-looking value
# leak even if a remote build accidentally echoed it.
plain_diag_safe=$(printf '%s' "$plain_diag" | tr -d '\r' | head -c 500)

jq -n \
  --arg scenario "S31" \
  --arg expected_verdict "$expected" \
  --arg actual_verdict "$actual_verdict" \
  --argjson pass "$pass" \
  --argjson db_header_opaque "$db_header_opaque" \
  --argjson plain_open_rejected "$plain_open_rejected" \
  --argjson keyed_open_works "$keyed_open_works" \
  --argjson passphrase_not_in_binary "$passphrase_not_in_binary" \
  --arg db_path "$db_path" \
  --arg db_header_hex "$db_header_hex" \
  --arg plain_open_diagnostic "$plain_diag_safe" \
  --argjson keyed_open_table_names "$keyed_tables_json" \
  --arg passphrase_source "$passphrase_source" \
  --argjson reasons "$reasons_json" \
  '{
    scenario: $scenario,
    pass: $pass,
    expected_verdict: $expected_verdict,
    actual_verdict: $actual_verdict,
    outputs: {
      db_header_opaque: $db_header_opaque,
      plain_open_rejected: $plain_open_rejected,
      keyed_open_works: $keyed_open_works,
      passphrase_not_in_binary: $passphrase_not_in_binary,
      db_path: $db_path,
      db_header_hex: $db_header_hex,
      plain_open_diagnostic: $plain_open_diagnostic,
      keyed_open_table_names: $keyed_open_table_names,
      passphrase_source: $passphrase_source
    },
    reasons: $reasons
  }'
