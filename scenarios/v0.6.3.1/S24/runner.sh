#!/usr/bin/env bash
# S24 — Issue #318 MCP stdio writes fan out (EXPECTED RED on v0.6.3.1)
# See contract.md.
set -euo pipefail

NODE_A="${A2A_NODE_A:?}"
NODE_B="${A2A_NODE_B:?}"
NODE_C="${A2A_NODE_C:?}"
NODE_D="${A2A_NODE_D:?}"
TOOLS=(memory_store memory_update memory_delete memory_link memory_promote memory_consolidate memory_forget)

# step 1: phase 1 control — HTTP write on NODE_A then poll peers for replication
echo "TODO — POST /api/v1/memories x10 on NODE_A; poll memory_recall on NODE_B/C/D for the seeded content"

# step 2: assert phase-1 replication count >= quorum on every peer
echo "TODO — assert peer replication count >= 1 (W=2 means at least one peer must ack); record"

# step 3: phase 2 — invoke each MCP-stdio tool with distinguishable payload
for t in "${TOOLS[@]}"; do
  echo "TODO — ssh NODE_A: spawn 'ai-memory mcp' via stub agent runner; call ${t}() with phase-2 payload"
done

# step 4: poll peers for phase-2 content; v0.6.3.1 expects zero replication
for t in "${TOOLS[@]}"; do
  echo "TODO — for each peer (B/C/D): query for ${t} phase-2 marker; expect 0 rows on v0.6.3.1; record actual"
done

# step 5: confirm phase-2 writes succeeded locally on NODE_A (rules out non-bug)
echo "TODO — ssh NODE_A: ai-memory audit tail | grep phase2-marker; assert each operation present locally"

# step 6: confirm serve daemon on B/C/D saw no replication request for phase-2
echo "TODO — ssh B/C/D: grep serve daemon log for replication requests with phase-2 marker; assert empty on v0.6.3.1"

# step 7: emit expected.json-shaped result document
cat <<EOF
{
  "scenario": "S24",
  "verdict": "TODO",
  "expected_red_reason": "Issue #318 — MCP stdio writes bypass federation fanout (closes in Patch 2)",
  "phase1_http_replication_ok": null,
  "phase2_mcp_replication_per_tool": {},
  "phase2_local_audit_present": null,
  "peer_serve_logs_silent": null
}
EOF
