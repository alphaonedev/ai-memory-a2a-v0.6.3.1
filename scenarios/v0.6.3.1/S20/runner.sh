#!/usr/bin/env bash
# S20 — G6 on_conflict policy under concurrent writes
# See contract.md.
set -euo pipefail

NODE_A="${A2A_NODE_A:?}"
NODE_B="${A2A_NODE_B:?}"
RACE_TRIALS="${A2A_RACE_TRIALS:-50}"

# step 1: probe on_conflict=error
echo "TODO — agent-X writes (title=dup-key, ns=probe) on NODE_A; agent-Y writes same on NODE_B with on_conflict=error; assert exactly one fails"

# step 2: reset state, probe on_conflict=merge
echo "TODO — purge probe ns; agent-X writes; agent-Y writes with on_conflict=merge differing body; assert single row, merged content per spec"

# step 3: reset state, probe on_conflict=version
echo "TODO — purge probe ns; agent-X writes; agent-Y writes with on_conflict=version; assert two rows / versioned successor"

# step 4: assert default policy is error for unknown clients
echo "TODO — purge probe ns; first write OK; second write WITHOUT on_conflict; assert default behaviour == error"

# step 5: concurrent race ${RACE_TRIALS} trials
echo "TODO — barrier-sync agent-X/agent-Y on NODE_A/NODE_B; race ${RACE_TRIALS} times; tally winners"

# step 6: collect win-rate per node and assert balanced (not pathological skew)
echo "TODO — assert sum(wins) == ${RACE_TRIALS}; both wins in plausible range"

# step 7: emit expected.json-shaped result document
cat <<EOF
{
  "scenario": "S20",
  "verdict": "TODO",
  "error_policy_ok": null,
  "merge_policy_ok": null,
  "version_policy_ok": null,
  "default_is_error": null,
  "race_trials": ${RACE_TRIALS},
  "race_exactly_one_winner_per_trial": null,
  "win_distribution": {}
}
EOF
