#!/usr/bin/env bash
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
#
# S23 — Issue #507 ~ expansion in db field (EXPECTED RED on v0.6.3.1)
# See contract.md.
#
# For each of the 4 nodes:
#   1. ssh in, write two config.toml variants under ~/.config/ai-memory/:
#        - config.toml.tilde       db = "~/.claude/ai-memory.db"
#        - config.toml.absolute    db = "$HOME/.claude/ai-memory.db" (resolved)
#   2. Activate tilde, run `ai-memory boot --format json --quiet`, capture
#      status + .db field. On v0.6.3.1 the bug surfaces as status=warn /
#      a "db unavailable" diagnostic + literal '~' in the .db field.
#   3. Activate absolute, re-run boot. Expect status=ok (control case).
#   4. Optional: doctor on tilde + absolute (CRIT vs OK Storage).
#   5. Restore the original config.toml (non-destructive).
#
# Output: standard scenario JSON on stdout, harness-shape:
#   {"scenario":"S23","pass":<bool>,"expected_verdict":"RED",
#    "actual_verdict":"<RED|GREEN>","outputs":{...},"reasons":[...]}.
#
# pass == (actual_verdict == expected_verdict). On v0.6.3.1 the bug is
# expected to manifest, so actual_verdict=RED => pass=true. If the bug
# is silently fixed (boot returns ok with tilde config on every node) we
# emit actual_verdict=GREEN and pass=false — signalling either the bug
# was patched or the harness has drifted.

set -euo pipefail

# --- env shim ----------------------------------------------------------
# Prefer A2A_NODE_A/B/C/D; fall back to NODE{1..4}_IP from the workflow.
NODE_A="${A2A_NODE_A:-${NODE1_IP:-}}"
NODE_B="${A2A_NODE_B:-${NODE2_IP:-}}"
NODE_C="${A2A_NODE_C:-${NODE3_IP:-}}"
NODE_D="${A2A_NODE_D:-${NODE4_IP:-${MEMORY_NODE_IP:-}}}"

if [ -z "$NODE_A" ] || [ -z "$NODE_B" ] || [ -z "$NODE_C" ] || [ -z "$NODE_D" ]; then
  cat <<'EOF'
{"scenario":"S23","pass":false,"expected_verdict":"RED","actual_verdict":"UNKNOWN","outputs":{},"reasons":["one or more node IPs missing from environment (A2A_NODE_A..D / NODE1_IP..NODE4_IP)"]}
EOF
  exit 0
fi

NODES=("node-1:$NODE_A" "node-2:$NODE_B" "node-3:$NODE_C" "node-4:$NODE_D")

SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=4)

# Per-node working artefacts live in /tmp/s23-<node>-* on the runner.
WORK="$(mktemp -d -t s23.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# Per-node boot output collected here.
declare -A TILDE_STATUS
declare -A TILDE_DB_FIELD
declare -A TILDE_DB_LITERAL_TILDE
declare -A ABSOLUTE_STATUS
declare -A TILDE_DOCTOR_STORAGE
declare -A ABSOLUTE_DOCTOR_STORAGE
declare -A NODE_REASONS

stderr() { printf '[s23] %s\n' "$*" >&2; }

# Run a remote shell snippet on a node. Captures stdout to file; returns
# the remote exit code. Stderr is piped through to our stderr (visible
# in the workflow's "Run scenarios" log group).
ssh_capture() {
  local node_ip="$1"; shift
  local out_file="$1"; shift
  local script="$1"; shift
  if ssh "${SSH_OPTS[@]}" "root@${node_ip}" "bash -s" <<<"$script" >"$out_file" 2> >(sed "s/^/[s23 ${node_ip} stderr] /" >&2); then
    return 0
  else
    return $?
  fi
}

# Per-node probe — runs entirely on the droplet over ssh. We push a
# heredoc'd bash snippet that:
#   1. saves the current ~/.config/ai-memory/config.toml (if any) to .bak;
#   2. writes config.toml.tilde + config.toml.absolute beside it;
#   3. activates tilde via ln -sf, runs boot (capture JSON);
#   4. activates absolute via ln -sf, runs boot (capture JSON);
#   5. activates tilde, runs doctor (capture JSON);
#   6. activates absolute, runs doctor (capture JSON);
#   7. restores original config.toml from .bak.
#
# All four captured JSON blobs are emitted as a single envelope:
#   {"tilde_boot":{...}, "absolute_boot":{...},
#    "tilde_doctor":{...}, "absolute_doctor":{...},
#    "errors":[...]}
remote_probe_script() {
  cat <<'REMOTE'
set -u
ERRS=()
emit_err() { ERRS+=("$1"); }

CFG_DIR="$HOME/.config/ai-memory"
mkdir -p "$CFG_DIR" 2>/dev/null || true
CFG="$CFG_DIR/config.toml"
BAK="$CFG_DIR/config.toml.s23.bak"
TILDE="$CFG_DIR/config.toml.tilde"
ABSOLUTE="$CFG_DIR/config.toml.absolute"

# Snapshot original (handles symlink + regular file + missing).
if [ -L "$CFG" ] || [ -f "$CFG" ]; then
  if [ -L "$CFG" ]; then
    ORIG_TARGET=$(readlink "$CFG" 2>/dev/null || true)
    rm -f "$BAK.symlink" 2>/dev/null || true
    printf '%s\n' "$ORIG_TARGET" > "$BAK.symlink"
  else
    cp -p "$CFG" "$BAK" 2>/dev/null || emit_err "snapshot-failed"
  fi
fi

DB_PATH_ABS="$HOME/.claude/ai-memory.db"
mkdir -p "$HOME/.claude" 2>/dev/null || true

cat > "$TILDE" <<TOML
# S23 probe — tilde form (#507 surface)
db = "~/.claude/ai-memory.db"
TOML

cat > "$ABSOLUTE" <<TOML
# S23 probe — absolute form (control)
db = "${DB_PATH_ABS}"
TOML

run_boot() {
  # Returns JSON object on stdout (or {"error":"..."} on failure).
  # We tolerate older binaries that don't honour --quiet by stripping
  # any leading non-{ noise. timeout 30s is generous on a 4GB droplet.
  local raw rc
  raw=$(timeout 30 ai-memory boot --format json --quiet 2>/dev/null || true)
  rc=$?
  if [ -z "$raw" ]; then
    printf '{"error":"empty-boot-output","rc":%d}' "$rc"
    return
  fi
  # Try to extract the first { ... } JSON object (some builds write a
  # banner before the JSON even with --quiet).
  local cleaned
  cleaned=$(printf '%s' "$raw" | awk 'f{print} /^{/{f=1; print}' | head -200)
  if [ -z "$cleaned" ]; then
    cleaned="$raw"
  fi
  if printf '%s' "$cleaned" | jq -e . >/dev/null 2>&1; then
    printf '%s' "$cleaned"
  else
    # Encode raw output as a JSON string so the runner can still see it.
    printf '{"error":"unparseable-boot-output","raw":%s}' "$(printf '%s' "$raw" | jq -Rs .)"
  fi
}

run_doctor() {
  local raw rc
  raw=$(timeout 30 ai-memory doctor --format json 2>/dev/null || true)
  rc=$?
  if [ -z "$raw" ]; then
    printf '{"error":"empty-doctor-output","rc":%d}' "$rc"
    return
  fi
  local cleaned
  cleaned=$(printf '%s' "$raw" | awk 'f{print} /^{/{f=1; print}' | head -500)
  if [ -z "$cleaned" ]; then cleaned="$raw"; fi
  if printf '%s' "$cleaned" | jq -e . >/dev/null 2>&1; then
    printf '%s' "$cleaned"
  else
    printf '{"error":"unparseable-doctor-output","raw":%s}' "$(printf '%s' "$raw" | jq -Rs .)"
  fi
}

# Phase A — tilde form active
ln -sf "$TILDE" "$CFG"
TILDE_BOOT=$(run_boot)
TILDE_DOCTOR=$(run_doctor)

# Phase B — absolute form active
ln -sf "$ABSOLUTE" "$CFG"
ABS_BOOT=$(run_boot)
ABS_DOCTOR=$(run_doctor)

# Restore original config (best-effort, non-destructive).
rm -f "$CFG" 2>/dev/null || true
if [ -f "$BAK.symlink" ]; then
  ORIG_TARGET=$(cat "$BAK.symlink")
  if [ -n "$ORIG_TARGET" ]; then
    ln -sf "$ORIG_TARGET" "$CFG" 2>/dev/null || emit_err "restore-symlink-failed"
  fi
  rm -f "$BAK.symlink"
elif [ -f "$BAK" ]; then
  cp -p "$BAK" "$CFG" 2>/dev/null || emit_err "restore-copy-failed"
  rm -f "$BAK"
fi
# Probe variant files left in place: config.toml.tilde / .absolute.
# They are inert without the symlink and aid manual repro if needed.

# Emit the envelope as compact JSON.
errs_json=$(printf '%s\n' "${ERRS[@]:-}" | jq -R . | jq -s 'map(select(length>0))')
jq -n \
  --argjson tb "$TILDE_BOOT" \
  --argjson ab "$ABS_BOOT" \
  --argjson td "$TILDE_DOCTOR" \
  --argjson ad "$ABS_DOCTOR" \
  --argjson errs "$errs_json" \
  '{tilde_boot:$tb, absolute_boot:$ab, tilde_doctor:$td, absolute_doctor:$ad, errors:$errs}'
REMOTE
}

stderr "begin S23 probe across 4 nodes"
PROBE_SCRIPT="$(remote_probe_script)"

for entry in "${NODES[@]}"; do
  name="${entry%%:*}"
  ip="${entry##*:}"
  out_file="$WORK/${name}.json"
  stderr "probing ${name} (${ip})"
  if ! ssh_capture "$ip" "$out_file" "$PROBE_SCRIPT"; then
    rc=$?
    stderr "  ssh-probe failed on ${name} rc=${rc}"
    NODE_REASONS["$name"]="ssh-probe-failed-rc-${rc}"
    TILDE_STATUS["$name"]="error"
    ABSOLUTE_STATUS["$name"]="error"
    TILDE_DB_FIELD["$name"]=""
    TILDE_DB_LITERAL_TILDE["$name"]="false"
    TILDE_DOCTOR_STORAGE["$name"]="error"
    ABSOLUTE_DOCTOR_STORAGE["$name"]="error"
    continue
  fi

  if ! jq -e . "$out_file" >/dev/null 2>&1; then
    stderr "  unparseable envelope from ${name}"
    NODE_REASONS["$name"]="unparseable-envelope"
    TILDE_STATUS["$name"]="error"
    ABSOLUTE_STATUS["$name"]="error"
    TILDE_DB_FIELD["$name"]=""
    TILDE_DB_LITERAL_TILDE["$name"]="false"
    TILDE_DOCTOR_STORAGE["$name"]="error"
    ABSOLUTE_DOCTOR_STORAGE["$name"]="error"
    continue
  fi

  # Tilde boot status field. Across ai-memory builds the field has been
  # called .status / .verdict / .ok — try a small set then fall back to
  # "unknown". A boot envelope with .error means the binary itself
  # failed before producing structured output.
  ts=$(jq -r '
    .tilde_boot
    | if .error then "error" else
        ( .status // .verdict //
          ( if (.ok == true) then "ok"
            elif (.ok == false) then "warn"
            else "unknown" end ) )
      end' "$out_file")
  TILDE_STATUS["$name"]="$ts"

  # .db field as written in the manifest. The literal tilde is the
  # smoking gun for #507 — the path was not expanded before SQLite open.
  td=$(jq -r '.tilde_boot.db // .tilde_boot.config.db // .tilde_boot.storage.db // ""' "$out_file")
  TILDE_DB_FIELD["$name"]="$td"
  if [ -n "$td" ] && [ "${td:0:1}" = "~" ]; then
    TILDE_DB_LITERAL_TILDE["$name"]="true"
  else
    TILDE_DB_LITERAL_TILDE["$name"]="false"
  fi

  as=$(jq -r '
    .absolute_boot
    | if .error then "error" else
        ( .status // .verdict //
          ( if (.ok == true) then "ok"
            elif (.ok == false) then "warn"
            else "unknown" end ) )
      end' "$out_file")
  ABSOLUTE_STATUS["$name"]="$as"

  # Doctor Storage section: try a few schemas. The contract calls out
  # CRIT in the tilde case and OK in the absolute case.
  tds=$(jq -r '
    .tilde_doctor
    | if .error then "error" else
        ( .storage.status // .sections.storage.status //
          (.checks // [])[]? | select((.name // .id // "") | ascii_downcase | test("storage")) | .status
        )
      end
    // "unknown"
    | if . == null then "unknown" else . end' "$out_file" | head -1)
  TILDE_DOCTOR_STORAGE["$name"]="${tds:-unknown}"

  ads=$(jq -r '
    .absolute_doctor
    | if .error then "error" else
        ( .storage.status // .sections.storage.status //
          (.checks // [])[]? | select((.name // .id // "") | ascii_downcase | test("storage")) | .status
        )
      end
    // "unknown"
    | if . == null then "unknown" else . end' "$out_file" | head -1)
  ABSOLUTE_DOCTOR_STORAGE["$name"]="${ads:-unknown}"

  errs=$(jq -r '.errors // [] | join(",")' "$out_file" 2>/dev/null || true)
  if [ -n "$errs" ]; then
    NODE_REASONS["$name"]="$errs"
  fi

  stderr "  ${name} tilde=${TILDE_STATUS[$name]} (.db='${td}', literal_tilde=${TILDE_DB_LITERAL_TILDE[$name]}) absolute=${ABSOLUTE_STATUS[$name]}"
done

# --- verdict computation ----------------------------------------------
# v0.6.3.1 RED proof requires (per contract.md §S23 pass criteria):
#   - tilde-form boot returns the warn variant on every node, OR the
#     binary surfaces a doctor Storage CRIT;
#   - the .db field in the tilde manifest contains a literal '~' on
#     every node (proves no expansion occurred);
#   - absolute-form boot returns ok on every node (control).
#
# If the tilde case returns ok everywhere, the bug has been silently
# fixed (or the harness can no longer detect it) — actual_verdict=GREEN
# and the scenario fails (per Principle 2: governance trip-wire).

reasons=()
red_signals=0   # how many nodes show the bug
green_signals=0 # how many nodes look healthy under tilde
absolute_ok=0
total=4

for entry in "${NODES[@]}"; do
  name="${entry%%:*}"
  ts="${TILDE_STATUS[$name]:-unknown}"
  lit="${TILDE_DB_LITERAL_TILDE[$name]:-false}"
  as="${ABSOLUTE_STATUS[$name]:-unknown}"
  tds="${TILDE_DOCTOR_STORAGE[$name]:-unknown}"

  # Bug signal on this node: either status != ok under tilde, OR
  # doctor reports Storage CRIT under tilde, OR the literal '~' is
  # in the .db field of the boot manifest.
  if [ "$ts" != "ok" ] || [ "$lit" = "true" ] || \
     [ "$(echo "$tds" | tr 'A-Z' 'a-z')" = "crit" ]; then
    red_signals=$((red_signals + 1))
  else
    green_signals=$((green_signals + 1))
    reasons+=("${name} tilde-form returned ok with no '~' in .db and Storage=${tds} — bug not detected")
  fi

  # Accept `ok` AND `info*` variants (info-fallback, info-empty per
  # v0.6.3.1 release notes) as a passing absolute-form control. The
  # boot CLI emits info* on a fresh DB with empty namespace — still
  # SUCCESS for our control case. `warn` is the bug-surface signal and
  # stays disqualifying.
  case "$as" in
    ok|info|info-fallback|info-empty)
      absolute_ok=$((absolute_ok + 1))
      ;;
    *)
      reasons+=("${name} absolute-form boot returned ${as} (control case should be ok or info*)")
      ;;
  esac
done

if [ "$red_signals" = "$total" ]; then
  actual_verdict="RED"
elif [ "$green_signals" = "$total" ]; then
  actual_verdict="GREEN"
else
  # Asymmetric — flagged as a fail mode in contract.md (binary drift /
  # partial fix). We emit the dominant verdict but leave a reason.
  actual_verdict="ASYMMETRIC"
  reasons+=("asymmetric: ${red_signals}/${total} nodes show #507; ${green_signals}/${total} look clean — possible binary drift")
fi

expected="RED"
if [ "$actual_verdict" = "$expected" ] && [ "$absolute_ok" = "$total" ]; then
  pass="true"
else
  pass="false"
  if [ "$absolute_ok" != "$total" ]; then
    reasons+=("absolute-form did not return ok on all nodes (${absolute_ok}/${total}); separate regression beyond #507")
  fi
fi

# --- emit harness JSON -------------------------------------------------
to_obj() {
  # Build a JSON object from a parallel "name=value" list.
  local -n arr=$1
  jq -n --argjson m "$(
    printf '{'
    sep=""
    for k in "${!arr[@]}"; do
      printf '%s%s:%s' "$sep" "$(printf '%s' "$k" | jq -Rs .)" "$(printf '%s' "${arr[$k]}" | jq -Rs .)"
      sep=','
    done
    printf '}'
  )" '$m'
}

tilde_status_obj=$(to_obj TILDE_STATUS)
absolute_status_obj=$(to_obj ABSOLUTE_STATUS)
tilde_db_field_obj=$(to_obj TILDE_DB_FIELD)
tilde_db_lit_obj=$(jq -n --argjson m "$(
  printf '{'
  sep=""
  for k in "${!TILDE_DB_LITERAL_TILDE[@]}"; do
    v="${TILDE_DB_LITERAL_TILDE[$k]}"
    printf '%s%s:%s' "$sep" "$(printf '%s' "$k" | jq -Rs .)" "$v"
    sep=','
  done
  printf '}'
)" '$m')
tilde_doctor_obj=$(to_obj TILDE_DOCTOR_STORAGE)
absolute_doctor_obj=$(to_obj ABSOLUTE_DOCTOR_STORAGE)

# Interchange holds when tilde and absolute disagree on at least one
# node (the bug "shows up" in the cross-form delta).
interchange_holds="false"
for entry in "${NODES[@]}"; do
  name="${entry%%:*}"
  if [ "${TILDE_STATUS[$name]:-}" != "${ABSOLUTE_STATUS[$name]:-}" ]; then
    interchange_holds="true"; break
  fi
done

reasons_json=$(printf '%s\n' "${reasons[@]:-}" | jq -R . | jq -s 'map(select(length>0))')

jq -n \
  --arg scenario "S23" \
  --arg expected_verdict "$expected" \
  --arg actual_verdict "$actual_verdict" \
  --argjson pass "$pass" \
  --arg expected_red_reason "Issue #507 — config.toml ~ expansion (closes in Patch 2)" \
  --argjson tilde_boot_status_per_node "$tilde_status_obj" \
  --argjson absolute_boot_status_per_node "$absolute_status_obj" \
  --argjson tilde_db_field_per_node "$tilde_db_field_obj" \
  --argjson tilde_db_field_literal_tilde_per_node "$tilde_db_lit_obj" \
  --argjson tilde_doctor_storage_per_node "$tilde_doctor_obj" \
  --argjson absolute_doctor_storage_per_node "$absolute_doctor_obj" \
  --argjson interchange_holds "$interchange_holds" \
  --argjson reasons "$reasons_json" \
  '{
    scenario: $scenario,
    pass: $pass,
    expected_verdict: $expected_verdict,
    actual_verdict: $actual_verdict,
    expected_red_reason: $expected_red_reason,
    outputs: {
      tilde_boot_status_per_node: $tilde_boot_status_per_node,
      absolute_boot_status_per_node: $absolute_boot_status_per_node,
      tilde_db_field_per_node: $tilde_db_field_per_node,
      tilde_db_field_literal_tilde_per_node: $tilde_db_field_literal_tilde_per_node,
      tilde_doctor_storage_per_node: $tilde_doctor_storage_per_node,
      absolute_doctor_storage_per_node: $absolute_doctor_storage_per_node,
      interchange_holds: $interchange_holds
    },
    reasons: $reasons
  }'
