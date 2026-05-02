# Forensic audit trail

ai-memory v0.6.3.1 ships an **opt-in (default OFF)** forensic audit substrate.
When the campaign turns it on (every campaign in this repo does — see
[`scripts/setup_node.sh`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/scripts/setup_node.sh)),
every memory operation lands one hash-chained, schema v1, JSONL line in
`/var/log/ai-memory/audit.jsonl` on the node where it executed.

The trail is the campaign's **legal-admissibility evidence**. If a regulator,
auditor, or counterparty asks "show me, byte-by-byte, that this NHI memory
operation actually happened, that the agent_id stamp is real, and that no one
has rewritten the record since" — this is the answer.

---

## The five properties tested

The forensic-audit harness tests five distinct properties. Each is a
separately-reproducible scenario; together they constitute the substrate's
admissibility claim.

| # | Property | Test | Why it matters legally |
|---|---|---|---|
| 1 | **Hash-chain integrity over a populated log** | [S25](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/scenarios/v0.6.3.1/S25/contract.md) | The chain is the proof: any line can be re-derived from its predecessor's hash. A trail that doesn't chain isn't evidence — it's a list. |
| 2 | **Tamper detection on byte mutation** | [S26](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/scenarios/v0.6.3.1/S26/contract.md) | If you can silently rewrite a line, the trail is worthless. S26 mutates one byte and asserts `ai-memory audit verify` returns `rc=2, ok=false`. |
| 3 | **OS-level append-only enforcement (`chattr +a`)** | [S27](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/scenarios/v0.6.3.1/S27/contract.md) | Defence in depth: even root cannot overwrite or truncate without first running `chattr -a`. The kernel — not the application — enforces it. |
| 4 | **Forensic reproducibility (Phase 3 ↔ audit)** | [Scenario I](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/scripts/phase3_autonomous.py) | Every NHI memory operation in Phase 3 must have a 1:1 matching audit entry, with `agent_id`, `action`, `namespace`, and timestamp byte-exact. |
| 5 | **Forged-provenance detection** | [Scenario J](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/scripts/phase3_autonomous.py) | A memory whose CONTENT lies about authorship is detected by the audit log's stamped provenance. The audit log is the source of truth; the body is not. |

Substrate canaries S25/S26/S27 prove the substrate. Phase 3 Scenarios I/J
prove the NHI-layer behaviour an external auditor would actually run — pulling
the audit log over ssh, cross-correlating it against the agent's claimed
operations, and flagging any discrepancy.

---

## How the chain works

Each line in `/var/log/ai-memory/audit.jsonl` is a JSON object with at minimum:

```json
{
  "schema_version": 1,
  "timestamp": "2026-04-30T12:34:56Z",
  "agent_id": "ai:alice",
  "action": "memory_store",
  "namespace": "phase3/I/stdio-1",
  "key_or_query": "stdio-1",
  "content_sha256": "<hex>",
  "previous_chain_hash": "<hex>",
  "chain_hash": "<hex>"
}
```

`chain_hash` is the SHA-256 of the canonical JSON serialization of the line
*minus* the `chain_hash` field, *plus* the previous line's `chain_hash`.
`ai-memory audit verify` walks the file from the top, recomputing each line's
hash and comparing it to the stored `chain_hash`. If any line was mutated, the
recomputed hash diverges and verify exits non-zero.

The first line's `previous_chain_hash` is the all-zero seed.

---

## OS-level append-only

On Linux ext2/3/4/btrfs (every campaign droplet), `setup_node.sh` applies
`chattr +a /var/log/ai-memory/audit.jsonl` after the file is created by
ai-memory's first audit-emitting write. With `+a` set:

- `open(O_WRONLY)` without `O_APPEND` returns `EPERM` for **everyone**
  including root.
- `truncate(2)`, `unlink(2)`, and renames-onto returns `EPERM`.
- The file CAN be appended to (because `ai-memory` opens with `O_APPEND`).
- Removing `+a` requires `CAP_LINUX_IMMUTABLE` (root with the capability).

On macOS (campaign Orchestrator only — droplets are Linux), the equivalent is
`fs_chflags UF_APPEND`.

On filesystems that don't support attributes (overlayfs, some container
roots), `chattr +a` is a no-op. S27 detects that case and degrades to
chain-only enforcement (S26 still detects tamper after the fact, but tamper
is no longer prevented at write time). The legal-admissibility claim is
weaker in that mode but not zero.

---

## Compliance presets

ai-memory's audit config supports compliance flags that change the
chain-hash computation and field set to match common audit-trail standards:

```toml
[audit]
enabled = true
path = "/var/log/ai-memory/audit.jsonl"
schema_version = 1
hash_chain = true
append_only = true
redact_content = false  # campaign uses synthetic test data; redaction would break forensic reproducibility

[audit.compliance.soc2]
applied = true
```

Other presets ai-memory ships:

- **HIPAA** (`[audit.compliance.hipaa]`) — adds `accessor_id` field, requires
  6-year retention metadata.
- **GDPR** (`[audit.compliance.gdpr]`) — adds `subject_data_categories`,
  enables right-to-erasure metadata bridge.
- **FedRAMP** (`[audit.compliance.fedramp]`) — Moderate baseline AU-2/AU-3/
  AU-12 alignment; adds `event_classification`.

The campaign uses **SOC 2** because the campaign artefacts are AlphaOne
internal trust evidence, not a regulated workload. A regulated deployment
would enable the appropriate preset(s) instead. The campaign tests the
substrate property — whichever compliance preset is on, hash-chain integrity
and append-only enforcement work the same way.

---

## What the auditor sees

A regulator or enterprise buyer reproducing this campaign would:

1. Pull the [audit logs](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/runs)
   under `runs/<campaign_id>/audit/node-{1,2,3,4}.audit.jsonl`.
2. Run `ai-memory audit verify --format json` against each. **Every node
   must return `rc=0, ok=true`**.
3. Open `runs/<campaign_id>/phase4-analysis.json` and read the
   `audit_forensics` block: per-node chain heads, op-to-audit match rate,
   forged-provenance detection rate.
4. For each Phase 3 `phase3-<scenario>-<arm>-runN.json`, walk the
   `records[*].ai_memory_ops` array and confirm each `write` has a matching
   audit entry.
5. Read the `legal_admissibility_summary` field — a deterministic prose
   summary of what was proven.

The summary is published per-run on [Forensic audit per-run matrix](forensics/index.md);
the most recent run's narrative cross-references the substrate canary
verdicts and the Phase 3 I/J scenario outcomes.

---

## References

- [`scripts/setup_node.sh`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/scripts/setup_node.sh) — audit-config write + chattr watcher
- [`scenarios/v0.6.3.1/S25/`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S25) — hash-chain integrity over a populated log
- [`scenarios/v0.6.3.1/S26/`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S26) — tamper detection
- [`scenarios/v0.6.3.1/S27/`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S27) — append-only enforcement
- [`scripts/phase3_autonomous.py`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/scripts/phase3_autonomous.py) — Phase 3 scenarios I (forensic reproducibility) and J (forged-provenance detection)
- [`scripts/phase4_meta_analyst.py`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/scripts/phase4_meta_analyst.py) — `audit_forensics` block computation
- [governance Principle 8 — Audit Trail Governance](governance.md#principle-8-audit-trail-governance-forensic-reproducibility) — campaign-level posture
