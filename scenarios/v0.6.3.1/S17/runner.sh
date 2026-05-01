#!/usr/bin/env bash
# S17 — G9 webhook fanout on link / promote / delete / consolidate
# See contract.md.
set -euo pipefail

NODE_A="${A2A_NODE_A:?}"
NODE_B="${A2A_NODE_B:?}"
NODE_C="${A2A_NODE_C:?}"
NODE_D="${A2A_NODE_D:?}"
RECEIVER_URL="${A2A_WEBHOOK_RECEIVER:?}"

# step 1: configure webhook on all mesh nodes pointing at RECEIVER_URL with HMAC key
echo "TODO — POST webhook config to each NODE; record subscription id"

# step 2: link from NODE_A — expect one signed POST with event=link.*
echo "TODO — ssh NODE_A: memory_link(...); poll receiver; assert one signed POST"

# step 3: promote from NODE_B
echo "TODO — ssh NODE_B: memory_promote(...); assert one signed POST event=promote"

# step 4: delete from NODE_C
echo "TODO — ssh NODE_C: memory_delete(...); assert one signed POST event=delete"

# step 5: consolidate from NODE_D
echo "TODO — ssh NODE_D: memory_consolidate(...); assert one signed POST event=consolidate"

# step 6: HMAC verify every received POST
echo "TODO — for each received POST: verify HMAC against configured secret"

# step 7: SSRF guard — try a 127.0.0.1 target; assert dispatch refused
echo "TODO — register webhook url=http://127.0.0.1:9999/...; trigger event; assert no POST observed"

# step 8: assert no duplicates and memory_store still fires
echo "TODO — count POSTs per event; assert exactly 1; trigger memory_store; assert continues to fire"

# step 9: emit expected.json-shaped result document
cat <<EOF
{
  "scenario": "S17",
  "verdict": "TODO",
  "events_fired": {
    "link": null,
    "promote": null,
    "delete": null,
    "consolidate": null,
    "store": null
  },
  "hmac_all_valid": null,
  "ssrf_guard_held": null,
  "no_duplicates": null
}
EOF
