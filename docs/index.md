# ai-memory A2A — v0.6.3.1

**Per-release agent-to-agent integration certification** for [ai-memory v0.6.3.1](https://github.com/alphaonedev/ai-memory-mcp/releases/tag/v0.6.3.1).

## Verdict

| Verdict | Run | Cert cell | Cells green | Last updated |
|---|---|---|---|---|
| `PENDING` | r0 | ironclaw / mTLS | 0 / 9 | 2026-04-30 |

Verdict updates automatically from [`releases/v0.6.3.1/summary.json`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/releases/v0.6.3.1/summary.json) once the first campaign run completes.

## Matrix

| Framework | `off` | `TLS` | `mTLS` |
|---|---|---|---|
| **ironclaw** | regression | regression | **CERT cell** |
| **hermes** | regression | regression | regression |
| **openclaw** | regression | regression | regression |
| mixed | regression | regression | stretch |

## Scenarios

[**Class A — carry-forward** (S1 – S8)](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/carry-forward) — eight base scenarios from the [umbrella testbook](https://github.com/alphaonedev/ai-memory-ai2ai-gate). Must remain green from v0.6.3 cert.

[**Class B — v0.6.3.1-specific** (S9 – S24)](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/scenarios/v0.6.3.1) — sixteen new scenarios for new surfaces (`boot`, `install`, `wrap`, `logs`, `audit verify`, `doctor`), recovered commitments (`budget_tokens`, capabilities v2), and absorbed audit findings (G4, G5, G6, G9, G13).

`S23` and `S24` are **expected RED** on v0.6.3.1 — they correspond to known-open defects ([#507](https://github.com/alphaonedev/ai-memory-mcp/issues/507) and [#318](https://github.com/alphaonedev/ai-memory-mcp/issues/318)) that will close in Patch 2 (`v0.6.3.2`). Their inclusion proves the harness detects defects we already know about.

## Reproducing

Local docker mesh:
```sh
cd harness && docker compose -f docker-compose.local.yml up
```

DigitalOcean (4-node real mesh): see [`harness/terraform/`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/harness/terraform).

## Cross-links

- [umbrella spec](https://github.com/alphaonedev/ai-memory-ai2ai-gate)
- [ship-gate (pre-flight)](https://github.com/alphaonedev/ai-memory-ship-gate)
- [test-hub (aggregator)](https://alphaonedev.github.io/ai-memory-test-hub/)
- [ai-memory-mcp (subject)](https://github.com/alphaonedev/ai-memory-mcp)
- [Patch 2 seed: #507](https://github.com/alphaonedev/ai-memory-mcp/issues/507)
- [Patch 2 candidate: #318](https://github.com/alphaonedev/ai-memory-mcp/issues/318)
