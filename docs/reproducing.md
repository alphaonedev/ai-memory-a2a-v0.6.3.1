# Reproducing the campaign

The whole point of a per-release cert repo is that any third party can re-run the campaign against the same tag and get the same verdict. This page documents the two supported reproduction paths (local docker mesh and DigitalOcean 4-node mesh), how to run an individual scenario, and how to verify the resulting verdict.

## Local docker mesh

The fastest way to exercise the harness. Spins up a 4-node OpenClaw mesh on a single host using `docker compose`. Useful for development of scenarios and for sanity-checking the CERT cell before paying for cloud resources; not a substitute for the DigitalOcean mesh on the cert artifact itself.

### Prerequisites

- **Docker** ≥ 24, with `docker compose` v2 plugin. Test with `docker compose version`.
- **`alphaonedev/ai-memory:v0.6.3.1`** image present locally or pullable from GHCR. The image is published to `ghcr.io/alphaonedev/ai-memory:v0.6.3.1` from the [`ai-memory-mcp`](https://github.com/alphaonedev/ai-memory-mcp) release pipeline. Pull with `docker pull ghcr.io/alphaonedev/ai-memory:v0.6.3.1`.
- **At least 4 GB free RAM** and 2 CPU cores. Four nodes plus a coordinator container is the floor.
- **Ports 7080 – 7083 free** on the host. The compose file maps each node to a host port for `curl` debugging.

### Bring up the mesh

```sh
cd /path/to/ai-memory-a2a-v0.6.3.1/harness
docker compose -f docker-compose.local.yml up
```

Expected console output (truncated, real run):

```
[+] Running 5/5
 ✔ Network harness_mesh           Created
 ✔ Container harness-node-1-1     Started
 ✔ Container harness-node-2-1     Started
 ✔ Container harness-node-3-1     Started
 ✔ Container harness-node-4-1     Started
node-1-1  | ai-memory v0.6.3.1 (schema v19) booting
node-1-1  | federation peers: node-2:7080, node-3:7080, node-4:7080
node-1-1  | doctor: storage OK / index OK / recall OK / sync OK
node-2-1  | ai-memory v0.6.3.1 (schema v19) booting
...
```

When all four nodes report `doctor: ... sync OK`, the mesh is ready. From a second terminal, run a scenario (see *Running a single scenario manually* below) or invoke the full sweep via the orchestrator script.

### Common pitfalls

- **`address already in use` on port 7080.** Some other ai-memory dev instance is bound. `docker compose down --remove-orphans` first, or change the host-side port mappings in `docker-compose.local.yml`.
- **Image not found: `ghcr.io/alphaonedev/ai-memory:v0.6.3.1`.** GHCR requires `docker login ghcr.io` if the package visibility is set to private at any point. The v0.6.3.1 image is public, but on networks behind a corporate proxy you may still need to authenticate. Confirm with `docker pull` directly before bringing up compose.
- **`sync ERROR: peer node-N unreachable`.** Compose started the nodes too fast; the federation layer retries with backoff, so wait ~10 s. If it persists, `docker compose logs node-N` to see why that container is unhealthy.
- **Tilde-in-config error on first run.** If you mounted a host config with `db = "~/.ai-memory/store.db"`, you have hit `S23` ([#507](https://github.com/alphaonedev/ai-memory-mcp/issues/507)) — known-open on v0.6.3.1. Use an absolute path until Patch 2.

## DigitalOcean 4-node mesh

The cert artifact is produced against a real 4-node mesh on DigitalOcean. This is the configuration the verdict is signed against.

### Node count rationale

Four nodes is the minimum that exercises a write-quorum mesh with a spare: `W = 2` quorum + 1 hot replica + 1 spare for partition tolerance. This matches the topology spec defined in [`ROADMAP2 §6`](https://github.com/alphaonedev/ai-memory-mcp/blob/main/ROADMAP2.md) (recovered commitments) and the umbrella's `topology/` spec. Three nodes would let `W = 2` quorum hold but leaves no spare for partition simulation; five would over-provision for the cert sweep.

### Prerequisites

- **Terraform** ≥ 1.6.
- **DigitalOcean API token** in `DIGITALOCEAN_TOKEN` (or via Doppler / `op` if you keep secrets in a vault). The token needs `write` on Droplets, VPC, and project resources.
- **An SSH keypair registered with DigitalOcean** whose fingerprint is set in `terraform.tfvars` as `ssh_fingerprint`.
- **Doppler config** (optional) for non-DO env vars: `DOPPLER_TOKEN`, project `ai-memory-a2a`, config `v0_6_3_1`. Or export them directly: `AI_MEMORY_TAG=v0.6.3.1`, `MESH_REGION=nyc3`, `MESH_SIZE=s-2vcpu-4gb`.

### Provision and run

```sh
cd /path/to/ai-memory-a2a-v0.6.3.1/harness/terraform

# one-time
terraform init

# every campaign
terraform apply -auto-approve   # ~3 minutes to four healthy droplets
../ansible/run-mesh.sh          # ansible converges the v0.6.3.1 binary onto each node
../orchestrator/run-campaign.sh # exercises every cell, writes runs/<id>/summary.json

# clean up so you stop paying for it
terraform destroy -auto-approve
```

The orchestrator emits one `runs/<run-id>/` directory per campaign and rolls the result into `releases/v0.6.3.1/summary.json` at the end. If the run is interrupted, `runs/<run-id>/summary.json` will record `verdict: INCOMPLETE` and the release-level summary will not be touched.

### Common pitfalls

- **Region capacity.** `nyc3` occasionally runs out of `s-2vcpu-4gb` slots. Switch to `sfo3` or `ams3` in `terraform.tfvars`.
- **DO API rate limits.** A campaign that hits the API too aggressively (rare) will see 429s; the terraform provider retries automatically but the orchestrator does not. Re-run if it bails out before the first scenario.
- **DNS on freshly-provisioned droplets.** Ansible can race the cloud-init step; the playbook waits for `port 22` plus `cloud-init status --wait` before doing anything destructive.

## Running a single scenario manually

Once the mesh is up (either path), individual scenarios can be exercised in isolation. This is the development inner-loop.

```sh
# env vars the runners expect
export AI_MEMORY_MESH_NODES="node-1:7080,node-2:7080,node-3:7080,node-4:7080"
export AI_MEMORY_TRANSPORT="mtls"
export AI_MEMORY_FRAMEWORK="ironclaw"
export AI_MEMORY_RUN_ID="r-local-$(date +%Y%m%d%H%M%S)"

# example: run S15 (budget_tokens recall)
bash /path/to/ai-memory-a2a-v0.6.3.1/scenarios/v0.6.3.1/S15/runner.sh
```

The runner writes its result under `runs/$AI_MEMORY_RUN_ID/S15.json` and exits non-zero on failure. For Class A scenarios swap `scenarios/v0.6.3.1/S15` for `scenarios/carry-forward/S<id>`.

For expected-red scenarios (`S23`, `S24`), the runner exits **zero** when it detects the expected failure mode and **non-zero** if the underlying defect appears to be silently fixed — the inversion is documented in each scenario's `contract.md`.

## Verifying the verdict

Two artifacts to read after a campaign finishes:

- **Per-run summary.** `runs/<run-id>/summary.json`. Records the run id, timestamp, mesh topology, every cell's pass/fail count, and per-scenario verdicts. This is the raw evidence for one execution.
- **Release-level summary.** [`releases/v0.6.3.1/summary.json`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/releases/v0.6.3.1/summary.json). Records the rolled-up verdict (`CERT` / `PARTIAL` / `FAIL` / `PENDING`), the run id that produced it, the matrix flat keys, and per-scenario verdicts. This is what the [test-hub aggregator](https://alphaonedev.github.io/ai-memory-test-hub/) and the [index page](./index.md) read from.

To verify by hand:

```sh
jq '.campaign.verdict, .scenarios.S23, .scenarios.S24' \
  /path/to/ai-memory-a2a-v0.6.3.1/releases/v0.6.3.1/summary.json
```

A `CERT`-grade run prints `"CERT"`, `"RED"`, `"RED"` (the latter two being expected). A `FAIL` run prints `"FAIL"` plus whichever scenario regressed.

## Why we publish reproducibility

A cert artifact that cannot be re-run is a press release. The whole point of pinning the subject to a tag, publishing the harness, publishing the topology, publishing the scenario contracts, and publishing the verdict computation is that an external party — a downstream integrator, a security auditor, a future maintainer six releases from now — can reproduce the verdict bit-for-bit (or close enough that any divergence is itself diagnostic information). The repo is Apache-2.0 and immutable once tagged for exactly this reason: the cert is the diff between what the code claims and what the harness can prove on the wire.

## Cross-links

- Back to [index](./index.md)
- [Scope](./scope.md) — verdict criteria
- [Matrix](./matrix.md) — framework × transport
- [Scenarios](./scenarios.md) — what each runner exercises
- [Findings](./findings.md) — what the campaign surfaced
- Harness sources: [`harness/`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/tree/main/harness)
- Topology spec: [`ai-memory-ai2ai-gate/topology`](https://github.com/alphaonedev/ai-memory-ai2ai-gate)
