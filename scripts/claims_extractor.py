#!/usr/bin/env python3
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
"""claims_extractor — turn agent CLI output into §7-shaped tools/claims arrays.

This module is the sole place where the `claims_made` and `claims_grounded`
arrays of the docs/governance.md §7 schema are computed for the v0.6.3.1
A2A-NHI campaign. Phase 4's grounding-rate metric is

    treatment_grounding_rate = len(claims_grounded) / len(claims_made)

so without a real extractor the whole attribution chain collapses to zero.
This module fixes that.

------------------------------------------------------------------------------
Upstream agent CLI output schemas (recon notes, captured 2026-05-01)
------------------------------------------------------------------------------

ironclaw v0.27.x (github.com/nearai/ironclaw):
    * Subcommand surface (src/cli/mod.rs): the public `run` subcommand is
      declared as `Run` with NO arguments — it just starts the agent in
      its default mode. There is no upstream `--non-interactive`, no
      `--format json`, and no `--max-tool-rounds`.
    * However, drive_agent_autonomous.sh DOES invoke
          `ironclaw run --non-interactive --format json --max-tool-rounds 12 -p "<prompt>"`
      which means in practice we will see one of:
        a) ironclaw rejects the unknown flags → empty stdout / non-zero rc
           (drive_agent_autonomous.sh treats this as an error termination).
        b) A future ironclaw build (or a private fork) adds those flags and
           emits a JSON trace.
    * The defensive shape we accept on stdout is therefore "any JSON object
      that MAY contain a `tool_calls[]` array at top level OR a `turns[]`
      array of objects each carrying their own `tool_calls[]`." Each call
      may carry: name/tool, args/args_sha256, result/result_sha256,
      duration_ms, ok/error. Anything missing is replaced with a zero-hash
      / size 0 / ok:true default to keep §7 records valid.
    * For the assistant-message body (claim source), we also accept a few
      shapes:
        - {"output": "<text>"}            (single-shot ironclaw build)
        - {"messages":[{"role":"assistant","content":"<text>"}, ...]}
        - {"turns":[{"assistant":"<text>", ...}, ...]}
        - {"final_response":"<text>"}
      If none of those parse, we fall back to treating the entire raw stdout
      as a single assistant message (best-effort; documented in `notes`).

hermes v0.x (github.com/NousResearch/hermes-agent):
    * Subcommand: `hermes chat -Q --provider <p> --model <m> -q "<prompt>"`.
    * `-Q`/`--quiet` is registered in hermes_cli/_parser.py: "Quiet mode for
      programmatic use: suppress banner, spinner, and tool previews. Only
      output the final response and session info."
    * Implementation reference is `hermes_cli/oneshot.py::run_oneshot` (the
      `-z` path; `-Q` shares the same final-write contract): redirect stderr
      AND stdout to /dev/null while the agent runs, then `real_stdout.write
      (response)` once and exit. So stdout is the assistant's final text,
      with no JSON envelope and no tool trace.
    * Therefore tools_called[] is ALWAYS empty for hermes here, and we set
      a notes-style annotation explaining why. ai-memory tool ops are still
      recoverable via the audit log (see drive_agent_autonomous.sh step 8).

------------------------------------------------------------------------------
Heuristics (documented per the task brief)
------------------------------------------------------------------------------

Sentence segmentation: simple regex on `.` `!` `?` followed by whitespace.
No nltk / spacy dependency (stdlib only per task constraints).

Claim categorisation, in priority order (first match wins):
    constraint  — sentence matches /\b(must|cannot|max(?:imum)?|min(?:imum)?|
                  no more than|<=|>=)\b/i
    decision    — sentence begins with /(I will|We will|Selected|Chose)\b/i
    rationale   — sentence begins with /(because|so|therefore|since)\b/i
                  OR contains the literal word "rationale"
    factual     — default for any other content sentence

Grounding (a claim is "grounded" if ANY of):
    1. The claim contains a substring (>= 8 contiguous chars) that also
       appears in some recall op's `key_or_query` field.
    2. The claim contains a substring (>= 8 contiguous chars) that matches
       the first 8 hex chars of some recall op's `payload_sha256`.
    3. The claim contains a UUID pattern [0-9a-f]{8}-[0-9a-f]{4}-... that
       matches text in the claim body (paranoid; recall results aren't in
       the op record).

Strength: "exact" if a literal substring match found; otherwise
"paraphrase". "inference" is reserved for future Phase 4 LLM-judge use.

------------------------------------------------------------------------------
Public API
------------------------------------------------------------------------------

    extract(agent_framework, agent_output_raw, ai_memory_ops)
        -> (tools_called, claims_made, claims_grounded)

All SHA-256s are 64-char lowercase hex (sha256(s.encode("utf-8"))).
The schema enforces this (see scripts/schema/phase-log.schema.json §7).
"""
from __future__ import annotations

import hashlib
import json
import re
from typing import Any

ZERO_SHA256 = "0" * 64

_SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?])\s+(?=[A-Z0-9\"'(\[])")

# Order matters: priority is constraint > decision > rationale > factual.
_CONSTRAINT_RE = re.compile(
    r"\b(must|cannot|max(?:imum)?|min(?:imum)?|no\s+more\s+than|<=|>=)\b",
    re.IGNORECASE,
)
_DECISION_RE = re.compile(r"^\s*(I\s+will|We\s+will|Selected|Chose)\b", re.IGNORECASE)
_RATIONALE_RE = re.compile(r"^\s*(because|so|therefore|since)\b", re.IGNORECASE)
_RATIONALE_WORD_RE = re.compile(r"\brationale\b", re.IGNORECASE)
_NUMBER_OR_PROPER_RE = re.compile(r"\d|\b[A-Z][a-zA-Z0-9_-]{2,}")
_UUID_HEAD_RE = re.compile(r"\b[0-9a-f]{8}-[0-9a-f]{4}\b")
_PROBABLY_JSON_RE = re.compile(r"^\s*[{\[]")


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #

def _sha256(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def _bytelen(s: str) -> int:
    return len(s.encode("utf-8"))


def _split_sentences(text: str) -> list[str]:
    """Stdlib-only sentence splitter. Returns non-empty stripped sentences."""
    if not text:
        return []
    # Normalise whitespace so the regex split behaves consistently.
    norm = re.sub(r"\s+", " ", text).strip()
    if not norm:
        return []
    parts = _SENTENCE_SPLIT_RE.split(norm)
    out: list[str] = []
    for p in parts:
        p = p.strip()
        # If the chunk lacks terminal punctuation (e.g. trailing fragment),
        # still emit it — tests expect at least one claim per non-empty body.
        if p:
            out.append(p)
    return out


def _categorize(sentence: str) -> str:
    if _CONSTRAINT_RE.search(sentence):
        return "constraint"
    if _DECISION_RE.match(sentence):
        return "decision"
    if _RATIONALE_RE.match(sentence) or _RATIONALE_WORD_RE.search(sentence):
        return "rationale"
    return "factual"


def _claim_id(turn_seq: int, idx: int) -> str:
    # Stable, schema-conforming id; minLength: 1.
    return f"c{turn_seq}-{idx + 1}"


def _safe_str(v: Any, default: str = "") -> str:
    if v is None:
        return default
    if isinstance(v, str):
        return v
    return json.dumps(v, sort_keys=True)


# --------------------------------------------------------------------------- #
# tools_called extraction
# --------------------------------------------------------------------------- #

def _ironclaw_tool_calls(parsed: Any) -> list[dict]:
    """Collect tool calls from any of the shapes ironclaw might emit.

    Defensive: we accept top-level `tool_calls` or nested `turns[].tool_calls`.
    Missing fields are replaced with zero-hash / 0-size / ok:true defaults so
    the resulting record stays §7-schema-valid.
    """
    if not isinstance(parsed, dict):
        return []
    raw_calls: list[Any] = []
    if isinstance(parsed.get("tool_calls"), list):
        raw_calls.extend(parsed["tool_calls"])
    if isinstance(parsed.get("turns"), list):
        for t in parsed["turns"]:
            if isinstance(t, dict) and isinstance(t.get("tool_calls"), list):
                raw_calls.extend(t["tool_calls"])
    out: list[dict] = []
    for c in raw_calls:
        if not isinstance(c, dict):
            continue
        name = _safe_str(c.get("name") or c.get("tool") or "unknown") or "unknown"
        args = c.get("args")
        if isinstance(args, (dict, list)):
            args_repr = json.dumps(args, sort_keys=True)
        else:
            args_repr = _safe_str(args, "")
        result = c.get("result")
        if isinstance(result, (dict, list)):
            result_repr = json.dumps(result, sort_keys=True)
        else:
            result_repr = _safe_str(result, "")
        args_sha = (
            c["args_sha256"] if isinstance(c.get("args_sha256"), str) and len(c["args_sha256"]) == 64
            else (_sha256(args_repr) if args_repr else ZERO_SHA256)
        )
        result_sha = (
            c["result_sha256"] if isinstance(c.get("result_sha256"), str) and len(c["result_sha256"]) == 64
            else (_sha256(result_repr) if result_repr else ZERO_SHA256)
        )
        try:
            duration_ms = int(c.get("duration_ms") or 0)
            if duration_ms < 0:
                duration_ms = 0
        except (TypeError, ValueError):
            duration_ms = 0
        try:
            args_size = int(c.get("args_size_bytes")) if c.get("args_size_bytes") is not None else _bytelen(args_repr)
        except (TypeError, ValueError):
            args_size = _bytelen(args_repr)
        try:
            result_size = (
                int(c.get("result_size_bytes"))
                if c.get("result_size_bytes") is not None else _bytelen(result_repr)
            )
        except (TypeError, ValueError):
            result_size = _bytelen(result_repr)
        ok_v = c.get("ok")
        if isinstance(ok_v, bool):
            ok = ok_v
        elif "error" in c:
            ok = c.get("error") in (None, "", False)
        else:
            ok = True
        out.append({
            "tool_name": name,
            "args_sha256": args_sha,
            "args_size_bytes": max(0, args_size),
            "result_sha256": result_sha,
            "result_size_bytes": max(0, result_size),
            "duration_ms": duration_ms,
            "ok": bool(ok),
        })
    return out


# --------------------------------------------------------------------------- #
# assistant-text extraction
# --------------------------------------------------------------------------- #

def _ironclaw_assistant_text(parsed: Any, raw: str) -> str:
    """Pull the assistant-message body out of the JSON shapes ironclaw might
    emit. Falls back to the raw string when no recognisable shape is found
    (e.g. a future ironclaw release with a different JSON envelope)."""
    if isinstance(parsed, dict):
        # Single-shot field.
        for k in ("output", "final_response", "response", "content", "text"):
            v = parsed.get(k)
            if isinstance(v, str) and v.strip():
                return v
        msgs = parsed.get("messages")
        if isinstance(msgs, list):
            chunks: list[str] = []
            for m in msgs:
                if not isinstance(m, dict):
                    continue
                if str(m.get("role", "")).lower() == "assistant":
                    c = m.get("content")
                    if isinstance(c, str):
                        chunks.append(c)
                    elif isinstance(c, list):
                        # OpenAI-style content list: [{type:"text", text:"..."}, ...]
                        for piece in c:
                            if isinstance(piece, dict) and isinstance(piece.get("text"), str):
                                chunks.append(piece["text"])
            if chunks:
                return "\n".join(chunks)
        turns = parsed.get("turns")
        if isinstance(turns, list):
            chunks = []
            for t in turns:
                if isinstance(t, dict):
                    a = t.get("assistant") or t.get("assistant_text") or t.get("output")
                    if isinstance(a, str):
                        chunks.append(a)
            if chunks:
                return "\n".join(chunks)
    # Fallback: treat raw stdout as the message body.
    return raw


# --------------------------------------------------------------------------- #
# claims extraction + grounding
# --------------------------------------------------------------------------- #

def _ngram_substrings(s: str, n: int = 8) -> set[str]:
    """All contiguous lowercased substrings of length >= n. Capped at len(s)
    to keep this O(len(s)) memory."""
    s = s.lower()
    if len(s) < n:
        return set()
    out: set[str] = set()
    # Generate length-n shingles; checking longer is implied by a hit on any
    # length-n shingle that's contained in the recall token.
    for i in range(0, len(s) - n + 1):
        out.add(s[i:i + n])
    return out


def _find_grounding(
    sentence: str,
    ai_memory_ops: list[dict],
) -> tuple[int, str] | None:
    """Return (op_index, strength) for the first matching recall op, or None.

    Strength is "exact" when we found a literal substring match against the
    op's key/query or payload-sha-prefix; "paraphrase" reserved for fuzzy/
    UUID-only matches.
    """
    if not sentence or not ai_memory_ops:
        return None
    s_low = sentence.lower()
    s_shingles = _ngram_substrings(sentence, n=8)

    # Pass 1: exact substring against key_or_query (any direction).
    for idx, op in enumerate(ai_memory_ops):
        if not isinstance(op, dict):
            continue
        if op.get("op") != "recall":
            continue
        key = _safe_str(op.get("key_or_query"), "").lower()
        if not key:
            continue
        # Either the recall's key appears in the sentence, or any 8-shingle
        # of the sentence appears in the key.
        if len(key) >= 8 and key in s_low:
            return idx, "exact"
        if s_shingles:
            for shing in s_shingles:
                if shing in key:
                    return idx, "exact"

    # Pass 2: payload sha256 prefix (8 hex chars).
    for idx, op in enumerate(ai_memory_ops):
        if not isinstance(op, dict):
            continue
        if op.get("op") != "recall":
            continue
        sha = _safe_str(op.get("payload_sha256"), "")
        if len(sha) >= 8 and sha[:8] != "00000000":
            if sha[:8] in s_low:
                return idx, "exact"

    # Pass 3: UUID head pattern in sentence — record as paraphrase since the
    # underlying recall result isn't in the op record.
    if _UUID_HEAD_RE.search(sentence):
        for idx, op in enumerate(ai_memory_ops):
            if isinstance(op, dict) and op.get("op") == "recall":
                return idx, "paraphrase"

    return None


def _extract_claims(
    assistant_text: str,
    ai_memory_ops: list[dict],
    turn_seq: int = 1,
) -> tuple[list[dict], list[dict]]:
    """Walk one assistant message body; emit claims_made + claims_grounded."""
    claims_made: list[dict] = []
    claims_grounded: list[dict] = []
    if not assistant_text or not assistant_text.strip():
        return claims_made, claims_grounded

    # If the whole stdout is JSON, don't dredge sentences out of it.
    if _PROBABLY_JSON_RE.match(assistant_text):
        try:
            json.loads(assistant_text)
            return claims_made, claims_grounded
        except (ValueError, TypeError):
            pass

    sentences = _split_sentences(assistant_text)
    for i, sent in enumerate(sentences):
        # Filter trivial fragments (under 4 chars after strip) — they can't
        # carry a meaningful claim, and they pollute the grounding rate.
        if len(sent.strip()) < 4:
            continue
        cid = _claim_id(turn_seq, len(claims_made))
        claims_made.append({
            "claim_id": cid,
            "text_sha256": _sha256(sent),
            "category": _categorize(sent),
        })
        match = _find_grounding(sent, ai_memory_ops)
        if match is not None:
            op_idx, strength = match
            claims_grounded.append({
                "claim_id": cid,
                "grounded_in_op_index": op_idx,
                "grounding_strength": strength,
            })
    return claims_made, claims_grounded


# --------------------------------------------------------------------------- #
# public API
# --------------------------------------------------------------------------- #

def extract(
    agent_framework: str,
    agent_output_raw: str,
    ai_memory_ops: list[dict],
) -> tuple[list[dict], list[dict], list[dict]]:
    """Extract (tools_called, claims_made, claims_grounded) from a per-turn
    agent CLI invocation.

    Args:
        agent_framework: "ironclaw" or "hermes" (Principle 6 surface).
        agent_output_raw: stdout the agent CLI wrote (str). Empty allowed.
        ai_memory_ops: already-extracted §7 ai_memory_ops items (list[dict]).

    Returns three §7-conforming lists. Computes all SHA-256s itself.
    """
    if agent_framework not in ("ironclaw", "hermes"):
        # Out of scope per Principle 6 / governance.md §6.1.
        return [], [], []

    raw = agent_output_raw if isinstance(agent_output_raw, str) else ""
    raw = raw.strip("﻿")  # strip BOM if present
    ops = ai_memory_ops if isinstance(ai_memory_ops, list) else []

    if not raw:
        return [], [], []

    if agent_framework == "ironclaw":
        parsed: Any = None
        try:
            parsed = json.loads(raw)
        except (ValueError, TypeError):
            parsed = None
        tools_called = _ironclaw_tool_calls(parsed) if parsed is not None else []
        assistant_text = _ironclaw_assistant_text(parsed, raw)
        claims_made, claims_grounded = _extract_claims(assistant_text, ops, turn_seq=1)
        return tools_called, claims_made, claims_grounded

    # hermes — quiet mode emits the assistant text as plain stdout. There is
    # no upstream tool-trace exposure path here; ai-memory ops are still
    # recoverable via the audit log (see drive_agent_autonomous.sh §8).
    claims_made, claims_grounded = _extract_claims(raw, ops, turn_seq=1)
    return [], claims_made, claims_grounded
