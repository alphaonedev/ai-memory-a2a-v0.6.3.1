#!/usr/bin/env bash
# S14 — ai-memory logs operator surface
# See contract.md.
set -euo pipefail

NODES=("${A2A_NODE_A:?}" "${A2A_NODE_B:?}" "${A2A_NODE_C:?}" "${A2A_NODE_D:?}")

# step 1: phase 1 — assert default OFF on every node
echo "TODO — for each NODE: ai-memory logs tail; assert default-OFF signal and exit 0; assert no log file"

# step 2: enable logging on every node and seed workload
echo "TODO — flip [logging] enabled = true on each NODE; reload; run small workload"

# step 3: tail json on every node and capture envelope shape
echo "TODO — ai-memory logs tail --format json --since '5 minutes ago' on each NODE; collect key set"

# step 4: assert envelope shape identical across nodes
echo "TODO — diff key sets; assert single distinct schema"

# step 5: filter cardinality checks (--namespace, --actor, --action)
echo "TODO — apply progressive filters; assert subset cardinality holds"

# step 6: phase 3 — revert A/B/C to disabled; only D stays on
echo "TODO — flip A/B/C off; confirm D still emitting; A/B/C silent post-revert"

# step 7: env-var precedence on D
echo "TODO — AI_MEMORY_LOG_DIR=/tmp/elsewhere ai-memory logs tail on D; confirm read path = /tmp/elsewhere"

# step 8: emit expected.json-shaped result document
cat <<EOF
{
  "scenario": "S14",
  "verdict": "TODO",
  "phase1_default_off_clean": null,
  "phase2_envelope_uniform": null,
  "phase2_filter_subsets_ok": null,
  "phase3_partial_optin_ok": null,
  "env_precedence_ok": null
}
EOF
