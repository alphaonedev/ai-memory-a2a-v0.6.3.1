#!/usr/bin/env bash
# S16 — Capabilities v2 honesty cross-mesh
# See contract.md.
set -euo pipefail

NODES=("${A2A_NODE_A:?}" "${A2A_NODE_B:?}" "${A2A_NODE_C:?}" "${A2A_NODE_D:?}")
NODE_D="${A2A_NODE_D}"

# step 1: phase 1 — all nodes healthy; query capabilities everywhere
echo "TODO — for each NODE: GET /api/v1/capabilities; assert recall_mode_active=hybrid, reranker_active=neural, schema_version>=2"

# step 2: assert v1 theater fields are absent from v2 response
echo "TODO — jq has(\"subscribers\"), has(\"by_event\"), has(\"rule_summary\"), has(\"default_timeout_seconds\"); all must be false"

# step 3: assert permissions.mode == \"advisory\" on every node
echo "TODO — jq .permissions.mode; assert advisory"

# step 4: phase 2 — unload embedder on NODE_D; recheck D directly
echo "TODO — ssh NODE_D: stop embedder; GET /api/v1/capabilities; assert recall_mode_active=keyword_only"

# step 5: from NODE_A, query D via federation peer endpoint; assert same degraded value
echo "TODO — ssh NODE_A: GET /api/v1/peers/<D-id>/capabilities; assert recall_mode_active=keyword_only"

# step 6: phase 3 — block reranker on D; recheck both views
echo "TODO — block reranker; assert reranker_active=lexical_fallback from D and via A"

# step 7: restore NODE_D and assert mesh-wide flip back
echo "TODO — re-enable embedder + reranker; await refresh; assert hybrid + neural everywhere"

# step 8: emit expected.json-shaped result document
cat <<EOF
{
  "scenario": "S16",
  "verdict": "TODO",
  "v2_schema_present": null,
  "v1_theater_fields_absent": null,
  "self_reports_degraded": null,
  "peer_view_surfaces_degraded": null,
  "permissions_mode_advisory": null,
  "round_trip_clean": null
}
EOF
