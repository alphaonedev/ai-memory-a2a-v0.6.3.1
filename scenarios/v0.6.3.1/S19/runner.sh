#!/usr/bin/env bash
# S19 — G5 archive/restore preserves embeddings cross-agent
# See contract.md.
set -euo pipefail

NODE_A="${A2A_NODE_A:?}"
NODE_B="${A2A_NODE_B:?}"

# step 1: seed α (short, 1d expiry) and β (autonomous, NULL expiry) memories on NODE_A
echo "TODO — bulk-load fixtures/g5-alpha.jsonl and fixtures/g5-beta.jsonl on NODE_A"

# step 2: snapshot embedding + tier + expires_at for each seeded memory (pre-archive)
echo "TODO — SELECT id, embedding, tier, expires_at FROM memories WHERE id IN (...); save as fixtures/g5-snapshot.json"

# step 3: archive the seeded memories on NODE_A
echo "TODO — ssh NODE_A: memory_archive(...) for each seeded id"

# step 4: list archive on NODE_B; assert visibility
echo "TODO — ssh NODE_B: memory_archive_list; assert seeded ids present"

# step 5: restore each from NODE_B
echo "TODO — ssh NODE_B: memory_archive_restore(id) for each id"

# step 6: compare restored row vs pre-archive snapshot
echo "TODO — for each id: SELECT embedding, tier, expires_at; assert byte-equal embedding, tier match, expires_at match"

# step 7: recall sanity on NODE_B against a query that should hit restored embedding
echo "TODO — memory_recall(query=Q) on NODE_B; assert restored ids in result"

# step 8: archive_stats consistency check across mesh
echo "TODO — memory_archive_stats on each NODE; compare counts"

# step 9: emit expected.json-shaped result document
cat <<EOF
{
  "scenario": "S19",
  "verdict": "TODO",
  "embedding_byte_equal_per_id": {},
  "tier_preserved_per_id": {},
  "expires_at_preserved_per_id": {},
  "recall_hit_post_restore": null,
  "stats_mesh_consistent": null
}
EOF
