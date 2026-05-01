# S23 — Issue [#507](https://github.com/alphaonedev/ai-memory-mcp/issues/507) `~` expansion in `db` field

## What this asserts

[Issue #507](https://github.com/alphaonedev/ai-memory-mcp/issues/507) — `ai-memory boot` (and by extension `ai-memory doctor`) treat a tilde-prefixed `db` path in `~/.config/ai-memory/config.toml` as a **literal directory component** rather than expanding it to `$HOME` before the SQLite open call. The MCP server (which receives an absolute path via launch args) reads/writes the same DB just fine — the bug is isolated to the CLI's config.toml path resolution.

This scenario asserts that on every mesh node:
1. A `config.toml` with `db = "~/.claude/ai-memory.db"` resolves to `/home/<user>/.claude/ai-memory.db` (or platform-equivalent) before SQLite opens.
2. A `config.toml` with the absolute form `/home/<user>/.claude/ai-memory.db` continues to work.
3. The two forms are interchangeable: swapping between them does not change boot output.
4. `ai-memory doctor`'s Storage section reports `OK` against the tilde-form config (currently it reports `CRIT — failed to open database` per the issue evidence).

This scenario is **expected RED on v0.6.3.1**: Issue #507 is open as of release tag, with the fix scheduled for **Patch 2 (`v0.6.3.2`)**. Including S23 here is the integrity check on the test infrastructure: the harness must detect a defect we already know about before any other verdict is trustworthy.

## Surface under test

- CLI: `ai-memory boot` against tilde-form config
- CLI: `ai-memory doctor` against tilde-form config
- Config field: `[ ] db = "~/..."`
- Path resolution: tilde-expansion before SQLite `open()`

## Setup

- 4-node mesh, ironclaw / mTLS, all v0.6.3.1.
- DB exists at the tilde-expanded path on each node (`$HOME/.claude/ai-memory.db`).
- Two config-file variants per node: `config.toml.tilde` (`db = "~/.claude/ai-memory.db"`), `config.toml.absolute` (`db = "/home/<user>/.claude/ai-memory.db"`).

## Steps

1. On every node: write `config.toml.tilde` as the active config; run `ai-memory boot --format json --quiet`.
2. Capture status variant. **On v0.6.3.1, expect `warn` with `db unavailable` per #507.** A green Patch-2 build would report `ok` or `info-empty`.
3. On every node: write `config.toml.absolute`; rerun `ai-memory boot`. Expect `ok` everywhere on v0.6.3.1 (the absolute path works today).
4. On every node: run `ai-memory doctor --format json` against the tilde-form config. **On v0.6.3.1, expect Storage `CRIT` with the literal-tilde error message.**
5. Confirm interchange: with absolute form, doctor reports Storage `OK`; with tilde form, doctor reports Storage `CRIT`. The test asserts the inequality (the bug) on v0.6.3.1.
6. Capture `db:` field text from the boot manifest in tilde mode; assert it prints the literal `~/.claude/...` (the smoking gun in the issue body).

## Pass criteria

**On v0.6.3.1 (RED, expected):**
- Tilde-form boot returns the `warn` variant on every node.
- Tilde-form doctor returns Storage `CRIT`.
- The `db:` field in the manifest contains a literal `~`.
- Absolute-form configurations continue to work (no regression beyond the documented bug).

**On Patch 2 (GREEN, future):**
- Tilde-form boot returns the same status as absolute-form (both `ok` or both `info-empty`).
- Tilde-form doctor returns Storage `OK`.
- The `db:` field in the manifest contains the expanded absolute path.
- Two forms behave interchangeably across the mesh.

The runner emits the same JSON shape in either case; the harness flips the verdict based on the `expected_verdict` field in `expected.json`. Patch 2 will close this; expected GREEN there.

## Fail modes

On v0.6.3.1, the only fail modes are:
- Tilde-form returns `ok` on some node and `warn` on another (asymmetric — would mean #507 has partial fix on some nodes; suggests binary drift).
- Absolute-form fails (separate, more severe regression).
- The bug is fixed in v0.6.3.1 unannounced (would require closing #507; out of scope for this campaign).

## Expected verdict on v0.6.3.1

`RED`. Issue #507 is open; the fix is scheduled for **Patch 2 (`v0.6.3.2`)**. Patch 2 will close this; expected GREEN there.

## References

- Issue [#507](https://github.com/alphaonedev/ai-memory-mcp/issues/507) — config.toml `db` field tilde-expansion bug
- Release notes — [`v0.6.3.1.md`](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/releases/v0.6.3.1.md)
- Patch 2 funnel — umbrella tracking issue (TBD on `ai-memory-mcp`)
- Related: S9 (boot manifest), S10 (doctor cross-node)
