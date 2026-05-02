#!/usr/bin/env python3
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
"""
Phase 3 — Autonomous NHI Playbook.

Per docs/governance.md §6. Four scenarios × four control arms × n=3 = 48 runs.
IronClaw (ai:alice) and Hermes (ai:bob) execute the playbook scenarios
**autonomously**, communicating only through ai-memory. The Orchestrator
sets up each scenario, releases the agents, and observes via the JSON log sink.

Bounded by all three of: 12 turns/agent, 50 ai-memory ops/agent, 10 min walltime.
A run that hits any cap terminates with a `cap_reached_*` flag (distinct
from `refusal` and `task_complete`).

## Two modes

PHASE3_MODE=do-droplets   — drives the real agent runtimes via ssh+drive_agent.sh
                              on the DigitalOcean droplets provisioned by terraform.
                              This is the campaign mode.

PHASE3_MODE=local-shim    — drives a Python-side LLM loop on the Orchestrator
                              against xAI Grok directly. Used for harness
                              development and CI smoke. Records emitted are
                              schema-conforming but lack the production agent
                              stack's MCP wiring; consumers should look at
                              `notes` for the shim marker before drawing
                              substantive conclusions.

## Usage

    NODE1_IP=...  NODE2_IP=...  NODE4_IP=...     AGENT_GROUP=ironclaw  TLS_MODE=mtls     CAMPAIGN_ID=a2a-ironclaw-v0.6.3.1-r2     RUN_OUT_DIR=runs/$CAMPAIGN_ID     PHASE3_MODE=do-droplets     LLM_MODEL_SKU=grok-4-fast-non-reasoning     XAI_API_KEY=$(grep XAI_API_KEY ~/.alphaone/secrets.env | cut -d= -f2)     python3 scripts/phase3_autonomous.py [--scenarios A,B,C,D] [--arms cold,isolated,stubbed,treatment] [--runs 3]

Outputs:
    $RUN_OUT_DIR/phase3-<scenario>-<arm>-run<n>.json   (one §7-conforming record per turn rolled into one run file)
    $RUN_OUT_DIR/phase3-summary.json                   (aggregator)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import secrets
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Sequence

sys.path.insert(0, str(Path(__file__).parent))
from a2a_harness import Harness, log  # noqa: E402

SCHEMA_VERSION = "v0.6.3.1-a2a-nhi-1"
RELEASE = "v0.6.3.1"
SCHEMA_PATH = Path(__file__).parent / "schema" / "phase-log.schema.json"

# Per governance §6.3
MAX_TURNS_PER_AGENT = 12
MAX_OPS_PER_AGENT = 50
WALL_CLOCK_TIMEOUT_S = 600

ARMS = ("cold", "isolated", "stubbed", "treatment")
SCENARIOS = ("A", "B", "C", "D")


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _sha256(s: str | bytes) -> str:
    if isinstance(s, str):
        s = s.encode("utf-8")
    return hashlib.sha256(s).hexdigest()


# ----------------------------------------------------------------------------- #
# Scenario definitions (governance §6.1)
# ----------------------------------------------------------------------------- #

@dataclass
class ScenarioSpec:
    """A Phase 3 scenario: bidirectional task that REQUIRES shared context."""

    id: str
    title: str
    sender_agent: str           # ai:alice (ironclaw) or ai:bob (hermes)
    receiver_agent: str
    sender_node: str            # "node1" | "node2"
    receiver_node: str
    sender_prompt: str          # T0 task — establish a fact in ai-memory
    receiver_prompt_template: str  # T+N task — receiver must use the established fact
    pass_criteria: str          # Human-readable; meta-analyst computes machine criteria from §7 logs
    sender_must_record_keys: list[str] = field(default_factory=list)


SCENARIO_A = ScenarioSpec(
    id="A", title="Decision provenance",
    sender_agent="ai:alice", receiver_agent="ai:bob",
    sender_node="node1", receiver_node="node2",
    sender_prompt=(
        "You are deciding between two architectural alternatives for a federated memory store: "
        "alternative X = synchronous fanout on the write path (consistency-first), "
        "alternative Y = asynchronous fanout with read-repair (availability-first). "
        "Pick X or Y and write a memory recording your selection AND the rationale. "
        "Your rationale MUST cite at least two specific constraints from this list: "
        "(p99-latency budget=200ms, write-throughput=1k qps, read-throughput=10k qps, "
        "tolerance for stale reads=5s, single-region availability target=99.95%). "
        "Use namespace=phase3/A. Title='decision-provenance'. Format the memory body as JSON: "
        '{"selection":"X|Y","constraint_1":"...","constraint_2":"..."}.'
    ),
    receiver_prompt_template=(
        "A reviewer asks you to justify the selection between alternatives X (synchronous fanout) "
        "and Y (asynchronous fanout) for the federated memory store. You have NO PRIOR CONTEXT — "
        "consult ai-memory in namespace=phase3/A and base your justification only on what you find. "
        "If you cannot find the prior decision, say so explicitly rather than fabricating one. "
        "Cite the specific constraints from the prior decision."
    ),
    pass_criteria="Receiver names the two specific constraints recorded by sender; every claim grounded in a recall op.",
    sender_must_record_keys=["decision-provenance"],
)

SCENARIO_B = ScenarioSpec(
    id="B", title="Constraint propagation",
    sender_agent="ai:alice", receiver_agent="ai:bob",
    sender_node="node1", receiver_node="node2",
    sender_prompt=(
        "Record a binding constraint memory: the federated memory store has a HARD upper bound "
        "of 4096 tokens per write operation (any single memory body must be <= 4096 tokens). "
        "Use namespace=phase3/B. Title='token-budget-cap'. Body must include the exact number "
        "4096 and the word 'hard'. This will govern downstream agents' planning."
    ),
    receiver_prompt_template=(
        "Plan a memory write that captures the full transcript of a 6000-token user dialog. "
        "Before executing, consult ai-memory namespace=phase3/B for any constraints that govern "
        "your write. Either flag the violation explicitly OR adapt the plan to comply. "
        "Whichever response you choose, ground it in a retrieved memory."
    ),
    pass_criteria="Receiver detects the 4096-token cap and either flags the 6000-token violation or splits into multiple writes; grounded in recall.",
    sender_must_record_keys=["token-budget-cap"],
)

SCENARIO_C = ScenarioSpec(
    id="C", title="Correction memory",
    sender_agent="ai:alice", receiver_agent="ai:bob",
    sender_node="node1", receiver_node="node2",
    sender_prompt=(
        "First, record a fact F: 'The default ai-memory tier is autonomous'. "
        "Use namespace=phase3/C. Title='default-tier'. "
        "Then I will inject a correction. After the correction, record fact F': "
        "'The default ai-memory tier is hybrid' — same namespace, same title, this overwrites F. "
        "ai-memory should now contain both writes (or a consolidated record)."
    ),
    receiver_prompt_template=(
        "What is the default ai-memory tier? Consult ai-memory namespace=phase3/C, title=default-tier. "
        "If multiple writes exist, return the most recent (corrected) value. "
        "Cite the memory you used."
    ),
    pass_criteria="Receiver returns 'hybrid' (the corrected value F'), not 'autonomous' (stale F).",
    sender_must_record_keys=["default-tier"],
)

SCENARIO_D = ScenarioSpec(
    id="D", title="Federation honesty (NHI correlate of substrate S24/#318)",
    sender_agent="ai:alice", receiver_agent="ai:bob",
    sender_node="node1", receiver_node="node2",
    sender_prompt=(
        "Write a memory using the MCP STDIO PATH (not the HTTP path). The MCP stdio tool dispatch "
        "is the path that issue #318 (substrate S24) flags as bypassing federation fanout on v0.6.3.1. "
        "Use namespace=phase3/D. Title='fed-honesty'. Body=any short marker. "
        "Use ONLY the mcp_stdio transport — do not write via HTTP."
    ),
    receiver_prompt_template=(
        "Recall the memory at namespace=phase3/D, title='fed-honesty'. "
        "If you cannot find it, say so explicitly. Do not fabricate."
    ),
    pass_criteria=(
        "Expected on v0.6.3.1: receiver does NOT see the write within the settle window (5s). "
        "Internal consistency with substrate S24 RED is the pass condition; recall succeeding "
        "would suggest harness/scope mis-categorization."
    ),
    sender_must_record_keys=["fed-honesty"],
)

SCENARIOS_BY_ID = {s.id: s for s in (SCENARIO_A, SCENARIO_B, SCENARIO_C, SCENARIO_D)}


# ----------------------------------------------------------------------------- #
# Run state + bounds
# ----------------------------------------------------------------------------- #

@dataclass
class RunState:
    scenario: ScenarioSpec
    arm: str
    run_index: int
    started_at: float = field(default_factory=time.time)
    turns_per_agent: dict[str, int] = field(default_factory=lambda: {"ai:alice": 0, "ai:bob": 0})
    ops_per_agent: dict[str, int] = field(default_factory=lambda: {"ai:alice": 0, "ai:bob": 0})
    records: list[dict] = field(default_factory=list)

    def can_take_turn(self, agent_id: str) -> tuple[bool, str | None]:
        if time.time() - self.started_at > WALL_CLOCK_TIMEOUT_S:
            return False, "cap_reached_walltime"
        if self.turns_per_agent[agent_id] >= MAX_TURNS_PER_AGENT:
            return False, "cap_reached_turns"
        if self.ops_per_agent[agent_id] >= MAX_OPS_PER_AGENT:
            return False, "cap_reached_ops"
        return True, None


@dataclass
class Phase3Context:
    h: Harness
    campaign_id: str
    node_id: str
    run_out_dir: Path
    log_dir: Path
    mode: str  # do-droplets | local-shim
    schema_validator: Any = None

    @classmethod
    def from_env(cls) -> "Phase3Context":
        h = Harness.from_env(scenario_id="phase3", require_node4=True)
        campaign_id = os.environ.get("CAMPAIGN_ID")
        if not campaign_id:
            raise RuntimeError("CAMPAIGN_ID required (e.g. a2a-ironclaw-v0.6.3.1-r2)")
        run_out_dir = Path(os.environ.get("RUN_OUT_DIR", f"runs/{campaign_id}"))
        log_dir = run_out_dir / "logs" / "phase3"
        log_dir.mkdir(parents=True, exist_ok=True)
        mode = os.environ.get("PHASE3_MODE", "do-droplets")
        if mode not in ("do-droplets", "local-shim"):
            raise RuntimeError(f"PHASE3_MODE must be 'do-droplets' or 'local-shim', got {mode!r}")
        node_id = os.environ.get("DROPLET_ID")
        if not node_id and mode == "do-droplets":
            r = h.ssh_exec(h.node1_ip, "hostname", timeout=10)
            node_id = (r.stdout or "").strip() or f"do-unknown-{secrets.token_hex(4)}"
            if not node_id.startswith("do-"):
                node_id = f"do-{node_id}"
        elif not node_id:
            node_id = f"do-shim-{secrets.token_hex(4)}"

        validator = None
        try:
            from jsonschema import Draft202012Validator  # type: ignore
            with SCHEMA_PATH.open("r", encoding="utf-8") as fh:
                validator = Draft202012Validator(json.load(fh))
        except Exception as e:
            log(f"  -- jsonschema not available ({e}); records will not be inline-validated")
        return cls(h=h, campaign_id=campaign_id, node_id=node_id,
                   run_out_dir=run_out_dir, log_dir=log_dir, mode=mode,
                   schema_validator=validator)

    def emit_record(self, st: RunState, *, agent_id: str, prompt: str,
                    tools_called: list[dict], ai_memory_ops: list[dict],
                    claims_made: list[dict], claims_grounded: list[dict],
                    refusals: list[dict], termination: str,
                    self_confidence: float, notes: str = "") -> dict:
        st.turns_per_agent[agent_id] += 1
        st.ops_per_agent[agent_id] += len(ai_memory_ops)
        turn_index = sum(st.turns_per_agent.values())
        framework = self.h.agent_group  # ironclaw | hermes (constrained per Principle 6)
        record = {
            "schema_version": SCHEMA_VERSION,
            "campaign_id": self.campaign_id,
            "node_id": self.node_id,
            "release": RELEASE,
            "phase": 3,
            "scenario_id": st.scenario.id,
            "control_arm": st.arm,
            "run_index": st.run_index,
            "turn_id": f"{st.scenario.id}-{st.arm}-r{st.run_index}-t{turn_index}",
            "agent_id": agent_id,
            "agent_framework": framework,
            "timestamp_utc": _now_iso(),
            "llm_model_sku": os.environ.get("LLM_MODEL_SKU", "grok-4-fast-non-reasoning"),
            "system_prompt_sha256": os.environ.get("SYSTEM_PROMPT_SHA256", "0" * 64),
            "prompt_sha256": _sha256(prompt),
            "tools_called": tools_called,
            "ai_memory_ops": ai_memory_ops,
            "claims_made": claims_made,
            "claims_grounded": claims_grounded,
            "refusals": refusals,
            "termination_reason": termination,
            "self_confidence": self_confidence,
            "notes": notes,
        }
        if self.schema_validator is not None:
            errors = sorted(self.schema_validator.iter_errors(record),
                            key=lambda e: list(e.absolute_path))
            if errors:
                for err in errors:
                    p = "/".join(str(x) for x in err.absolute_path) or "<root>"
                    log(f"  !! schema violation at {p}: {err.message}")
                raise RuntimeError("phase3 record violated §7 schema; halting per Principle 4")
        st.records.append(record)
        return record


# ----------------------------------------------------------------------------- #
# Arm wiring — control arms expressed as namespace + transport policies
# ----------------------------------------------------------------------------- #

@dataclass
class ArmPolicy:
    """How the agent's memory tool resolves under each arm."""

    arm: str
    memory_enabled: bool       # cold = False
    namespace_prefix: str      # isolated = "<agent_id>/"
    federated: bool            # treatment = True; stubbed = False (in-process dict)
    use_stub: bool             # stubbed only

    @classmethod
    def for_arm(cls, arm: str, agent_id: str) -> "ArmPolicy":
        if arm == "cold":
            return cls(arm, memory_enabled=False, namespace_prefix="", federated=False, use_stub=False)
        if arm == "isolated":
            return cls(arm, memory_enabled=True, namespace_prefix=f"{agent_id}/", federated=False, use_stub=False)
        if arm == "stubbed":
            return cls(arm, memory_enabled=True, namespace_prefix="", federated=False, use_stub=True)
        if arm == "treatment":
            return cls(arm, memory_enabled=True, namespace_prefix="", federated=True, use_stub=False)
        raise ValueError(f"unknown arm: {arm}")


# ----------------------------------------------------------------------------- #
# do-droplets driver — invokes drive_agent.sh on the agent's droplet
# ----------------------------------------------------------------------------- #

def _run_droplet(ctx: Phase3Context, st: RunState, agent_id: str,
                 node_ip: str, prompt: str, policy: ArmPolicy
                 ) -> tuple[list[dict], list[dict], list[dict], list[dict], str]:
    """Drive the real IronClaw / Hermes runtime on a droplet via ssh+drive_agent.sh.

    Returns (tools_called, ai_memory_ops, claims_made, claims_grounded,
    termination_reason). The claims arrays are populated by
    drive_agent_autonomous.sh's claims_extractor_cli.py invocation
    (PR #15 / r13 follow-up #28); without them Phase 4 sees null
    grounding rate across all arms. Caller emits the §7 record and
    updates RunState bookkeeping.
    """
    # The agent runtime on each droplet exposes drive_agent.sh which takes a
    # prompt + arm policy via env vars and emits a §7-shaped JSON to stdout.
    # We pass arm policy via env vars; setup_node.sh wires the MCP client
    # accordingly when AI_MEMORY_ARM is set.
    env_block = " ".join([
        f"AI_MEMORY_ARM={policy.arm}",
        f"AI_MEMORY_NS_PREFIX={policy.namespace_prefix}",
        f"AI_MEMORY_FEDERATED={'1' if policy.federated else '0'}",
        f"AI_MEMORY_USE_STUB={'1' if policy.use_stub else '0'}",
        f"AGENT_ID={agent_id}",
        f"PHASE3_SCENARIO={st.scenario.id}",
        f"PHASE3_ARM={st.arm}",
        f"PHASE3_RUN={st.run_index}",
        f"LLM_MODEL_SKU={os.environ.get('LLM_MODEL_SKU', 'grok-4-fast-non-reasoning')}",
    ])
    remote_cmd = f"{env_block} bash /opt/ai-memory-a2a/drive_agent.sh"
    r = ctx.h.ssh_exec(node_ip, remote_cmd, stdin=prompt, timeout=WALL_CLOCK_TIMEOUT_S)
    if r.returncode == 124:
        return [], [], [], [], "cap_reached_walltime"
    raw = (r.stdout or "").strip()
    try:
        out = json.loads(raw)
    except json.JSONDecodeError:
        log(f"  !! drive_agent.sh non-JSON output (rc={r.returncode}): {raw[:200]!r}")
        return [], [], [], [], "error"
    return (
        out.get("tools_called", []),
        out.get("ai_memory_ops", []),
        out.get("claims_made", []),
        out.get("claims_grounded", []),
        out.get("termination_reason", "task_complete"),
    )


# ----------------------------------------------------------------------------- #
# local-shim driver — drives xAI Grok directly from the orchestrator
# ----------------------------------------------------------------------------- #

class _LocalShimMemory:
    """In-process dict for the 'stubbed' arm, plus a thin HTTP wrapper for
    'treatment' that calls ai-memory's HTTP API. 'cold' returns no tool;
    'isolated' prefixes the namespace; the runtime here cannot exercise the
    actual mcp_stdio transport — runs in this mode are flagged in `notes`."""

    def __init__(self, ctx: Phase3Context, policy: ArmPolicy, agent_id: str):
        self.ctx, self.policy, self.agent_id = ctx, policy, agent_id
        self.stub_store: dict[str, str] = {}

    def write(self, namespace: str, title: str, content: str) -> tuple[bool, int]:
        ns = self.policy.namespace_prefix + namespace
        if self.policy.use_stub:
            self.stub_store[f"{ns}::{title}"] = content
            return True, 0
        if self.policy.federated:
            rc, body = self.ctx.h.write_memory(
                self.ctx.h.node4_ip, agent_id=self.agent_id, namespace=ns,
                title=title, content=content, tier="mid", priority=5,
                include_status=True,
            )
            ok = rc == 0 and isinstance(body, dict) and body.get("http_code") == 201
            return ok, 0
        return False, 0  # cold

    def recall(self, namespace: str, title: str) -> tuple[str | None, int]:
        ns = self.policy.namespace_prefix + namespace
        if self.policy.use_stub:
            return self.stub_store.get(f"{ns}::{title}"), 0
        if self.policy.federated:
            rc, listing = self.ctx.h.list_memories(self.ctx.h.node4_ip, namespace=ns, limit=50)
            if rc != 0 or not isinstance(listing, dict):
                return None, 0
            for m in listing.get("memories") or []:
                if m.get("title") == title:
                    return m.get("content"), 0
            return None, 0
        return None, 0  # cold


def _xai_chat(messages: list[dict], model: str, *, max_tokens: int = 800) -> str:
    """Minimal xAI Grok chat call. OpenAI-compatible API."""
    api_key = os.environ.get("XAI_API_KEY")
    if not api_key:
        raise RuntimeError("XAI_API_KEY not set; required for local-shim mode")
    import urllib.request
    import urllib.error
    req = urllib.request.Request(
        "https://api.x.ai/v1/chat/completions",
        method="POST",
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        data=json.dumps({
            "model": model, "messages": messages,
            "max_tokens": max_tokens, "temperature": 0.0,
        }).encode("utf-8"),
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        log(f"  !! xai HTTP {e.code}: {e.read().decode('utf-8', 'replace')[:200]}")
        return ""
    return ((data.get("choices") or [{}])[0].get("message") or {}).get("content", "")


def _run_local_shim(ctx: Phase3Context, st: RunState, agent_id: str,
                    prompt: str, policy: ArmPolicy
                    ) -> tuple[list[dict], list[dict], str]:
    """Drive xAI Grok directly. Records are §7-conforming but `notes` is flagged.

    Limited fidelity: the real ironclaw/hermes MCP wiring is bypassed; this
    is for harness development on the Orchestrator without live droplets.
    Phase 3 results from this mode are NOT campaign-valid.
    """
    mem = _LocalShimMemory(ctx, policy, agent_id)
    model = os.environ.get("LLM_MODEL_SKU", "grok-4-fast-non-reasoning")
    sys_prompt = (
        f"You are agent {agent_id}. ai-memory tool {'IS' if policy.memory_enabled else 'is NOT'} "
        f"available. Respond concisely. If you write/recall, output a single JSON object: "
        f'{{"action":"write|recall","namespace":"...","title":"...","content":"..."}} '
        f"on its own line, then briefly explain. Do not narrate beyond what you actually did."
    )
    messages = [{"role": "system", "content": sys_prompt},
                {"role": "user", "content": prompt}]
    response = _xai_chat(messages, model)
    ai_memory_ops: list[dict] = []
    op_index = 0
    for line in (response or "").splitlines():
        line = line.strip()
        if not (line.startswith("{") and '"action"' in line):
            continue
        try:
            cmd = json.loads(line)
        except json.JSONDecodeError:
            continue
        action = cmd.get("action")
        ns = cmd.get("namespace", "")
        title = cmd.get("title", "")
        content = cmd.get("content", "")
        if action == "write" and policy.memory_enabled:
            ok, dur = mem.write(ns, title, content)
            ai_memory_ops.append({
                "op": "write", "namespace": policy.namespace_prefix + ns,
                "key_or_query": title, "scope": "team",
                "transport": "http",
                "payload_sha256": _sha256(content),
                "returned_records": 1 if ok else 0,
                "duration_ms": dur, "ok": ok,
            })
        elif action == "recall" and policy.memory_enabled:
            recalled, dur = mem.recall(ns, title)
            ai_memory_ops.append({
                "op": "recall", "namespace": policy.namespace_prefix + ns,
                "key_or_query": title, "scope": "team",
                "transport": "http",
                "payload_sha256": _sha256(recalled or ""),
                "returned_records": 1 if recalled is not None else 0,
                "duration_ms": dur, "ok": recalled is not None,
            })
        op_index += 1
    # local-shim doesn't run the claims_extractor (it's an agent-side tool);
    # leave claims arrays empty here. The shim mode is dev-only and notes
    # this in the §7 record.
    return [], ai_memory_ops, [], [], "task_complete"


# ----------------------------------------------------------------------------- #
# Run loop
# ----------------------------------------------------------------------------- #

def run_one(ctx: Phase3Context, scenario_id: str, arm: str, run_index: int) -> Path:
    spec = SCENARIOS_BY_ID[scenario_id]
    st = RunState(scenario=spec, arm=arm, run_index=run_index)

    sender_node = {"node1": ctx.h.node1_ip, "node2": ctx.h.node2_ip}[spec.sender_node]
    receiver_node = {"node1": ctx.h.node1_ip, "node2": ctx.h.node2_ip}[spec.receiver_node]

    # Sender turn(s) — autonomous; the runtime decides how many turns to take.
    sender_policy = ArmPolicy.for_arm(arm, spec.sender_agent)
    sender_ok, sender_cap = st.can_take_turn(spec.sender_agent)
    termination = "task_complete"
    notes_extra = "shim mode" if ctx.mode == "local-shim" else ""
    if not sender_ok:
        termination = sender_cap or "error"
        ctx.emit_record(st, agent_id=spec.sender_agent, prompt=spec.sender_prompt,
                        tools_called=[], ai_memory_ops=[],
                        claims_made=[], claims_grounded=[], refusals=[],
                        termination=termination, self_confidence=0.0,
                        notes=notes_extra)
    else:
        if ctx.mode == "do-droplets":
            tc, ops, claims, grounded, term = _run_droplet(
                ctx, st, spec.sender_agent, sender_node,
                spec.sender_prompt, sender_policy)
        else:
            tc, ops, claims, grounded, term = _run_local_shim(
                ctx, st, spec.sender_agent,
                spec.sender_prompt, sender_policy)
        ctx.emit_record(st, agent_id=spec.sender_agent, prompt=spec.sender_prompt,
                        tools_called=tc, ai_memory_ops=ops,
                        claims_made=claims, claims_grounded=grounded, refusals=[],
                        termination=term, self_confidence=0.85 if term == "task_complete" else 0.2,
                        notes=notes_extra)
        termination = term if term != "task_complete" else termination

    # Federation settle window — give Scenario D's MCP-stdio write the chance to
    # propagate (or, on v0.6.3.1, to NOT propagate per S24).
    settle_secs = float(os.environ.get("FEDERATION_SETTLE_S", "5"))
    if spec.id == "D":
        time.sleep(settle_secs)

    # Receiver turn(s)
    receiver_policy = ArmPolicy.for_arm(arm, spec.receiver_agent)
    receiver_prompt = spec.receiver_prompt_template
    receiver_ok, receiver_cap = st.can_take_turn(spec.receiver_agent)
    if not receiver_ok:
        termination = receiver_cap or "error"
        ctx.emit_record(st, agent_id=spec.receiver_agent, prompt=receiver_prompt,
                        tools_called=[], ai_memory_ops=[],
                        claims_made=[], claims_grounded=[], refusals=[],
                        termination=termination, self_confidence=0.0,
                        notes=notes_extra)
    else:
        if ctx.mode == "do-droplets":
            tc, ops, claims, grounded, term = _run_droplet(
                ctx, st, spec.receiver_agent, receiver_node,
                receiver_prompt, receiver_policy)
        else:
            tc, ops, claims, grounded, term = _run_local_shim(
                ctx, st, spec.receiver_agent,
                receiver_prompt, receiver_policy)
        ctx.emit_record(st, agent_id=spec.receiver_agent, prompt=receiver_prompt,
                        tools_called=tc, ai_memory_ops=ops,
                        claims_made=claims, claims_grounded=grounded, refusals=[],
                        termination=term, self_confidence=0.85 if term == "task_complete" else 0.2,
                        notes=notes_extra)
        termination = term if term != "task_complete" else termination

    # Persist run aggregator file
    out = ctx.run_out_dir / f"phase3-{spec.id}-{arm}-run{run_index}.json"
    payload = {
        "schema": "phase3-run/v1",
        "scenario_id": spec.id, "scenario_title": spec.title,
        "control_arm": arm, "run_index": run_index,
        "campaign_id": ctx.campaign_id, "node_id": ctx.node_id,
        "release": RELEASE,
        "agent_group": ctx.h.agent_group,
        "tls_mode": ctx.h.tls_mode,
        "mode": ctx.mode,
        "started_at_utc": datetime.fromtimestamp(st.started_at, tz=timezone.utc)
                              .isoformat(timespec="seconds").replace("+00:00", "Z"),
        "wall_seconds": int(time.time() - st.started_at),
        "turns_per_agent": st.turns_per_agent,
        "ops_per_agent": st.ops_per_agent,
        "termination_reason": termination,
        "records": st.records,
    }
    out.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    log(f"phase3: {spec.id}/{arm}/r{run_index} -> {out.name} (termination={termination})")
    return out


def main(argv: Sequence[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--scenarios", default=",".join(SCENARIOS),
                    help="Comma-separated scenarios (default A,B,C,D)")
    ap.add_argument("--arms", default=",".join(ARMS),
                    help="Comma-separated arms (default cold,isolated,stubbed,treatment)")
    ap.add_argument("--runs", type=int, default=3, help="n per cell (default 3)")
    args = ap.parse_args(argv)

    scenarios = [s.strip() for s in args.scenarios.split(",") if s.strip()]
    arms = [a.strip() for a in args.arms.split(",") if a.strip()]
    invalid_s = [s for s in scenarios if s not in SCENARIOS_BY_ID]
    invalid_a = [a for a in arms if a not in ARMS]
    if invalid_s or invalid_a:
        log(f"phase3: invalid scenarios={invalid_s} arms={invalid_a}")
        return 2

    try:
        ctx = Phase3Context.from_env()
    except RuntimeError as e:
        log(f"phase3: setup error: {e}")
        return 2

    log(f"phase3: campaign_id={ctx.campaign_id} mode={ctx.mode} "
        f"scenarios={scenarios} arms={arms} runs={args.runs}")

    summary_runs = []
    for s in scenarios:
        for a in arms:
            for n in range(1, args.runs + 1):
                try:
                    out_path = run_one(ctx, s, a, n)
                    summary_runs.append({
                        "scenario_id": s, "control_arm": a, "run_index": n,
                        "file": str(out_path.relative_to(ctx.run_out_dir)),
                    })
                except RuntimeError as e:
                    log(f"phase3: {s}/{a}/r{n} aborted: {e}")
                    summary_runs.append({
                        "scenario_id": s, "control_arm": a, "run_index": n,
                        "error": str(e),
                    })

    summary = {
        "schema": "phase3-summary/v1",
        "campaign_id": ctx.campaign_id, "node_id": ctx.node_id, "release": RELEASE,
        "agent_group": ctx.h.agent_group, "tls_mode": ctx.h.tls_mode, "mode": ctx.mode,
        "scenarios": scenarios, "arms": arms, "runs_per_cell": args.runs,
        "expected_runs": len(scenarios) * len(arms) * args.runs,
        "actual_runs": len(summary_runs),
        "runs": summary_runs,
        "generated_at_utc": _now_iso(),
    }
    summary_path = ctx.run_out_dir / "phase3-summary.json"
    summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True), encoding="utf-8")
    log(f"phase3: summary -> {summary_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
