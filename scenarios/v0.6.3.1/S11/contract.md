# S11 — `ai-memory install <agent>` recipe handoff across mesh

## What this asserts

Installing the same agent recipe on different mesh nodes must produce equivalent bootstrap state when the nodes share a federated store. This scenario installs the `claude-code` recipe on node-A, then opens a Claude Code session on node-B (same shared store via federation), and asserts that the two recipes resolve to the same managed-block contents and the same boot manifest.

The `ai-memory install <agent>` subcommand is documented in the [v0.6.3.1 release notes](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/releases/v0.6.3.1.md) as a 6-target idempotent installer with `--dry-run` default, `--apply` opt-in, marker-block roundtrip, and `.bak.<rfc3339>` backups. Recipe drift across the mesh would mean one team member's session loads a different memory bootstrap than another's — a category-A regression for the "never lose context" claim.

## Surface under test

- CLI: `ai-memory install claude-code --apply`
- Targets covered (release notes §"What's new"): `claude-code`, `openclaw`, `cursor`, `cline`, `continue`, `windsurf`
- Marker block: `// ai-memory:managed-block:start` … `:end`

## Setup

- 4-node `ironclaw / mTLS` mesh, all v0.6.3.1.
- Node-A and node-B configured with their respective host-side recipe destinations writable but pristine (no prior managed block).
- Federation peers configured so writes on A propagate to B.

## Steps

1. On node-A: `ai-memory install claude-code --dry-run`; capture diff.
2. On node-A: `ai-memory install claude-code --apply`; assert idempotent rerun produces zero-diff.
3. Capture A's managed-block contents and `.bak.<rfc3339>` artefact.
4. On node-B: `ai-memory install claude-code --apply`; capture B's managed-block contents.
5. Compare A's and B's managed-block managed-keys and recipe payload.
6. On both nodes: invoke `ai-memory boot --format json` against the shared store and compare manifests.
7. Round-trip: `ai-memory install claude-code --uninstall --apply` on node-A; assert managed block removed cleanly with no other config edits.

## Pass criteria

- `--dry-run` and `--apply` both exit `0` on every node.
- Managed-block managed-keys list is identical across nodes for the same recipe target.
- The `.bak.<rfc3339>` artefact is created on first apply and not on idempotent rerun.
- World-writable destination is refused (release notes contract).
- JSON-roundtrip validation passes on every install.
- Boot manifest from node-B (after federation sync) matches the agent corpus seeded via node-A's recipe.
- Uninstall round-trip leaves the host config byte-identical to the pre-install state (excepting the backup file).

## Fail modes

- Recipe payload differs between nodes (binary drift — cross-link to S9).
- Managed block applied twice (idempotency regression).
- Backup file not created (release notes guarantee violated).
- World-writable target accepted (security regression).
- Uninstall leaves stray markers or partial config.

## Expected verdict on v0.6.3.1

`GREEN`. The install command's idempotency and marker-block contract are explicit v0.6.3.1 deliverables.

## References

- Release notes — [`v0.6.3.1.md`](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/releases/v0.6.3.1.md)
- Reference recipe — [`docs/integrations/claude-code.md`](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/integrations/claude-code.md)
- Related: S12 (`wrap` cross-vendor), S9 (boot manifest)
