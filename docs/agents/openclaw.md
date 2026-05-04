# OpenClaw agent

OpenClaw is a first-class agent framework in the A2A gate alongside
IronClaw (Rust) and Hermes (Python). On DigitalOcean the 8+ GB
install-time memory demand constrained the matrix to tier-upgraded
droplets; as of 2026-04-24 OpenClaw runs as a fully certified cell
on the **[local Docker mesh](../local-docker-mesh.md)** where each
openclaw node is allocated 16 GB of container memory on a workstation.
IronClaw is still the DO default for the Basic-tier 4 GB cost path
(~$0.03 per campaign).

The A2A gate hosts three OpenClaw agent instances (on `node-1`,
`node-2`, `node-3`) + one memory-only aggregator (`node-4`) to
demonstrate that ai-memory's A2A semantics work with the OpenClaw
agent framework's specific MCP client.

## What OpenClaw brings to the A2A gate

- An MCP-native agent runtime that invokes `memory_store`,
  `memory_recall`, and the rest of the ai-memory tool surface via
  stdio.
- Two different `agent_id` values (`ai:alice`, `ai:charlie`) so
  scenarios can assert agent-identity preservation and immutability
  across independent writers of the same framework.

## Per-node setup (`scripts/setup_openclaw_agent.sh` — to be written)

```
1. apt-get update + install runtime deps
2. Install OpenClaw from release tarball or container image
3. Configure MCP client to target node-4:
     AI_MEMORY_MCP_ENDPOINT=http://10.260.0.14:9077
     AI_MEMORY_AGENT_ID=ai:alice   # or ai:charlie on node-3
4. Provision the scenario-runner script from the ship-gate
   conventions
5. Health-check: agent CLI `openclaw version` + echo-request to
   ai-memory
```

## Why two OpenClaw agents and not one

Scenarios 6 (contradiction detection) and 7 (scoping visibility)
both require at least three distinct `agent_id` values to
exercise their full assertion matrix:

- Agent A writes something
- Agent B writes a contradicting or scope-boundary-testing
  something
- Agent C, the uninvolved third party, recalls and must see the
  state

Two OpenClaw agents + one Hermes agent satisfies "≥ 3 distinct
agents" while also exercising the "same-framework × different-
agent-id" axis that catches identity-preservation bugs specific
to OpenClaw's MCP client implementation.

## What the A2A gate measures against OpenClaw

- Correctness of tool invocation under the MCP schema (validated
  by `memory_store` responses carrying the expected `id` field).
- Identity preservation on each write (`metadata.agent_id` on the
  returned row matches the caller's).
- Scope honoring (agent A's `private`-scope writes invisible to
  agent C's recall).

If a release of OpenClaw changes MCP client behaviour in a way
that breaks these assertions, the A2A gate will flag it the next
time a campaign runs.

## Version pinning

The specific OpenClaw release tested in each campaign is recorded
in the artifact as `openclaw_version`. Reviewers comparing
campaigns across time can filter on that field.

Pinning policy: the A2A gate defaults to the latest stable OpenClaw
release available at campaign-dispatch time. Override via a
workflow input when intentionally testing against a specific
version.

## Reality-check findings (v0.6.3.1, 2026-05-04)

These are observed during the v0.6.3.1 OpenClaw campaign — important context for anyone re-using this harness:

### 1. OpenClaw config schema changed substantially between 2026.4.x and 2026.5.x

The `docker/entrypoint.sh` openclaw.json shape that worked through the v0.6.0–v0.6.2 cert era — top-level `providers`, `defaultProvider`, `mcpServers`, `agentToAgent`, `toolAllowlist`, `nodeHosts`, `remoteMode`, `subAgent`, `agentTeams`, `sharedServices`, `a2aGateProfile` — is **rejected by both OpenClaw 2026.4.22 and 2026.5.2** with `Unrecognized keys` errors. Modern OpenClaw is **gateway-centric**: `gateway.{mode,auth,port,bind,tailscale}`, `agents.defaults`, `models`, `tools`, `bindings`, `acp`, `cron`, `commitments`, etc.

### 2. The fictional `openclaw run` invocation never worked

`docker/drive_agent.sh:94` invokes `openclaw run --non-interactive --format json --max-tool-rounds 20 -p "<prompt>"`. **Neither OpenClaw 2026.4.22 nor 2026.5.2 has a `run` subcommand.** The actual subcommand is `openclaw agent` with options `--local --json --message <text> --session-id <id> --agent <agent>`. The `drive_agent.sh` openclaw branch silently fails and falls through to `fallback_driver` (HTTP-direct against ai-memory) — which is why Phase 0–1 substrate scenarios pass even with a non-functional openclaw runtime.

### 3. The validated 2026.5.x setup recipe

```bash
# 1. Onboard with xAI provider, accepting the risk acknowledgement
openclaw onboard --non-interactive --accept-risk --mode local --skip-health \
  --auth-choice xai-api-key \
  --xai-api-key "$XAI_API_KEY"

# 2. Register ai-memory MCP server
openclaw mcp set memory '{
  "command": "ai-memory",
  "args": ["--db", "/var/lib/ai-memory/a2a.db", "mcp", "--tier", "semantic"],
  "env": {"AI_MEMORY_AGENT_ID": "ai:alice"}
}'

# 3. Verify
openclaw mcp list
openclaw config validate --json

# 4. Drive an agent turn (the actual modern invocation)
openclaw agent --local --json --agent main --session-id <sid> \
  --message "<prompt>" --timeout 200
```

This recipe is the **substrate of the OpenClaw behavioral assessment** — see [openclaw v0.6.3.1 behavioral assessment](../nhi/openclaw-behavioral-v0.6.3.1.md) for the full Tier 1–4 instrument run against this configuration.

### 4. Identity propagation is not automatic

Container env carries `AGENT_ID=ai:alice|ai:bob|ai:charlie`. OpenClaw `agent --local` does NOT read this env to set the agent's verbal identity. In the behavioral assessment, agents on `a2a-node-1` (env `AGENT_ID=ai:alice`) sometimes self-identify as `ai:bob` if the system-prompt / SOUL.md flow doesn't anchor them. **MCP write metadata is correct** (the `AI_MEMORY_AGENT_ID` env in the openclaw.json `mcpServers.memory.env` block flows through to ai-memory writes), but the LLM's verbal self-reference can drift. Caveat for prompt design.

### 5. End-to-end xAI Grok ↔ ai-memory MCP roundtrip — VERIFIED

Phase C of the v0.6.3.1 assessment proves: xAI `grok-4.3` (provider=`xai`, OpenAI-Responses API at `api.x.ai/v1`) → openclaw `agent --local` runtime → MCP stdio → `ai-memory mcp` server → write/read on local SQLite + federated quorum-fanout. Roundtrip ~46 s, ~25 K tokens (mostly cached after first turn). Working configuration captured under PR #46.

## Related

- [Hermes agent](hermes.md) — the other framework under test.
- [IronClaw agent](ironclaw.md) — primary cert agent.
- [OpenClaw v0.6.3.1 behavioral assessment](../nhi/openclaw-behavioral-v0.6.3.1.md) — Tier 1–4 evidence.
- [OpenClaw v0.6.3.1 substrate cert](../../releases/v0.6.3.1/openclaw-local-docker-cert.md) — 3-green substrate streak.
- [Local Docker mesh](../local-docker-mesh.md) — reproducibility spec.
- [Topology](../topology.md) — where OpenClaw agents sit.
- [Methodology](../methodology.md) — the full scenario matrix.
