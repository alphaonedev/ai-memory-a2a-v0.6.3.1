# Capability domains in ai-memory v0.6.3.1

ai-memory v0.6.3.1 ships **eight capability domains** beyond the
testbook S1–S42 substrate matrix. This page is the inventory: each
domain is described by what it does, why it matters in production
agent systems, and which substrate canary (or canaries) probes it
on the live mesh.

The naming convention `S<N>` in this page refers to **substrate
canaries** living at `scenarios/v0.6.3.1/S<N>/` — distinct from the
testbook scenarios at `docs/scenarios/`. The substrate canary for a
domain probes the documented behaviour holds on the live 4-node
mesh; the testbook scenarios cover the canonical user flows.

| # | Domain | Substrate canary | Status on v0.6.3.1 |
|---|---|---|---|
| 1 | NHI / Agent identity | [S28](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S28) | live, runtime-tested |
| 2 | Governance — approval gate | [S29](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S29) | live, runtime-tested |
| 3 | A2A messaging | [S30](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S30) | live, runtime-tested |
| 4 | Encryption at rest + in transit | [S31](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S31) (SQLCipher) | live, runtime-tested (SQLCipher); transit covered by F6/F7 |
| 5 | Architecture tiers T1–T5 | — | documented; T1–T3 ship + quorum-write federation; T4 partial; T5 vision |
| 6 | Surface area (133 operations) | — | documented; covered piecewise by testbook S1–S42 |
| 7 | Knowledge graph | — | documented; covered by S38–S42 (recursive CTE, KG timeline, KG invalidate) |
| 8 | Operational modes | — | documented; covered by [baseline](baseline.md) (foreground stdio, HTTP daemon, sync daemon, curator daemon) |

---

## 1. NHI / Agent identity

**What it does.** Every memory carries `metadata.agent_id` set to
the writer-of-record at the moment of admission. ai-memory enforces
**defence-in-depth immutability** of that field across every
mutation surface an attacker (or a buggy peer) could plausibly use
to rewrite history:

- `memory_update` / `PUT /api/v1/memories/<id>` — a later writer
  cannot rewrite the original `agent_id`. `updated_at` and
  `update_count` MAY bump; the NHI bind stays sticky.
- `memory_consolidate` / dedup — when two writes with identical
  content but different `agent_id` collide, both writers appear
  in the consolidated row's source-agent provenance.
- Federation sync (fanout) — the relayed copy on a peer carries
  the **origin** `agent_id`, not the relaying peer's.
- `memory_import` — the import path round-trips `agent_id`
  byte-for-byte; restore-from-backup does not rewrite NHI.

**Why it matters.** Without this invariance, downstream governance
(approval gate, audit trail, prime-directive enforcement) loses its
identity anchor: an adversarial peer could rewrite the writer-of-
record on every convergence cycle and "ai:alice wrote this" silently
becomes "node-2 wrote this" or "ai:bob wrote this". The audit trail
is then chronologically intact but evidentially worthless.

**What probes it.** [S28](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S28) — runs the four invariants on the live mesh.

---

## 2. Governance — approval gate

**What it does.** A namespace-scoped policy holds writes in
`state=Pending` until a distinct NHI agent (typically
`ai:operator`, `role=admin`) explicitly Approves or Denies them.
The full matrix is **3 actions × 4 approval levels × 3 approver
types = 36 verdict shapes**:

- **Actions:** Allow (write into Memory), Deny (write rejected,
  audit-logged), Pending (write held for human review).
- **Approval levels:** auto-allow, soft (single approver), hard
  (quorum N-of-M), forensic (immutable + signed).
- **Approver types:** human, agent (with role=admin), system
  (curator daemon under policy).

Decisions propagate across federation: a single approve/deny on
node-1 settles the queue across the entire mesh — the pending list
on every peer clears the moment the decision lands.

**Why it matters.** The approval gate is the substrate's enforcement
point for organisational policy. Without federation-aware
propagation, an attacker could race the approval by writing to a
peer that hasn't seen the deny yet. With it, "Deny" is a
write-once boundary across the whole convergence domain.

**What probes it.** [S29](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S29) — exercises both happy-path approve and reject across two peer nodes.

---

## 3. A2A messaging

**What it does.** Three coordinated primitives let agents address
each other directly without a sidecar message bus:

- `memory_notify` — agent X sends a notification to agent Y (or to
  a namespace pattern). Returns a `notification_id`.
- `memory_inbox` — agent Y polls or pages its own inbox for unread
  notifications.
- `memory_subscribe` — agent Y registers a subscription
  (typically a namespace glob) so future writes/notifies that
  match are pushed without polling.

On top of those, **HMAC-SHA256-signed webhooks** support the
push-notification path: every emitted notification is POSTed to a
configured URL with `X-AIM-Signature: sha256=<hex>`. The receiver
recomputes HMAC-SHA256(secret, body) and compares constant-time.
Any mismatch ⇒ forged or tampered in transit.

The notify path is **federation-aware**: calling `memory_notify`
on node-1 with a target whose subscription lives on node-3 fans
out across the W=2/N=4 quorum without the caller having to know
which peer hosts the subscription.

**Why it matters.** A2A messaging makes ai-memory a coordination
substrate, not just a memory store. Two agents can agree on a
plan, hand off a task, or signal "I'm done" — without sharing
private channels, dedicated orchestration layers, or any shared
code beyond the MCP interface. The HMAC-signed webhook layer
ensures the push path is integrity-protected end-to-end.

**What probes it.** [S30](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S30) — notify + inbox + subscribe + HMAC verification + federation fanout.

---

## 4. Encryption at rest + in transit

ai-memory v0.6.3.1 lays five complementary layers of integrity /
confidentiality:

1. **SQLCipher AES-256 at rest.** The on-disk DB is opaque to
   anyone without the configured passphrase; stock `sqlite3`
   cannot read it. The passphrase is loaded from
   `/etc/ai-memory-a2a/env` or `config.toml`, never embedded in
   the binary.
2. **mTLS 1.3 with fingerprint allowlist.** Every peer connection
   carries a client certificate; rustls rejects any handshake
   whose fingerprint is not on the allowlist. Probed by F6/F7
   (TLS handshake + mTLS enforcement) in the baseline.
3. **HMAC-SHA256 webhooks.** Every webhook delivery is signed with
   the per-subscription shared secret. Same primitive as §3 but
   applied at the at-rest tag layer too.
4. **GPG-signed release tags.** `git tag -s v0.6.3.1` is signed
   with the AlphaOne release key; downstream consumers can verify
   provenance before extracting the tarball.
5. **SBOM + reproducible builds.** The release tarball ships an
   SPDX SBOM and a `BUILD_REPRO.md` recipe; two independent
   builds of the same source tag MUST produce byte-identical
   binaries (verified out-of-band by the release process).

**Why it matters.** Defence in depth: an attacker who steals the
DB file gets ciphertext; an attacker on the wire gets rejected at
TLS; an attacker in the supply chain gets caught by SBOM diff or
reproducible-build mismatch.

**What probes it.** [S31](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1/S31) — SQLCipher (header opaque, plain rejected, keyed works, passphrase not in binary). Layers 2 + 3 covered by F6/F7 + S30. Layers 4 + 5 are release-process invariants verified out-of-band.

---

## 5. Architecture tiers T1–T5

ai-memory documents **five architecture tiers** spanning single-
laptop deployments to a global hive:

| Tier | Topology | Status on v0.6.3.1 |
|---|---|---|
| **T1** | Single laptop, foreground stdio (MCP) | ships; baseline default |
| **T2** | Single host, HTTP daemon (mTLS-aware) | ships; baseline `tls=on/mtls` |
| **T3** | Multi-host federation, W-of-N quorum sync | ships; campaign topology (W=2/N=4) |
| **T4** | Cross-region federation with cold-store tier | partial; cold-store hooks present, region-aware quorum is roadmap |
| **T5** | Global hive, planet-scale eventual consistency | vision; documented in [roadmap](roadmap.md) |

Deployment recipes + topology SVGs live in the
[ai-memory-mcp docs](https://github.com/alphaonedev/ai-memory-mcp).

**Why it matters.** Tiering lets an operator pick the smallest
viable footprint for their use case without forking the codebase.
A T1 dev laptop, a T3 production cluster, and a T5 federation
all run the same binary; only the daemon flags and config layout
differ.

**What probes it.** Tier T1–T3 is exercised by every campaign run;
the campaign topology is itself a T3 deployment (4 nodes, W=2/N=4).
T4–T5 are not runtime-tested in this campaign — documented as
forward-looking in the [v1.0 GA criteria](v1-ga-criteria.md).

---

## 6. Surface area (43 + 50 + 40 = 133 operations)

ai-memory v0.6.3.1 exposes **133 operations** across three
interface surfaces:

| Surface | Count | Scope |
|---|---|---|
| MCP tools | 43 | `memory_store`, `memory_recall`, `memory_consolidate`, `memory_link`, `memory_kg_query`, `memory_subscribe`, `memory_inbox`, `memory_notify`, `memory_pending_*`, `memory_namespace_*`, `memory_archive_*`, `memory_kg_*`, `memory_session_start`, `memory_capabilities`, `memory_check_duplicate`, `memory_detect_contradiction`, `memory_expand_query`, `memory_get_taxonomy`, `memory_auto_tag`, `memory_promote`, `memory_forget`, `memory_gc`, `memory_get_links`, `memory_kg_invalidate`, `memory_kg_timeline`, `memory_entity_*`, `memory_agent_register`, `memory_agent_list`, `memory_inbox`, `memory_search`, etc. |
| HTTP endpoints | 50 | `/api/v1/memories`, `/api/v1/memory/pending`, `/api/v1/notify`, `/api/v1/inbox`, `/api/v1/subscriptions`, `/api/v1/namespaces`, `/api/v1/audit`, `/api/v1/entities`, `/api/v1/kg/*`, `/api/v1/admin/*`, etc. |
| CLI commands | 40 | `ai-memory boot`, `ai-memory doctor`, `ai-memory wrap`, `ai-memory audit verify`, `ai-memory mcp`, `ai-memory peer add`, `ai-memory namespace policy`, `ai-memory kg traverse`, etc. |

A cross-reference matrix maps every MCP tool to its HTTP and CLI
analogue (where one exists) — see [`tests.md`](tests.md) and the
testbook for the canonical surface coverage.

**Why it matters.** The three surfaces are not independent — they
all hit the same SQLite file via the same coordinator. But they
expose different ergonomic profiles: MCP for in-process LLM tools,
HTTP for cross-process federation + UI, CLI for ops + scripts.
Coverage holes in any one surface (e.g. #318 — MCP stdio writes
bypass fanout) are surface-specific bugs, not substrate bugs.

**What probes it.** Testbook S1–S42 covers the canonical user
flows; per-tool MCP coverage is broken out in
[testbook Suite H](testbook.md). Substrate canaries S23, S24,
S25, S26, S27, S28, S29, S30, S31 probe specific cross-surface
invariants.

---

## 7. Knowledge graph

**What it does.** ai-memory ships a knowledge-graph layer on top
of the memory store:

- **Recursive CTE traversal** with cycle detection — depth-bounded,
  visited-set pruned, so a malformed graph cannot OOM the daemon.
- **Bitemporal filters** — every edge carries (`valid_from`,
  `valid_to`) AND (`recorded_at`, `superseded_at`) so queries can
  reconstruct "what did the graph look like at time T as of
  reporting time R". Useful for forensic replays.
- **Entity registry + alias resolution** — `memory_entity_register`
  + `memory_entity_get_by_alias` give a stable canonical id even
  as labels drift across agents.
- **KG timeline** — `memory_kg_timeline` returns the ordered
  history of edges touching a node.
- **KG invalidate** — `memory_kg_invalidate` marks a subgraph
  superseded without deleting it (audit-preserving).

**Why it matters.** The KG layer turns ai-memory from a key-value
store into a queryable evidence base. An auditor can walk
"who-said-what-about-X-as-of-Tuesday" without having to merge a
flat memory list against an external graph database.

**What probes it.** Testbook S38–S42 (`memory_kg_*` family) and
the substrate-level entity / alias resolution checks in baseline
v1.4.0. Not currently runtime-tested as a substrate canary in
this campaign — documented for completeness.

---

## 8. Operational modes

ai-memory runs in **four operational modes**, all from the same
binary:

| Mode | Command | What it does |
|---|---|---|
| **Foreground stdio (MCP)** | `ai-memory mcp` | speaks JSON-RPC over stdio; the canonical surface for LLM tool-use |
| **HTTP daemon** | `ai-memory serve` (mTLS-aware) | exposes the 50-endpoint HTTP API; takes peer connections |
| **Sync daemon** | `ai-memory sync` | runs the W-of-N quorum write coordinator + federation fanout |
| **Curator daemon** | `ai-memory curate` | auto-tag + contradiction detection + consolidation, scheduled or event-driven |

A production T3 deployment runs three of the four (`serve` +
`sync` + `curate`); a T1 dev box runs only `mcp` (the other three
are subprocesses spawned on demand).

**Why it matters.** The modes are intentional separation of
concerns — the curator can be paused for a forensic snapshot
without losing recall; the sync daemon can be restarted without
disrupting in-flight MCP sessions. Each is independently
observable (own systemd unit, own log stream, own healthcheck).

**What probes it.** Each mode has at least one baseline probe
(F1–F7 in [`baseline.md`](baseline.md)), and the curator
contradiction-detection path is tested by Phase 3 scenario D
(behavioral propagation under contradiction). Not currently
runtime-tested as a single substrate canary — documented for
completeness; could be promoted to S32+ if a regression motivates
it.

---

## Cross-domain notes

- **Audit trail (forensic).** S25 / S26 / S27 (parallel substrate
  canaries) prove the audit log is hash-chained, tamper-detecting,
  and OS-level append-only. Every write surfaced by domains 1–3
  above lands a hash-chained line keyed by `agent_id`, so the
  forensic surface is the **enforcement point** for all the
  invariants on this page.
- **Prime Directive.** Phase 3 scenarios E–H probe whether the
  Prime Directive (immutable in `system/governance/prime-directive`)
  is correctly enforced by agents reading from ai-memory. The
  approval gate (domain 2) is the substrate's enforcement
  primitive; Prime Directive scenarios test the **NHI behaviour**
  on top of it.
- **Patch 2 funnel.** Bugs against any of these domains funnel
  into the [findings tracker](findings.md) and become Patch 2
  (`v0.6.3.2`) candidates. S23 (#507) and S24 (#318) are the two
  canaries currently green-RED on this campaign.

---

## How to add a new capability domain

1. Write a contract.md, expected.json, runner.sh under
   `scenarios/v0.6.3.1/S<N>/` (mirror S28–S31 patterns).
2. Add the runner id to `.github/workflows/a2a-gate.yml`'s
   "Run v0.6.3.1-specific expected-RED canaries" loop.
3. Add a row to the table at the top of this file describing
   what it tests and why.
4. Reference the new canary from at least one Domain section.
5. Update [`docs/index.md`](index.md)'s "Full-spectrum test
   landscape" matrix if it changes the surface count.

The substrate-canary pattern keeps capability claims honest:
every domain documented here either has a runner that passes on
every dispatch, or is explicitly flagged as documented-but-not-
runtime-tested.
