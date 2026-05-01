#!/usr/bin/env bash
# S18 — G4 embedding-dim integrity under cross-agent writes
# See contract.md.
set -euo pipefail

NODES=("${A2A_NODE_A:?}" "${A2A_NODE_B:?}" "${A2A_NODE_C:?}" "${A2A_NODE_D:?}")
NODE_A="${A2A_NODE_A}"
CANONICAL_DIM="${A2A_CANONICAL_DIM:-768}"
BAD_DIM="${A2A_BAD_DIM:-384}"

# step 1: agent-X writes a canonical 768-d vector on NODE_A; assert accepted
echo "TODO — ssh NODE_A: memory_store(content, embedding=zeros(${CANONICAL_DIM})); assert ok; SELECT embedding_dim from memories WHERE id=NEW; assert ${CANONICAL_DIM}"

# step 2: agent-Y writes a 384-d vector on NODE_A; assert refused with documented error
echo "TODO — ssh NODE_A: memory_store(content, embedding=zeros(${BAD_DIM})); assert error code dim_mismatch"

# step 3: repeat refusal probe on B / C / D
for n in "${NODES[@]:1}"; do
  echo "TODO — ssh ${n}: same bad-dim probe; assert refused"
done

# step 4: dim_violations counter increments per refusal per node
for n in "${NODES[@]}"; do
  echo "TODO — ssh ${n}: memory_stats; assert dim_violations >= 1; record value"
done

# step 5: federation peer view — query each peer's stats from NODE_A
for n in "${NODES[@]:1}"; do
  echo "TODO — ssh NODE_A: GET /api/v1/peers/${n}/stats; assert dim_violations matches local"
done

# step 6: recall sanity — confirm bad-dim memory not present
echo "TODO — memory_recall(probe-query); assert returned set has no 384-d row"

# step 7: emit expected.json-shaped result document
cat <<EOF
{
  "scenario": "S18",
  "verdict": "TODO",
  "good_dim_accepted": null,
  "bad_dim_refused_per_node": {},
  "dim_violations_per_node": {},
  "federation_view_matches": null,
  "no_silent_leak": null
}
EOF
