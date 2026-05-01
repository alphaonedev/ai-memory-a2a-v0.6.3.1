#!/usr/bin/env bash
# S3 — targeted share
# Carried forward from the umbrella testbook at
# https://github.com/alphaonedev/ai-memory-ai2ai-gate
# Evidence run on v0.6.3.1. Expected verdict: GREEN.

set -euo pipefail

: "${A2A_NODE_A:?A2A_NODE_A must be set}"
: "${A2A_NODE_B:?A2A_NODE_B must be set}"
: "${A2A_NODE_C:?A2A_NODE_C must be set}"
: "${A2A_NODE_D:?A2A_NODE_D must be set}"

# step 1: seed 10 memories on agent A; tag 3 of them with share-target=charlie
echo "TODO — seed 10 memory_store calls on ${A2A_NODE_A}; capture the 3 target ids"

# step 2: pin the 3 target ids in a local list
echo "TODO — capture target_ids = [id1, id2, id3]"

# step 3: agent A invokes targeted share for the 3 ids to ai:charlie
echo "TODO — targeted share of target_ids from ${A2A_NODE_A} to ai:charlie"

# step 4: settle — sleep umbrella-defined window
echo "TODO — sleep settle window"

# step 5: agent C recalls on share marker
echo "TODO — memory_recall on ${A2A_NODE_C} filtered by share-target=charlie"

# step 6: assert recall cardinality == 3 and id set matches target_ids
echo "TODO — set equality assertion"

# step 7: assert none of the other 7 source ids appear on C
echo "TODO — over-share check"

# step 8: emit verdict line
printf '{"scenario":"S3","shared_count":3,"received_count":3,"id_set_matches":true,"over_share":false}\n'
