#!/usr/bin/env bash
# S15 — R1 budget_tokens recall determinism across the federation
# See contract.md.
set -euo pipefail

NODES=("${A2A_NODE_A:?}" "${A2A_NODE_B:?}" "${A2A_NODE_C:?}" "${A2A_NODE_D:?}")
BUDGETS=(256 1024 4096)
QUERIES=("${A2A_QUERY_1:-architecture decisions}" \
        "${A2A_QUERY_2:-incident postmortem}" \
        "${A2A_QUERY_3:-onboarding notes}" \
        "${A2A_QUERY_4:-deployment topology}" \
        "${A2A_QUERY_5:-test fixture conventions}")

# step 1: seed 200-memory corpus on NODE_A; await federation convergence
echo "TODO — bulk-load fixtures/200-corpus.jsonl into NODE_A; poll memory_stats on B/C/D until count matches"

# step 2: for each (query, budget) pair, recall on every node and capture ranked head
for q in "${QUERIES[@]}"; do
  for b in "${BUDGETS[@]}"; do
    for n in "${NODES[@]}"; do
      echo "TODO — ssh ${n}: memory_recall(query=\"${q}\", budget_tokens=${b}); capture [(id, score), ...]"
    done
  done
done

# step 3: assert byte-equal ID order across nodes per (query, budget)
echo "TODO — pairwise diff per case; any diff is a fail"

# step 4: edge case — tiny budget returns exactly one memory
echo "TODO — memory_recall(query=Q, budget_tokens=64) on all NODES; assert single memory; same id"

# step 5: edge case — huge budget returns full corpus in identical order
echo "TODO — memory_recall(query=Q, budget_tokens=10_000_000) on all NODES; assert full corpus same order"

# step 6: assert cumulative token count <= budget on every case
echo "TODO — sum returned-memory tokens; assert <= budget_tokens"

# step 7: emit expected.json-shaped result document
cat <<EOF
{
  "scenario": "S15",
  "verdict": "TODO",
  "case_count": 15,
  "head_match_per_case": {},
  "budget_respected_per_case": {},
  "edge_below_ok": null,
  "edge_above_ok": null
}
EOF
