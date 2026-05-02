# S31 — SQLCipher AES-256 encryption at rest

## What this asserts

ai-memory v0.6.3.1's release brief lists **SQLCipher AES-256
encryption at rest** as a shipping defence-in-depth feature.
S31 is the substrate canary that proves it on the live mesh —
the database file on disk MUST be opaque to anyone without the
configured passphrase, and the passphrase MUST live in
configuration / environment, not embedded in the binary.

Three orthogonal probes:

1. **Header opaque.** A SQLCipher-encrypted SQLite file does NOT
   start with the well-known `SQLite format 3\x00` magic bytes —
   even the header pages are encrypted. We `head -c 16` the DB
   file and assert it does not begin with that magic.
2. **Plain `sqlite3` rejected.** Stock (non-cipher-aware) sqlite3
   opens the file and tries to read; we expect an error like
   `file is not a database` / `file is encrypted or is not a
   database`. This is the proof that the stored bytes really are
   ciphertext, not a structurally-different format that a future
   sqlite3 would happily read.
3. **Keyed `sqlite3` works.** Same binary BUT with
   `PRAGMA key='<passphrase>'` issued before any other statement
   MUST list the ai-memory tables. If the passphrase comes from
   `/etc/ai-memory-a2a/env` (or `config.toml`) we read it from
   there; we never log it in the runner output.

We additionally assert the passphrase reference is **not embedded
in the binary** (the operator can rotate the passphrase without a
rebuild). We `strings` the `ai-memory` binary and assert the live
passphrase is NOT present as a literal substring.

## Capability gating

If SQLCipher isn't a build flag in this v0.6.3.1 build (the user's
brief calls this out as acceptable), the runner emits
`expected_verdict=NOT_BUILT` with `pass=true` and a
`reasons[]` entry flagging the deviation from the brief — so the
campaign aggregate surfaces the absence loudly rather than
silently green. The detection is two-pronged:

- The DB file's leading 16 bytes ARE the SQLite plain magic
  (`SQLite format 3\x00`), AND
- Stock `sqlite3 <db> .tables` succeeds without a passphrase.

In that combination, the build clearly opted out of SQLCipher.

## Surface under test

- File: `/var/lib/ai-memory/a2a.db` (canonical), or the path in
  `/etc/ai-memory-a2a/env` / `~/.config/ai-memory/config.toml`.
- Binary: `ai-memory` resolved on `$PATH`.
- Tools used: `file(1)`, `head -c`, `xxd`, `sqlite3`, `strings`.
- Configuration: `/etc/ai-memory-a2a/env` (canonical for systemd
  unit) or `~/.config/ai-memory/config.toml`.

## Setup

- 4-node mesh, ironclaw / mTLS, all v0.6.3.1.
- We probe node-1 only (the encryption invariant is local; running
  on every node would just multiply the same evidence). The other
  three are noted as in-scope but not visited unless the node-1
  result is ASYMMETRIC and we want corroboration.

## Steps

1. **Resolve DB path + passphrase reference** on node-1.
   - Check `/etc/ai-memory-a2a/env` for a `*KEY*` /
     `*PASSPHRASE*` / `AI_MEMORY_DB_KEY` entry.
   - If absent, fall back to `~/.config/ai-memory/config.toml` and
     scan for a `key = ` / `passphrase = ` line under
     `[storage]` or `[encryption]`.
   - Resolve DB path: `db = ` line (S23 surface, expected expanded).
2. **Header opaque probe.** `head -c 16 <db> | xxd -p` and assert
   the hex string does NOT start with `53514c69746520666f726d6174203300`
   (which is `SQLite format 3\x00` in hex).
3. **Plain sqlite3 rejected.** `sqlite3 <db> .tables 2>&1` —
   expect a non-zero exit AND output containing `not a database`
   or `encrypted` or `malformed`.
4. **Keyed sqlite3 works.** Issue
   `sqlite3 -cmd "PRAGMA key='<passphrase>'" <db> .tables` and
   assert at least one ai-memory table name appears in the output
   (`memories`, `audit`, `subscriptions`, `pending`, `inbox`, …).
   We accept any of those as proof the keyed open succeeded.
5. **Binary does not embed the passphrase.** `strings $(which
   ai-memory) | grep -F -- "<passphrase>"` MUST find no matches.
   We never echo the passphrase in the runner output.

## Pass criteria

- `db_header_opaque = true`: leading 16 bytes are NOT the SQLite
  plain magic.
- `plain_open_rejected = true`: stock sqlite3 fails with the
  expected diagnostic.
- `keyed_open_works = true`: keyed sqlite3 lists ai-memory tables.
- `passphrase_not_in_binary = true` (best-effort, surfaced in
  outputs but not gating — some builds may legitimately have the
  passphrase derived from a string in a build-time config).

If steps 2 + 3 BOTH show plain (header is SQLite magic + plain
sqlite3 succeeds), we treat the build as `NOT_BUILT` for the
SQLCipher capability — `expected_verdict=NOT_BUILT`, `pass=true`,
and a `reasons[]` entry flags the deviation from the user's brief.

## Fail modes

- DB header is opaque BUT `plain_open_rejected = false`: surface
  inconsistency — the file looks encrypted but stock sqlite3
  reads it. **Critical** — could mean a hash-only or
  keyed-but-default-key surface. Distinguished by the
  `plain_open_diagnostic` output.
- DB header is opaque AND plain rejected, BUT keyed open also
  fails: the passphrase isn't actually the configured one, or
  the configured one is being mishandled by the loader.
  **Critical**.
- Passphrase IS embedded in the binary as a literal: the operator
  cannot rotate it without a rebuild. **High** but informational
  — surfaced in outputs as `passphrase_not_in_binary=false`.

## Expected verdict on v0.6.3.1

`GREEN` if SQLCipher is in the build (opaque header + plain
rejected + keyed works). `NOT_BUILT` (with `pass=true`) if the
build skipped the SQLCipher flag — in which case the runner
flags the deviation so the campaign-aggregate sees it loudly.

## References

- Capabilities inventory: [`docs/capabilities.md`](../../../docs/capabilities.md) §4 Encryption at rest + in transit
- Companion canary: S30 (HMAC-SHA256 over the wire — same crypto primitive used for at-rest tag signing)
- Related: SQLCipher upstream — https://www.zetetic.net/sqlcipher/
- Related: ai-memory secrets management doc — `docs/security.md`
