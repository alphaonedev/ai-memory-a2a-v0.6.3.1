#!/usr/bin/env bash
# S23 — Issue #507 ~ expansion in db field (EXPECTED RED on v0.6.3.1)
# See contract.md.
set -euo pipefail

NODES=("${A2A_NODE_A:?}" "${A2A_NODE_B:?}" "${A2A_NODE_C:?}" "${A2A_NODE_D:?}")

# step 1: install both config variants on every node
echo "TODO — for each NODE: write config.toml.tilde and config.toml.absolute under ~/.config/ai-memory/"

# step 2: activate tilde form and run boot on every node
echo "TODO — for each NODE: ln -sf config.toml.tilde config.toml; ai-memory boot --format json --quiet; capture status"

# step 3: assert v0.6.3.1 contract — expect warn on every node (this is the bug)
echo "TODO — assert each NODE returned status=warn with 'db unavailable' (#507 RED proof)"

# step 4: confirm db: field contains literal '~'
echo "TODO — jq .db on each manifest; assert starts with '~' (no expansion)"

# step 5: activate absolute form; rerun boot on every node
echo "TODO — for each NODE: ln -sf config.toml.absolute config.toml; ai-memory boot --format json; capture status"

# step 6: assert absolute form returns ok on every node
echo "TODO — assert each NODE returned status=ok (control case)"

# step 7: doctor against tilde form
echo "TODO — re-activate tilde; ai-memory doctor --format json on each NODE; assert Storage CRIT on v0.6.3.1"

# step 8: doctor against absolute form
echo "TODO — re-activate absolute; ai-memory doctor; assert Storage OK"

# step 9: emit expected.json-shaped result document
cat <<EOF
{
  "scenario": "S23",
  "verdict": "TODO",
  "expected_red_reason": "Issue #507 — config.toml ~ expansion (closes in Patch 2)",
  "tilde_boot_status_per_node": {},
  "tilde_db_field_literal_tilde_per_node": {},
  "absolute_boot_status_per_node": {},
  "tilde_doctor_storage_per_node": {},
  "absolute_doctor_storage_per_node": {}
}
EOF
