#!/usr/bin/env bash
# S13 — ai-memory audit verify tamper-evident hash chain
# See contract.md.
set -euo pipefail

NODES=("${A2A_NODE_A:?}" "${A2A_NODE_B:?}" "${A2A_NODE_C:?}" "${A2A_NODE_D:?}")
NODE_A="${A2A_NODE_A}"

# step 1: seed audit workload on each node
echo "TODO — for each NODE: run ~50 mixed memory ops to populate audit log"

# step 2: clean-state verify on every node
echo "TODO — for each NODE: ssh and run: ai-memory audit verify; assert exit 0"

# step 3: tail spot-check
echo "TODO — for each NODE: ai-memory audit tail 10; assert prev_hash chain locally"

# step 4: snapshot node-A audit file
echo "TODO — ssh NODE_A: cp \$(ai-memory audit path) \$(ai-memory audit path).snapshot"

# step 5: tamper one byte mid-file on NODE_A
echo "TODO — ssh NODE_A: out-of-band byte flip in middle of audit log"

# step 6: re-verify NODE_A; assert exit 2 and sequence reported
echo "TODO — ssh NODE_A: ai-memory audit verify; assert exit 2; capture stderr sequence id"

# step 7: re-verify peers; assert each still exits 0
for n in "${NODES[@]:1}"; do
  echo "TODO — ssh ${n}: ai-memory audit verify; assert exit 0"
done

# step 8: restore NODE_A from snapshot
echo "TODO — ssh NODE_A: mv snapshot back; verify exit 0 again"

# step 9: emit expected.json-shaped result document
cat <<EOF
{
  "scenario": "S13",
  "verdict": "TODO",
  "pre_tamper_exit_codes": {},
  "tampered_node_exit_code": null,
  "peer_exit_codes_post_tamper": {},
  "tampered_sequence_reported": null
}
EOF
