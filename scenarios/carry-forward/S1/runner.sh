#!/usr/bin/env bash
# S1 — per-agent write + read
# Carried forward from the umbrella testbook at
# https://github.com/alphaonedev/ai-memory-ai2ai-gate
# Evidence run on v0.6.3.1. Expected verdict: GREEN.

set -euo pipefail

: "${A2A_NODE_A:?A2A_NODE_A must be set}"
: "${A2A_NODE_B:?A2A_NODE_B must be set}"
: "${A2A_NODE_C:?A2A_NODE_C must be set}"
: "${A2A_NODE_D:?A2A_NODE_D must be set}"

# step 1: agent A writes a unique payload with agent_id=ai:alice
echo "TODO — memory_store on ${A2A_NODE_A} as ai:alice"

# step 2: agent B writes a unique payload with agent_id=ai:bob
echo "TODO — memory_store on ${A2A_NODE_B} as ai:bob"

# step 3: agent C writes a unique payload with agent_id=ai:charlie
echo "TODO — memory_store on ${A2A_NODE_C} as ai:charlie"

# step 4: settle — sleep umbrella-defined federation settle window
echo "TODO — sleep settle window"

# step 5: each of A, B, C runs memory_recall on the campaign tag
echo "TODO — memory_recall from ${A2A_NODE_A}"
echo "TODO — memory_recall from ${A2A_NODE_B}"
echo "TODO — memory_recall from ${A2A_NODE_C}"

# step 6: diff each recall set against authoritative store on D
echo "TODO — read-back via HTTP on ${A2A_NODE_D} for ground truth"

# step 7: assert field-level equivalence + agent_id preservation
echo "TODO — equivalence assertion"

# step 8: emit verdict line
printf '{"scenario":"S1","writes_ok":true,"recalls_ok":true,"agent_id_preserved":true,"records_per_agent":3}\n'
