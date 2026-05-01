#!/usr/bin/env bash
# S21 — G13 endianness magic byte cross-arch
# See contract.md.
set -euo pipefail

NODE_A_X86="${A2A_NODE_A:?}"        # expected x86_64
NODE_B_X86="${A2A_NODE_B:?}"        # expected x86_64
NODE_C_ARM="${A2A_NODE_C:?}"        # expected arm64
NODE_D_ARM="${A2A_NODE_D:?}"        # expected arm64

# step 1: confirm arch on each NODE
for n in "${NODE_A_X86}" "${NODE_B_X86}" "${NODE_C_ARM}" "${NODE_D_ARM}"; do
  echo "TODO — ssh ${n}: uname -m; record arch"
done

# step 2: seed embedding corpus on NODE_A_X86; await federation
echo "TODO — bulk-load fixtures/g13-embeddings.jsonl on NODE_A_X86; poll until C/D have rows"

# step 3: cross-arch read on NODE_C_ARM; recompute cosine; assert magnitude-1
echo "TODO — fetch a seeded memory's embedding on NODE_C_ARM; cosine vs original; assert ~1.0"

# step 4: inverse direction — seed on NODE_C_ARM; replicate; check on NODE_A_X86
echo "TODO — bulk-load on NODE_C_ARM; await sync; cosine check on NODE_A_X86"

# step 5: inspect raw BLOB magic byte on both arches
echo "TODO — sqlite3 SELECT hex(substr(embedding, 1, 1)); assert documented magic byte on both arches"

# step 6: inject wrong-endian payload via federation HTTP API
echo "TODO — POST /api/v1/replicate with byteswapped f32 payload; assert documented refuse-or-rewrite"

# step 7: cross-arch recall determinism
echo "TODO — memory_recall(query=Q) on x86 and arm; assert same ranked head"

# step 8: emit expected.json-shaped result document
cat <<EOF
{
  "scenario": "S21",
  "verdict": "TODO",
  "arch_per_node": {},
  "magic_byte_present_per_arch": {},
  "cross_arch_cosine_ok": null,
  "wrong_endian_handled": null,
  "recall_determinism": null
}
EOF
