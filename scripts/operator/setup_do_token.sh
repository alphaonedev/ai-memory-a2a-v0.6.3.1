#!/usr/bin/env bash
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
#
# Idempotent DigitalOcean token onboarding for the Orchestrator node.
#
# What this does (in order):
#   1. Reads a DigitalOcean API token from $1 OR stdin OR $DIGITALOCEAN_TOKEN
#      env var (in that priority).
#   2. Validates the token shape (DO tokens are 64 hex chars, prefixed with
#      `dop_v1_` since 2023; older tokens are 64 hex without prefix).
#   3. Adds it to ~/.alphaone/secrets.env as DIGITALOCEAN_TOKEN= (if not
#      already present) — idempotent.
#   4. Runs `doctl auth init -t $TOKEN` (or detects existing auth).
#   5. Confirms `doctl compute droplet list` works against the account.
#   6. Prints the env exports the operator should sources for terraform:
#        export DIGITALOCEAN_TOKEN
#        export TF_VAR_do_token=$DIGITALOCEAN_TOKEN
#        export TF_VAR_ssh_key_fingerprint=<from `doctl compute ssh-key list`>
#
# Usage:
#   scripts/operator/setup_do_token.sh dop_v1_abcdef...
#   scripts/operator/setup_do_token.sh < token.txt
#   echo dop_v1_... | scripts/operator/setup_do_token.sh
#   DIGITALOCEAN_TOKEN=dop_v1_... scripts/operator/setup_do_token.sh
#
# Exit codes:
#   0 — token validated, doctl authenticated, droplet list succeeded
#   1 — token validation failed
#   2 — doctl auth failed (token rejected)
#   3 — droplet list failed (token authenticated but lacks scope, or net error)

set -euo pipefail

SECRETS_FILE="${SECRETS_FILE:-$HOME/.alphaone/secrets.env}"

err() { echo "setup_do_token: $*" >&2; }

# 1. Resolve token from arg / stdin / env, in that priority.
TOKEN="${1:-}"
if [ -z "$TOKEN" ] && [ ! -t 0 ]; then
  TOKEN="$(cat | tr -d '[:space:]')"
fi
if [ -z "$TOKEN" ]; then
  TOKEN="${DIGITALOCEAN_TOKEN:-}"
fi
if [ -z "$TOKEN" ]; then
  err "no token provided. Usage: setup_do_token.sh dop_v1_<token>"
  exit 1
fi

# 2. Shape validation.
if [[ ! "$TOKEN" =~ ^(dop_v1_)?[a-f0-9]{64}$ ]]; then
  err "token does not match DigitalOcean shape (dop_v1_<64 hex> or 64 hex)."
  err "got length=${#TOKEN}; first 8 chars=${TOKEN:0:8}<redacted>"
  exit 1
fi

# 3. Idempotent persist to secrets.env. Don't echo the token to stdout.
mkdir -p "$(dirname "$SECRETS_FILE")"
if [ -f "$SECRETS_FILE" ] && grep -q '^DIGITALOCEAN_TOKEN=' "$SECRETS_FILE"; then
  # Preserve permission, replace in-place.
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  awk -v t="$TOKEN" '/^DIGITALOCEAN_TOKEN=/{print "DIGITALOCEAN_TOKEN=" t; next} {print}' "$SECRETS_FILE" > "$tmp"
  mv "$tmp" "$SECRETS_FILE"
  chmod 600 "$SECRETS_FILE"
  echo "setup_do_token: replaced DIGITALOCEAN_TOKEN in $SECRETS_FILE"
else
  printf 'DIGITALOCEAN_TOKEN=%s\n' "$TOKEN" >> "$SECRETS_FILE"
  chmod 600 "$SECRETS_FILE"
  echo "setup_do_token: appended DIGITALOCEAN_TOKEN to $SECRETS_FILE"
fi

# 4. doctl auth init. Use a named context so multiple accounts can coexist.
DOCTL_CONTEXT="${DOCTL_CONTEXT:-a2a-v0631}"
if doctl auth list 2>/dev/null | grep -q "^${DOCTL_CONTEXT}\b"; then
  echo "setup_do_token: doctl context '$DOCTL_CONTEXT' already exists; updating token"
fi
if ! printf '%s\n' "$TOKEN" | doctl auth init --context "$DOCTL_CONTEXT" --access-token "$TOKEN" >/dev/null 2>&1; then
  err "doctl auth init failed for context '$DOCTL_CONTEXT'"
  exit 2
fi
doctl auth switch --context "$DOCTL_CONTEXT" >/dev/null 2>&1 || true

# 5. Smoke check.
echo "setup_do_token: doctl compute droplet list (smoke check) ..."
if ! doctl compute droplet list --format ID,Name,Region,Status,Tags 2>&1 | head -20; then
  err "droplet list failed; check token scope (needs read on Droplets)"
  exit 3
fi

# 5a. SSH key fingerprint hint (terraform/main.tf wants TF_VAR_ssh_key_fingerprint)
echo
echo "setup_do_token: SSH keys registered on this DO account:"
doctl compute ssh-key list --format ID,Name,FingerPrint 2>/dev/null | head -10

# 6. Print exports for the operator to source.
cat <<EOF

setup_do_token: success.

To use in this shell:
    set -a; source $SECRETS_FILE; set +a
    export TF_VAR_do_token="\$DIGITALOCEAN_TOKEN"
    # Pick the fingerprint that matches your local ssh key:
    export TF_VAR_ssh_key_fingerprint="<paste-from-list-above>"

To verify terraform pickup:
    cd terraform && terraform plan -var "ssh_key_fingerprint=\$TF_VAR_ssh_key_fingerprint"
EOF
