#!/usr/bin/env bash
# S11 — ai-memory install <agent> recipe handoff across mesh
# See contract.md.
set -euo pipefail

NODE_A="${A2A_NODE_A:?}"
NODE_B="${A2A_NODE_B:?}"
RECIPE="${A2A_INSTALL_RECIPE:-claude-code}"

# step 1: dry-run on node-A
echo "TODO — ssh NODE_A: ai-memory install ${RECIPE} --dry-run; capture diff"

# step 2: apply on node-A and verify idempotent rerun
echo "TODO — ssh NODE_A: ai-memory install ${RECIPE} --apply; rerun and confirm zero-diff"

# step 3: capture node-A managed block + .bak.<rfc3339> artefact
echo "TODO — read managed-block contents and confirm backup file exists"

# step 4: apply on node-B and capture managed block
echo "TODO — ssh NODE_B: ai-memory install ${RECIPE} --apply; read managed block"

# step 5: compare managed-keys and payload across A and B
echo "TODO — diff payloads; assert identical"

# step 6: cross-mesh boot equivalence
echo "TODO — ai-memory boot --format json on both nodes; assert same recall set after federation sync"

# step 7: uninstall round-trip on node-A
echo "TODO — ssh NODE_A: ai-memory install ${RECIPE} --uninstall --apply; assert config restored"

# step 8: emit expected.json-shaped result document
cat <<EOF
{
  "scenario": "S11",
  "verdict": "TODO",
  "recipe": "${RECIPE}",
  "managed_block_match": null,
  "idempotent": null,
  "uninstall_roundtrip_clean": null
}
EOF
