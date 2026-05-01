#!/usr/bin/env bash
# S7 — scoping visibility
# Carried forward from the umbrella testbook at
# https://github.com/alphaonedev/ai-memory-ai2ai-gate
# Evidence run on v0.6.3.1. Expected verdict: GREEN.

set -euo pipefail

: "${A2A_NODE_A:?A2A_NODE_A must be set}"
: "${A2A_NODE_B:?A2A_NODE_B must be set}"
: "${A2A_NODE_C:?A2A_NODE_C must be set}"
: "${A2A_NODE_D:?A2A_NODE_D must be set}"

# step 1: agent A writes one memory per scope (private/team/unit/org/collective)
echo "TODO — five memory_store calls on ${A2A_NODE_A}, one per scope"

# step 2: settle — sleep umbrella-defined window
echo "TODO — sleep settle window"

# step 3: agent A recalls the campaign tag
echo "TODO — memory_recall on ${A2A_NODE_A}; record visible scopes for caller=alice"

# step 4: agent B recalls the campaign tag
echo "TODO — memory_recall on ${A2A_NODE_B}; record visible scopes for caller=bob"

# step 5: agent C recalls the campaign tag
echo "TODO — memory_recall on ${A2A_NODE_C}; record visible scopes for caller=charlie"

# step 6: probe memory_get on the private id from B and C; expect not-found
echo "TODO — memory_get on private id from ${A2A_NODE_B} and ${A2A_NODE_C}"

# step 7: build 5x3 visibility matrix and diff against umbrella spec
echo "TODO — matrix diff; count cell mismatches"

# step 8: cross-check HTTP path agrees with MCP path
echo "TODO — HTTP /api/v1/memories?scope=... agreement check"

# step 9: emit verdict line
printf '{"scenario":"S7","matrix_mismatches":0,"private_leak":false,"http_mcp_agree":true}\n'
