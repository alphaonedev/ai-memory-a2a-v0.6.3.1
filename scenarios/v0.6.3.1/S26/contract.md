# S26 — Audit tamper detection

## What this asserts

The hash chain in `/var/log/ai-memory/audit.jsonl` is the campaign's tamper
evidence: changing any byte in any line MUST cause `ai-memory audit verify`
to fail with a non-zero rc and an `ok=false` payload that names the line
that broke the chain. S26 asserts that property end-to-end on a live node.

This scenario is **expected GREEN on v0.6.3.1**: tamper detection is the
substrate's headline forensic property. If S26 is RED, the chain is not
acting as a tamper detector and the campaign cannot make any
legal-admissibility claim about the audit trail.

## Surface under test

- CLI: `ai-memory audit verify --format json` rc + payload semantics
- File: `/var/log/ai-memory/audit.jsonl` byte-level mutation
- Substrate property: chain head re-derivation diverges when any line is
  mutated, regardless of which line was touched

## Setup

- Audit log on `node-1` already populated by S25's writes (or by the live
  campaign workflow). If empty, S26 will drive a single write to seed it.
- Append-only flag is removed for the duration of the test (`chattr -a`)
  because non-append byte mutation is what we're testing — without it, no
  process can tamper, so there's nothing to detect. We restore `chattr +a`
  before exit.
- The audit file is backed up to `/var/log/ai-memory/audit.jsonl.s26.bak`
  BEFORE tampering so we can restore + re-verify clean afterward.

## Steps

1. ssh `node-1`:
   - If the audit log doesn't exist or has < 1 line, drive 1 HTTP write to
     populate at least one line.
   - Capture the chain head hash + line count BEFORE tampering (clean
     baseline).
   - Back up the file: `cp audit.jsonl audit.jsonl.s26.bak`.
   - Strip the append-only flag: `chattr -a audit.jsonl` (best-effort; on
     filesystems without attrs it's a no-op and the test still proceeds).
   - Tamper: `printf X | dd of=audit.jsonl bs=1 count=1 conv=notrunc`. This
     overwrites byte 0 (likely the leading `{` of the first JSONL line) so
     the JSON itself becomes invalid AND the line's hash diverges from
     what the chain expects.
   - Re-run `ai-memory audit verify --format json`. Capture rc + payload.
     **Expect rc=2, `ok=false`, payload references a tampered line.**
2. Restore from backup: `cp audit.jsonl.s26.bak audit.jsonl`. Re-run
   verify. **Expect rc=0, `ok=true`** (chain is whole again).
3. Re-apply `chattr +a` (best-effort, matches setup_node.sh's permanent
   posture).

## Pass criteria

**On v0.6.3.1 (GREEN, expected):**
- Tamper-phase rc != 0 (expected 2 per release notes; we accept any
  non-zero rc as long as `ok=false`).
- Tamper-phase payload has `ok=false`.
- Tamper-phase payload mentions tamper / chain break in some recognizable
  field (`tamper_detected`, `error`, `failed_line`, etc. — schema varies
  by build, so we accept the union and report what we found).
- Restore-phase rc=0 AND `ok=true` (chain is whole again).

If tamper detection fires AND restore succeeds, S26 passes.

## Fail modes

- Tamper-phase rc=0 (chain didn't detect the mutation — tamper detector
  is broken).
- Tamper-phase payload has `ok=true` (verify thinks chain is fine despite
  byte mutation).
- Restore-phase rc != 0 even after byte-exact restore from backup
  (suggests the restore path itself is broken, but still indicates the
  test infrastructure cannot reset cleanly between S26 runs).

## Expected verdict on v0.6.3.1

`GREEN`. Tamper detection is the load-bearing legal-admissibility
property. If RED, the audit substrate's primary value claim — "you cannot
silently rewrite history" — is false on v0.6.3.1.

## References

- `docs/forensic-audit.md`
- `scripts/setup_node.sh` audit-watcher (for `chattr +a` posture)
- ai-memory release notes — `v0.6.3.1` audit verify rc semantics
- Related: S25 (clean-chain integrity), S27 (append-only enforcement)
