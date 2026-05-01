#!/usr/bin/env bash
# S10 — ai-memory doctor cross-node section agreement
# See contract.md.
set -euo pipefail

NODES=("${A2A_NODE_A:?}" "${A2A_NODE_B:?}" "${A2A_NODE_C:?}" "${A2A_NODE_D:?}")
IN_FLIGHT_TOLERANCE="${A2A_DOCTOR_TOLERANCE:-5}"

# step 1: seed fixture corpus across the mesh
echo "TODO — write ~20 memories spanning 3 namespaces via memory_store on node-A"

# step 2: run ai-memory doctor on every node
echo "TODO — for each NODE: ssh and run: ai-memory doctor --format json"

# step 3: parse 7 sections (Storage / Index / Recall / Governance / Sync / Webhook / Capabilities)
echo "TODO — jq each manifest into per-section severity table"

# step 4: compute per-section agreement; tolerate row-count delta within IN_FLIGHT_TOLERANCE
echo "TODO — build agreement matrix; flag any categorical disagreement"

# step 5: asymmetric-warning variant — stop embedder on node-D and re-check peers
echo "TODO — toggle embedder off on D, re-run doctor on A/B/C/D, assert D is flagged from all four perspectives"

# step 6: emit expected.json-shaped result document
cat <<EOF
{
  "scenario": "S10",
  "verdict": "TODO",
  "section_table": {},
  "asymmetric_warning_surfaced": null
}
EOF
