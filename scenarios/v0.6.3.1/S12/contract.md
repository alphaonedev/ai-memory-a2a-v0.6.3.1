# S12 — `ai-memory wrap <agent>` cross-vendor consistency

## What this asserts

The `ai-memory wrap <agent>` subcommand (release notes §"What's new") is the cross-platform Rust replacement for prior bash/PowerShell wrapper recipes. It spawns a vendor CLI (`codex`, `gemini`, `aider`, `ollama`, …) with the `ai-memory boot` context delivered via the per-vendor strategy: `SystemFlag` / `SystemEnv` / `MessageFile` / `Auto`. This scenario asserts that switching vendors does not change *what context the agent sees* — only *how it is delivered*.

For each of the four documented default vendors (`codex`, `gemini`, `aider`, `ollama`), wrap a no-op probe that echoes whatever boot context it received, then compare the recalled memory set across vendors. The boot recall set must be identical (same memory IDs in the same ranked order) within a tolerance of zero — this is a determinism contract, not a similarity threshold.

## Surface under test

- CLI: `ai-memory wrap <vendor> -- <probe-cmd>`
- Strategies: `SystemFlag` (default `--system <msg>`), `SystemEnv`, `MessageFile`, `Auto`
- Per-vendor lookup table (release notes): `codex` → SystemFlag, `gemini` → SystemFlag, `aider` → MessageFile, `ollama` → SystemEnv

## Setup

- 4-node mesh, ironclaw / mTLS.
- Each node has a stub vendor binary on `$PATH` for each of the four targets — the stub echoes whichever delivery surface it was given (system message, env var, or file contents) to stdout in a structured envelope.
- Shared corpus of ~30 memories pre-seeded via federation.

## Steps

1. On node-A, run `ai-memory wrap codex -- <stub-codex>`; capture the stub's echoed boot context.
2. Repeat for `gemini`, `aider`, `ollama` on the same node.
3. Parse each captured envelope into a normalised `{strategy, payload}` shape.
4. Diff the `payload` field across the four runs — must be byte-identical (the four runs share the same boot manifest; only the envelope wrapper differs).
5. Repeat the four-vendor sweep on node-B; confirm payload still identical to node-A's.
6. Confirm exit codes are propagated end-to-end (exit `7` from a stub returns exit `7` from `wrap`).

## Pass criteria

- All eight runs (4 vendors × 2 nodes) exit `0` on success.
- Captured boot payload is byte-identical across all four vendors on the same node.
- Captured boot payload is byte-identical between node-A and node-B (after federation sync).
- The chosen delivery strategy matches the documented per-vendor default.
- Exit-code propagation: a non-zero exit from the wrapped probe surfaces as the same exit code from `wrap`.

## Fail modes

- One vendor's payload differs from the others (recall non-determinism — cross-link to S15).
- Wrong delivery strategy chosen (e.g. `aider` invoked with `SystemFlag` instead of `MessageFile`).
- Exit code swallowed.
- Cross-node payload divergence (federation drift — cross-link to S9, S15).

## Expected verdict on v0.6.3.1

`GREEN`. The wrap subcommand is one of the five new CLI surfaces and is contract-tested by 49+ integration tests per release notes.

## References

- Release notes — [`v0.6.3.1.md`](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/releases/v0.6.3.1.md)
- Integration matrix — [`docs/integrations/README.md`](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/integrations/README.md)
- Related: S11 (install recipe), S15 (recall determinism)
