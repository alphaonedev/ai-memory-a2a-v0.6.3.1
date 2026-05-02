#!/usr/bin/env python3
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
"""Stdlib unittest suite for scripts/claims_extractor.py.

Run with: `python3 -m unittest scripts/test_claims_extractor.py`
or:        `python3 -m unittest scripts.test_claims_extractor` (when
            invoked from the repo root with scripts/ a package).

All §7-record validation goes through scripts/schema/validate_log.py /
scripts/schema/phase-log.schema.json. We assemble a full record around
the extractor's outputs using known-good fixed values for every other
required §7 field, then validate.
"""
from __future__ import annotations

import hashlib
import json
import sys
import unittest
from pathlib import Path

# Make the sibling claims_extractor module importable when running with
# `python3 -m unittest scripts/test_claims_extractor.py`.
HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import claims_extractor as ce  # noqa: E402


SCHEMA_PATH = HERE / "schema" / "phase-log.schema.json"


def _sha256(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def _baseline_ops() -> list[dict]:
    """A canonical pair of ai_memory_ops: one write, one recall.

    The recall key_or_query 'budget_constraint_2026' is intentionally a
    distinctive token an assistant message can quote back verbatim.
    """
    return [
        {
            "op": "write",
            "namespace": "phase3/A",
            "key_or_query": "budget_decision",
            "scope": "team",
            "transport": "mcp_stdio",
            "payload_sha256": _sha256("budget=4096"),
            "returned_records": 0,
            "duration_ms": 4,
            "ok": True,
        },
        {
            "op": "recall",
            "namespace": "phase3/A",
            "key_or_query": "budget_constraint_2026",
            "scope": "team",
            "transport": "mcp_stdio",
            "payload_sha256": _sha256("budget=4096"),
            "returned_records": 1,
            "duration_ms": 7,
            "ok": True,
        },
    ]


def _build_full_record(
    *,
    tools_called: list[dict],
    ai_memory_ops: list[dict],
    claims_made: list[dict],
    claims_grounded: list[dict],
    framework: str = "ironclaw",
) -> dict:
    """Wrap the extractor outputs in a full §7 record using known-good
    placeholders for every other required field. Mirrors what
    phase3_autonomous.py::emit_record assembles."""
    return {
        "schema_version": "v0.6.3.1-a2a-nhi-1",
        "campaign_id": f"a2a-{framework}-v0.6.3.1-r1",
        "node_id": "do-test-node-1",
        "release": "v0.6.3.1",
        "phase": 3,
        "scenario_id": "A",
        "control_arm": "treatment",
        "run_index": 1,
        "turn_id": "A-treatment-r1-t1",
        "agent_id": "ai:alice",
        "agent_framework": framework,
        "timestamp_utc": "2026-05-01T00:00:00Z",
        "llm_model_sku": "grok-4-fast-non-reasoning",
        "system_prompt_sha256": "0" * 64,
        "prompt_sha256": _sha256("test prompt"),
        "tools_called": tools_called,
        "ai_memory_ops": ai_memory_ops,
        "claims_made": claims_made,
        "claims_grounded": claims_grounded,
        "refusals": [],
        "termination_reason": "task_complete",
        "self_confidence": 0.85,
        "notes": "test fixture",
    }


class _RecordValidatorMixin:
    """Mixin: load Draft202012Validator once and validate full §7 records."""

    _validator = None  # type: ignore[var-annotated]

    @classmethod
    def _load_validator(cls):
        if cls._validator is not None:
            return cls._validator
        try:
            from jsonschema import Draft202012Validator  # type: ignore
        except ImportError:
            cls._validator = False  # tri-state: False = jsonschema absent
            return cls._validator
        with SCHEMA_PATH.open("r", encoding="utf-8") as fh:
            schema = json.load(fh)
        cls._validator = Draft202012Validator(schema)
        return cls._validator

    def assertSchemaValid(self, record: dict):  # noqa: N802 — unittest style
        v = self._load_validator()
        if v is False:
            self.skipTest("jsonschema not installed")
            return
        errors = sorted(v.iter_errors(record), key=lambda e: list(e.absolute_path))
        if errors:
            paths = "; ".join(
                "/".join(str(p) for p in e.absolute_path) + ": " + e.message
                for e in errors
            )
            self.fail(f"§7 schema violations: {paths}")


# --------------------------------------------------------------------------- #
# tests
# --------------------------------------------------------------------------- #


class TestEmptyInputs(unittest.TestCase, _RecordValidatorMixin):

    def test_empty_string_returns_empty_lists(self):
        tc, cm, cg = ce.extract("ironclaw", "", [])
        self.assertEqual(tc, [])
        self.assertEqual(cm, [])
        self.assertEqual(cg, [])

    def test_empty_string_hermes_returns_empty(self):
        tc, cm, cg = ce.extract("hermes", "", [])
        self.assertEqual((tc, cm, cg), ([], [], []))

    def test_unknown_framework_returns_empty(self):
        tc, cm, cg = ce.extract("nonsense", "anything goes here.", _baseline_ops())
        self.assertEqual((tc, cm, cg), ([], [], []))

    def test_empty_record_validates(self):
        tc, cm, cg = ce.extract("ironclaw", "", [])
        rec = _build_full_record(tools_called=tc, ai_memory_ops=[],
                                  claims_made=cm, claims_grounded=cg)
        self.assertSchemaValid(rec)


class TestIronclawJson(unittest.TestCase, _RecordValidatorMixin):

    def test_one_assistant_msg_one_tool_no_grounding(self):
        # ironclaw JSON envelope with one tool call + one assistant message,
        # but NO ai_memory_ops to ground against → 1 claim, 0 grounded.
        payload = {
            "messages": [
                {"role": "assistant",
                 "content": "The deployment uses Terraform on DigitalOcean."},
            ],
            "tool_calls": [
                {"name": "memory_recall",
                 "args": {"namespace": "phase3/A", "query": "deploy"},
                 "result": {"memories": []},
                 "duration_ms": 5,
                 "ok": True},
            ],
        }
        tc, cm, cg = ce.extract("ironclaw", json.dumps(payload), [])
        self.assertEqual(len(tc), 1)
        self.assertEqual(tc[0]["tool_name"], "memory_recall")
        self.assertEqual(len(tc[0]["args_sha256"]), 64)
        self.assertEqual(len(cm), 1)
        self.assertEqual(cg, [])
        self.assertEqual(cm[0]["category"], "factual")  # has proper noun
        # full §7 record validates
        rec = _build_full_record(tools_called=tc,
                                  ai_memory_ops=[],
                                  claims_made=cm, claims_grounded=cg)
        self.assertSchemaValid(rec)

    def test_one_assistant_msg_quoting_recall_key_grounds(self):
        # Assistant verbatim-quotes the recall query token → 1/1 grounded
        # with grounding_strength=exact.
        ops = _baseline_ops()
        payload = {
            "messages": [
                {"role": "assistant",
                 "content": "Per budget_constraint_2026 the cap is 4096 tokens."},
            ],
        }
        tc, cm, cg = ce.extract("ironclaw", json.dumps(payload), ops)
        self.assertEqual(len(cm), 1)
        self.assertEqual(len(cg), 1)
        self.assertEqual(cg[0]["grounding_strength"], "exact")
        self.assertEqual(cg[0]["grounded_in_op_index"], 1)  # recall is index 1
        self.assertEqual(cg[0]["claim_id"], cm[0]["claim_id"])
        rec = _build_full_record(tools_called=tc, ai_memory_ops=ops,
                                  claims_made=cm, claims_grounded=cg)
        self.assertSchemaValid(rec)

    def test_constraint_sentence_categorised(self):
        # "budget must not exceed 4096 tokens" → category=constraint
        payload = {
            "messages": [
                {"role": "assistant",
                 "content": "Budget must not exceed 4096 tokens."},
            ],
        }
        _tc, cm, _cg = ce.extract("ironclaw", json.dumps(payload), [])
        self.assertEqual(len(cm), 1)
        self.assertEqual(cm[0]["category"], "constraint")

    def test_decision_sentence_categorised(self):
        payload = {"output": "I will use scenario A. The reason is throughput."}
        _tc, cm, _cg = ce.extract("ironclaw", json.dumps(payload), [])
        cats = [c["category"] for c in cm]
        self.assertIn("decision", cats)

    def test_rationale_sentence_categorised(self):
        payload = {"output": "Because latency was the binding factor, we picked A."}
        _tc, cm, _cg = ce.extract("ironclaw", json.dumps(payload), [])
        self.assertEqual(cm[0]["category"], "rationale")

    def test_turns_shape_is_supported(self):
        payload = {
            "turns": [
                {"assistant": "Step 1 completed.",
                 "tool_calls": [{"name": "memory_store",
                                  "args": {"k": "v"}, "result": "ok",
                                  "duration_ms": 1, "ok": True}]},
                {"assistant": "Step 2 completed."},
            ],
        }
        tc, cm, _cg = ce.extract("ironclaw", json.dumps(payload), [])
        self.assertEqual(len(tc), 1)
        # 2 sentences across both turns
        self.assertGreaterEqual(len(cm), 2)

    def test_non_json_ironclaw_falls_back_to_raw(self):
        # If ironclaw emits plain text (e.g. a future build), we still
        # extract claims from it and report no tool trace.
        raw = "The plan is approved. Latency is 12 ms."
        tc, cm, _cg = ce.extract("ironclaw", raw, [])
        self.assertEqual(tc, [])
        self.assertEqual(len(cm), 2)


class TestHermes(unittest.TestCase, _RecordValidatorMixin):

    def test_hermes_plain_text_extracts_claims(self):
        raw = (
            "I will deploy to DigitalOcean. "
            "The cost cap must not exceed 4096 tokens. "
            "Federation propagated the entry under namespace phase3/A."
        )
        ops = _baseline_ops()
        tc, cm, cg = ce.extract("hermes", raw, ops)
        self.assertEqual(tc, [])  # Hermes -Q never exposes tools_called
        self.assertEqual(len(cm), 3)
        cats = [c["category"] for c in cm]
        self.assertIn("decision", cats)     # "I will deploy..."
        self.assertIn("constraint", cats)   # "...must not exceed..."
        # Full record stays §7-valid even with tools_called empty.
        rec = _build_full_record(tools_called=tc, ai_memory_ops=ops,
                                  claims_made=cm, claims_grounded=cg,
                                  framework="hermes")
        rec["campaign_id"] = "a2a-hermes-v0.6.3.1-r1"
        self.assertSchemaValid(rec)

    def test_hermes_grounds_via_recall_key_substring(self):
        ops = _baseline_ops()
        raw = "We picked the path because budget_constraint_2026 ruled it in."
        _tc, cm, cg = ce.extract("hermes", raw, ops)
        self.assertEqual(len(cg), 1)
        self.assertEqual(cg[0]["grounding_strength"], "exact")


class TestSchemaShapesEverywhere(unittest.TestCase, _RecordValidatorMixin):
    """Belt-and-suspenders: hand-crafted edge cases must produce records
    that always pass the §7 validator."""

    def test_tools_called_records_have_all_required_fields(self):
        payload = {
            "tool_calls": [
                {"name": "weird_tool"},  # missing everything else
                {"name": "another", "args": {"x": 1}, "ok": False, "duration_ms": 9},
            ],
        }
        tc, _cm, _cg = ce.extract("ironclaw", json.dumps(payload), [])
        for entry in tc:
            self.assertEqual(set(entry.keys()), {
                "tool_name", "args_sha256", "args_size_bytes",
                "result_sha256", "result_size_bytes", "duration_ms", "ok"
            })
            self.assertEqual(len(entry["args_sha256"]), 64)
            self.assertEqual(len(entry["result_sha256"]), 64)
            self.assertGreaterEqual(entry["duration_ms"], 0)
        rec = _build_full_record(tools_called=tc, ai_memory_ops=[],
                                  claims_made=[], claims_grounded=[])
        self.assertSchemaValid(rec)

    def test_claim_id_uniqueness_across_turn(self):
        raw = "First claim here. Second claim here. Third claim here."
        _tc, cm, _cg = ce.extract("hermes", raw, [])
        ids = [c["claim_id"] for c in cm]
        self.assertEqual(len(ids), len(set(ids)))


if __name__ == "__main__":
    unittest.main()
