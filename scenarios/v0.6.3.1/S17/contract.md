# S17 — G9 webhook fanout on link / promote / delete / consolidate

## What this asserts

Audit finding **G9** ([ROADMAP2 §5.4](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#54-substantive-gaps-and-bugs-priority-ordered)) — pre-v0.6.3.1, webhooks fired on `memory_store` only; promote / delete / link / consolidate were silent. v0.6.3.1 wires `dispatch_event` into all four additional paths while keeping the existing signing / SSRF protections intact ([ROADMAP2 §7.2](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#72-v0631--honesty-patch--recovered-commitments--doc-currency--q2-2026-4-weeks)).

This scenario asserts that each of the four newly-wired events fires exactly once per operation, regardless of which mesh node originates the operation, with the existing HMAC signature verifying and SSRF protections still rejecting loopback/private-net targets.

## Surface under test

- MCP tools: `memory_link`, `memory_promote`, `memory_delete`, `memory_consolidate`
- Internal: `dispatch_event(...)` fanout
- Webhook config: HMAC signing key, allowed-target list (SSRF guard)

## Setup

- 4-node mesh, ironclaw / mTLS.
- A test webhook receiver runs on a fifth host (out of mesh) and exposes a public-net URL with HMAC signature verification.
- Webhooks configured on every mesh node to POST to the receiver.
- A second receiver target points at `127.0.0.1` to exercise the SSRF guard.

## Steps

1. From node-A: invoke `memory_link(source, target, kind="related_to")`; assert the receiver gets one signed POST with `event=link.created` (or equivalent).
2. From node-B: invoke `memory_promote(id, "long")`; assert one signed POST with `event=promote`.
3. From node-C: invoke `memory_delete(id)`; assert one signed POST with `event=delete`.
4. From node-D: invoke `memory_consolidate({...})`; assert one signed POST with `event=consolidate`.
5. Verify HMAC signature on every received POST.
6. Configure a webhook with a `127.0.0.1` target; trigger any event; assert the SSRF guard rejects the dispatch (no POST hits loopback).
7. Verify each event fires **once** — no duplication, no silent absorb.

## Pass criteria

- One signed POST per operation per event type, on every originating-node permutation.
- HMAC signature verifies on every received POST.
- SSRF guard rejects loopback / private-net targets without dispatch.
- No duplicate dispatches.
- `memory_store` continues to fire (no regression on the existing path).

## Fail modes

- An event type produces zero POSTs (G9 fix incomplete).
- Duplicate POSTs per event (over-wired dispatch).
- HMAC signature fails to verify (signing regression).
- SSRF target accepted (security regression).
- Originating-node bias (e.g. only node-A's events fire — federation drift).

## Expected verdict on v0.6.3.1

`GREEN`. G9 is in the v0.6.3.1 audit-finding close-out set.

## References

- ROADMAP2 §5.4 G9 — [webhook gap](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#54-substantive-gaps-and-bugs-priority-ordered)
- ROADMAP2 §7.2 — [G9 absorption](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md#72-v0631--honesty-patch--recovered-commitments--doc-currency--q2-2026-4-weeks)
- Release notes — [`v0.6.3.1.md`](https://github.com/alphaonedev/ai-memory-mcp/blob/main/docs/releases/v0.6.3.1.md)
- Related: S24 (#318 MCP-stdio fanout — expected RED on v0.6.3.1)
