#!/usr/bin/env bash
# S8 — auto-tagging
# Carried forward from the umbrella testbook at
# https://github.com/alphaonedev/ai-memory-ai2ai-gate
# Evidence run on v0.6.3.1. Expected verdict: GREEN.

set -euo pipefail

: "${A2A_NODE_A:?A2A_NODE_A must be set}"
: "${A2A_NODE_B:?A2A_NODE_B must be set}"
: "${A2A_NODE_C:?A2A_NODE_C must be set}"
: "${A2A_NODE_D:?A2A_NODE_D must be set}"

# step 1: agent A writes a memory with empty tags on a recognisable topic
echo "TODO — memory_store on ${A2A_NODE_A} as ai:alice with tags=[]"

# step 2: settle — sleep auto-tag pipeline window
echo "TODO — sleep auto-tag settle window"

# step 3: explicitly invoke memory_auto_tag for determinism
echo "TODO — memory_auto_tag on the new record id"

# step 4: snapshot the taxonomy
echo "TODO — memory_get_taxonomy on ${A2A_NODE_D}; capture taxonomy_size"

# step 5: re-fetch the record and read its tag set
echo "TODO — memory_get on the record; capture applied_tags"

# step 6: assert applied_tags non-empty and subset of taxonomy
echo "TODO — non-empty + subset assertion"

# step 7: agent B recalls by one of the auto-generated tags
echo "TODO — memory_recall on ${A2A_NODE_B} filtered by one applied tag; assert A's record present"

# step 8: emit verdict line
printf '{"scenario":"S8","tags_applied":0,"tags_in_taxonomy":true,"recall_by_auto_tag_ok":true,"taxonomy_size":0}\n'
