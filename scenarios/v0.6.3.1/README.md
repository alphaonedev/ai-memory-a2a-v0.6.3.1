# Class B — v0.6.3.1-specific scenarios

Sixteen scenarios for surfaces shipped in [v0.6.3.1](https://github.com/alphaonedev/ai-memory-mcp/releases/tag/v0.6.3.1).

| ID | Surface | What it asserts | Default cell |
|---|---|---|---|
| S9 | `ai-memory boot` multi-node | Boot manifest agreement on `version`, `schema_version`, `tier` across 4 nodes. | ironclaw / mTLS |
| S10 | `ai-memory doctor` cross-node | Doctor sections agree (in-flight delta tolerated); asymmetric warnings surface. | ironclaw / mTLS |
| S11 | `ai-memory install <agent>` recipe handoff | Recipes installed at different nodes share the same store cleanly. | ironclaw / mTLS |
| S12 | `ai-memory wrap <agent>` cross-vendor | Boot context delivered for codex / gemini / aider / ollama. | ironclaw / mTLS |
| S13 | `ai-memory audit verify` tamper-evident | Hash chain verifies independently per node; corruption detected. | ironclaw / mTLS |
| S14 | `ai-memory logs` operator surface | Filters work uniformly; privacy default OFF holds. | ironclaw / mTLS |
| S15 | **R1** `budget_tokens` recall | Same query + budget on federated peers → same ranked head. | ironclaw / mTLS |
| S16 | **Capabilities v2** honesty cross-mesh | Asymmetric capabilities surface, never absorb. | ironclaw / mTLS |
| S17 | **G9** webhook fanout | link / promote / delete / consolidate fire from any originating node. | ironclaw / mTLS |
| S18 | **G4** embedding-dim integrity | Mixed-dim writes refused at boundary. | ironclaw / mTLS |
| S19 | **G5** archive/restore preserves embeddings | Archive at A → restore at B keeps embedding + tier + expiry. | ironclaw / mTLS |
| S20 | **G6** `on_conflict` policy | Concurrent same-key writes → deterministic outcome per policy. | ironclaw / mTLS |
| S21 | **G13** endianness magic byte | x86_64 + arm64 mesh exchanges f32 BLOBs cleanly. | mixed-arch / mTLS |
| S22 | Schema **v19** migration | Heterogeneous mesh; warn manifest fires on mismatch. | ironclaw / mTLS |
| **S23** | **#507** `~` expansion | Tilde in `db` field expanded before SQLite open. | ironclaw / mTLS — **expected RED** |
| **S24** | **#318** MCP stdio fanout | MCP stdio writes trigger federation fanout. | ironclaw / mTLS — **expected RED** |

Each scenario gets its own subdirectory `S<id>/` with:
- `contract.md` — what passes / fails
- `runner.sh` (or `runner.py`) — the actual test
- `fixtures/` — minimal reproducible state
- `expected.json` — pass criteria

Status: README only. Scenario implementations pending.
