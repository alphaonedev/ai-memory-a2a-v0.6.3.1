# S27 — Append-only enforcement (OS-level chattr +a)

## What this asserts

The audit trail's tamper resistance is two-layered:

1. The hash chain catches retroactive mutations (S26).
2. The OS append-only flag (`chattr +a` on Linux, `fs_chflags UF_APPEND`
   on macOS) prevents the mutation from happening in the first place at
   the kernel level — even root cannot overwrite or truncate the file
   without first running `chattr -a`.

S27 asserts that on `node-1`'s `/var/log/ai-memory/audit.jsonl`:

1. The append-only attribute IS set (`lsattr` shows `a` in the flag
   string).
2. A non-root user cannot overwrite the file (`Operation not permitted`).
3. Root cannot overwrite or truncate via non-append IO either (`dd` with
   `conv=notrunc` at offset 0 fails; `> file` fails; `truncate` fails).
4. **Append still works** — the legitimate write path (issuing a memory
   op via HTTP) DOES land a new line in the audit log. We confirm the
   line count increases.

This scenario is **expected GREEN on v0.6.3.1** when the underlying
filesystem supports `chattr +a`. On overlayfs / containers / non-ext
filesystems, `chattr +a` is a no-op and S27 cannot enforce — the runner
detects this case, sets `outputs.chattr_supported = false`, and reports
`actual_verdict=GREEN with caveat` (pass=true, but with a `reasons` entry
calling out the unenforceable substrate). See `docs/forensic-audit.md`
§3 for the chain-only fallback property.

## Surface under test

- Linux `chattr` / `lsattr` (e2fsprogs)
- File: `/var/log/ai-memory/audit.jsonl`
- HTTP write path → audit hook → append-only-respecting append
- Negative: `dd of=audit.jsonl ... conv=notrunc` (root, non-append)
- Negative: `su nobody -c "echo X > audit.jsonl"` (non-root)

## Setup

- Audit log already exists on `node-1` and `setup_node.sh`'s audit-watcher
  has applied `chattr +a` after the first write.
- If the log doesn't exist at S27 start, a single seed write is issued
  (mirrors S26).

## Steps

1. ssh `node-1`:
   - Confirm `lsattr /var/log/ai-memory/audit.jsonl` returns a flag string
     containing `a`. Capture that string. If `lsattr` itself fails (no
     e2fsprogs / unsupported fs), set `chattr_supported=false` and skip
     the negative-write asserts (they would all "pass" trivially on a
     filesystem with no enforcement).
   - Capture line count before any writes.
2. **Negative write — non-root**:
   - `su nobody -s /bin/sh -c "echo X > /var/log/ai-memory/audit.jsonl"`.
     Expect non-zero exit AND error message containing
     `Operation not permitted` or `Permission denied`.
3. **Negative write — root non-append**:
   - `dd if=/dev/urandom of=/var/log/ai-memory/audit.jsonl bs=1 count=1 conv=notrunc`.
     Expect non-zero exit (chattr +a blocks even root).
   - Also try `truncate -s 0 /var/log/ai-memory/audit.jsonl` to confirm
     truncate is also blocked.
4. **Positive append (legitimate write path)**:
   - Issue 1 HTTP write to `/api/v1/memories`. Settle 1s. Re-count lines.
     Expect line count +1 (or more, if S27 races other audit-emitting
     ops — we accept anything strictly greater than the pre-write count).
5. Pass = (non-root write blocked) AND (root non-append blocked) AND
   (append legitimate write incremented line count). On a filesystem
   without chattr support, pass = (legitimate append worked) AND a
   note flags `chattr_supported=false`.

## Pass criteria

**On v0.6.3.1 (GREEN, expected, with chattr-supporting fs):**
- `lsattr` flag string contains `a`.
- Non-root overwrite fails.
- Root non-append `dd` and `truncate` fail.
- HTTP write increments the line count.

**On v0.6.3.1 (GREEN with caveat, non-chattr fs):**
- `lsattr` returns "operation not supported" (or empty on unsupported
  fs).
- HTTP write still increments the line count.
- `outputs.chattr_supported = false`; `reasons` flags the substrate
  cannot enforce.

## Fail modes

- `lsattr` shows the flag is missing on a chattr-supporting fs (the
  setup_node.sh watcher never applied it; the file is unprotected).
- Non-root write SUCCEEDS despite chattr +a being set (kernel /
  filesystem has a known append-only-bypass bug — high-severity
  finding).
- HTTP write does NOT increment the line count (audit hook is broken;
  S25 should have caught this but S27 confirms independently).
- Root non-append dd/truncate SUCCEEDS (chattr +a is being silently
  applied as a no-op).

## Expected verdict on v0.6.3.1

`GREEN`. The OS-level append-only flag is the second of two
load-bearing tamper-resistance claims. If RED, the campaign falls back
to the hash chain alone (S26 still detects, but tamper is no longer
prevented at write time).

## References

- `docs/forensic-audit.md` §3 — OS append-only as the prevention layer
- `scripts/setup_node.sh` audit-watcher — applies `chattr +a` after
  first write
- ai-memory release notes — `v0.6.3.1` documents `append_only = true`
  as the config flag triggering setup_node.sh's chattr posture
- Related: S25 (chain integrity), S26 (chain-break detection)
