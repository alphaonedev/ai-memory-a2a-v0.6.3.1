# S30 — A2A messaging (notify + inbox + subscribe + HMAC-signed webhooks)

## What this asserts

ai-memory v0.6.3.1 ships **A2A messaging** as a first-class
capability — three coordinated primitives that let agents address
each other directly without a sidecar message bus:

1. **`memory_notify`** — agent X sends a notification addressed to
   agent Y (or to a namespace pattern). Returns a `notification_id`.
2. **`memory_inbox`** — agent Y polls (or pages) its own inbox for
   unread notifications.
3. **`memory_subscribe`** — agent Y registers a subscription
   (typically a namespace glob) so future writes/notifies that
   match are pushed without polling.

On top of those primitives, ai-memory v0.6.3.1 supports
**HMAC-SHA256-signed webhooks** for the push-notification path:
when a subscription is configured with a webhook URL + shared
secret, every emitted notification is POSTed to the URL with an
`X-AIM-Signature: sha256=<hex>` header. The receiver recomputes
HMAC-SHA256(secret, raw body) and compares constant-time. Any
mismatch ⇒ the notification is forged or tampered in transit.

S30 also asserts that the notify path is **federation-aware**:
calling `memory_notify` on node-1 with a target whose subscription
lives on node-3 fans out across the W=2/N=4 quorum without the
caller having to know which peer hosts the subscription.

## Surface under test

- HTTP: `POST /api/v1/notify` (alias of `memory_notify`)
- HTTP: `GET /api/v1/inbox?agent_id=...` (alias of `memory_inbox`)
- HTTP: `POST /api/v1/subscriptions` (alias of `memory_subscribe`)
- HTTP: webhook delivery — POST with body + `X-AIM-Signature` header
- Signing: HMAC-SHA256 with subscription-bound shared secret
- Federation: notify on node-1 reaches subscriber on node-2/node-3

## Setup

- 4-node mesh, ironclaw / mTLS, all v0.6.3.1.
- Native fanout enabled.
- Probe namespace pattern: `test/S30/<run_id>/**`.
- Three NHI identities: `ai:alice` (notifier), `ai:bob`
  (subscriber), `ai:charlie` (federation-target subscriber).
- Webhook receiver: a tiny netcat/python listener bound on a
  high-numbered loopback-mapped port on the runner node — no
  external network required.

## Steps

1. **Subscribe ai:bob.** On node-2, `POST /api/v1/subscriptions`
   with `agent_id=ai:bob`, namespace pattern, and a generated
   shared secret. Capture `subscription_id`.
2. **Notify roundtrip.** On node-1, as `ai:alice`, POST
   `/api/v1/notify` with target `ai:bob`, payload `"hello"`. Assert
   `201 Created` (or 200 with notification_id). Capture
   `notification_id`.
3. **Inbox poll.** On node-2, GET `/api/v1/inbox?agent_id=ai:bob`.
   Assert at least one unread item present, with payload matching
   what alice sent. (Federation is fine here too — but the canonical
   hop is node-2 since that's where ai:bob's subscription lives.)
4. **HMAC verification on webhook delivery.** On node-3, start a
   one-shot `nc -l <port>` listener (with a small bash framing
   wrapper) that captures the next HTTP request body + headers.
   Subscribe ai:charlie with that webhook URL and a known shared
   secret. Trigger `memory_notify` for ai:charlie. Read the captured
   request: extract `X-AIM-Signature: sha256=<hex>`, recompute
   `openssl dgst -sha256 -hmac "<secret>"` over the body, assert
   the hex matches.
5. **Federation fanout.** From node-1, `memory_notify` to a target
   whose subscription is on node-3 (different peer). Assert the
   inbox on node-3 sees the notification (settle window applied).
   The fanout is the test — the caller never directly addressed
   node-3.

## Pass criteria

- `notify_inbox_roundtrip = true`: ai:bob's inbox on node-2 contains
  the notification ai:alice sent from node-1.
- `hmac_verified = true`: the webhook receiver got
  `X-AIM-Signature: sha256=<hex>` and the recomputed HMAC matches
  byte-for-byte.
- `federation_fanout = true`: the notify-on-node-1 → subscription-
  on-node-3 path delivered without the caller addressing node-3
  directly.

## Fail modes

- `notify_inbox_roundtrip = false`: `POST /api/v1/notify` returned
  a 4xx, or the inbox is empty after settle. Either the surface
  doesn't exist on this build or the notify→inbox plumbing is
  broken.
- `hmac_verified = false` with a captured body but mismatched hex:
  **Critical** — the wire signature is not what HMAC-SHA256(secret,
  body) computes. An on-path tamper would not be detectable.
- `hmac_verified = false` with no body captured at all: the
  webhook receiver did not get a delivery — either the
  subscription's webhook field is silently ignored, or
  network reachability between node-1 and node-3 is degraded.
  Distinguished by the `webhook_body_captured` output.
- `federation_fanout = false`: notify on the wrong peer fails
  silently. **High** — A2A requires location-transparent addressing.

## Expected verdict on v0.6.3.1

`GREEN`. memory_notify / memory_inbox / memory_subscribe and
HMAC-SHA256 signed webhooks are documented as first-class shipping
features in v0.6.3.1's release notes and the user's brief
("HMAC-SHA256 signed webhooks"). S30 is the substrate canary.

If `nc -l` (or fallback python -m http.server) cannot bind on
node-3 within the probe window, the runner emits
`actual_verdict=UNKNOWN` with `webhook_listener_unavailable`.

## References

- Capabilities inventory: [`docs/capabilities.md`](../../../docs/capabilities.md) §3 A2A messaging
- Companion canary: S29 (governance — approve/reject can ride the same notify rail)
- Companion canary: S31 (the HMAC primitive used here is the same one used for at-rest tag signing)
- Federation primitives: S24 (#318 — note that MCP stdio writes bypass fanout, so S30 uses HTTP)
