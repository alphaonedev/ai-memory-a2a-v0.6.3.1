# Ansible — node provisioning

Status: scaffolding.

Provisions ai-memory v0.6.3.1 on each node via the Homebrew + cargo + apt pathways depending on the OS image, applies `[boot] / [logging] / [audit]` config preset, generates per-node mTLS certs, and starts the daemon.
