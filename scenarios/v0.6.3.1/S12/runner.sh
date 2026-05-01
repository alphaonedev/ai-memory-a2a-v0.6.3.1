#!/usr/bin/env bash
# S12 — ai-memory wrap <agent> cross-vendor consistency
# See contract.md.
set -euo pipefail

NODE_A="${A2A_NODE_A:?}"
NODE_B="${A2A_NODE_B:?}"
VENDORS=(codex gemini aider ollama)

# step 1: seed federation corpus
echo "TODO — seed ~30 memories via memory_store on NODE_A; await sync"

# step 2: run wrap against each vendor stub on NODE_A
for v in "${VENDORS[@]}"; do
  echo "TODO — ssh NODE_A: ai-memory wrap ${v} -- ${A2A_STUB_DIR:-/opt/a2a/stubs}/${v}-stub"
done

# step 3: parse stub envelopes into normalised {strategy, payload} shape
echo "TODO — extract delivered boot context from each stub stdout"

# step 4: assert payload byte-identical across the four vendors on NODE_A
echo "TODO — sha256 each payload; assert single distinct hash"

# step 5: repeat sweep on NODE_B; assert payload matches NODE_A
for v in "${VENDORS[@]}"; do
  echo "TODO — ssh NODE_B: ai-memory wrap ${v} -- ${A2A_STUB_DIR:-/opt/a2a/stubs}/${v}-stub; compare hash"
done

# step 6: exit-code propagation
echo "TODO — invoke a stub that exits 7; assert wrap also exits 7"

# step 7: emit expected.json-shaped result document
cat <<EOF
{
  "scenario": "S12",
  "verdict": "TODO",
  "vendor_payload_hashes": {},
  "cross_node_payload_match": null,
  "exit_propagation_ok": null
}
EOF
