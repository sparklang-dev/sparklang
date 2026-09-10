#!/usr/bin/env python3
"""Unit gates for tools/decompile_assist.py.

Real .sparkbc fixtures only. Offline mode must need no network;
the --llm path is exercised with a stubbed HTTP layer (legitimate
test double — no live gateway in unit tests).
"""

from __future__ import annotations

import io
import json
import sys
import urllib.error
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "python"))

import decompile_assist as da  # noqa: E402
from sparklang.model_lab.bc_dump import OP_NAME  # noqa: E402

STEP_BC = ROOT / "docs/examples/spark-train-step.sparkbc"
SELF_BC = ROOT / "docs/examples/spark-self.sparkbc"


class _FakeResp:
    """Minimal urlopen response double (context manager + read)."""

    def __init__(self, payload: dict) -> None:
        self._raw = json.dumps(payload).encode("utf-8")

    def read(self) -> bytes:
        return self._raw

    def __enter__(self) -> "_FakeResp":
        return self

    def __exit__(self, *exc: object) -> None:
        return None


def _chat_payload(text: str) -> dict:
    """Shape of an OpenAI-compatible chat completion."""
    return {"choices": [{"message": {"content": text}}]}


def test_offline_tracks_input() -> None:
    """Two different real .sparkbc inputs → different assist output."""
    text_a, meta_a = da.run_assist(
        STEP_BC, use_llm=False, base_url="", model="code"
    )
    text_b, meta_b = da.run_assist(
        SELF_BC, use_llm=False, base_url="", model="code"
    )
    assert meta_a["grounding"] == "pass"
    assert meta_b["grounding"] == "pass"
    assert text_a != text_b, "assist output insensitive to input"
    assert meta_a["sha256"] != meta_b["sha256"]
    a = da.load_analysis(STEP_BC)
    for op in a["ops"]:
        assert op["name"] in text_a


def test_grounding_rejects_injected_fake_opcode() -> None:
    """Fabricated opcode/symbol mentions are loud violations."""
    analysis = da.load_analysis(STEP_BC)
    present = {op["name"] for op in analysis["ops"]}
    missing = sorted(set(OP_NAME.values()) - present)
    assert missing, "fixture uses every opcode; pick another"
    text = da.offline_explain(analysis)
    assert da.grounding_violations(text, analysis) == []
    fake_known = text + "\nThe bytecode then runs %s.\n" % missing[0]
    v = da.grounding_violations(fake_known, analysis)
    assert any("not present in dump" in e for e in v), v
    fake_unknown = text + "\nThis uses opcode `ZWARP` here.\n"
    v = da.grounding_violations(fake_unknown, analysis)
    assert any("ZWARP" in e for e in v), v
    fake_sym = text + "\nReads str999 and const999.\n"
    v = da.grounding_violations(fake_sym, analysis)
    assert any("str999" in e for e in v), v
    assert any("const999" in e for e in v), v


def test_offline_needs_no_network() -> None:
    """Offline mode must never touch the HTTP layer."""
    with mock.patch(
        "urllib.request.urlopen",
        side_effect=AssertionError("network in offline mode"),
    ):
        rc = da.main([str(STEP_BC), "--json"])
        assert rc == 0


def test_llm_stubbed_grounded() -> None:
    """--llm with a grounded stub response adds the aid layer."""
    analysis = da.load_analysis(STEP_BC)
    some_op = analysis["ops"][0]["name"]
    aid = "This program starts with %s and ends cleanly." % some_op
    with mock.patch(
        "urllib.request.urlopen",
        return_value=_FakeResp(_chat_payload(aid)),
    ):
        text, meta = da.run_assist(
            STEP_BC,
            use_llm=True,
            base_url="http://127.0.0.1:4000",
            model="code",
        )
    assert meta["mode"] == "offline+llm"
    assert meta["llm"] == "ok"
    assert meta["grounding"] == "pass"
    assert aid in text


def test_llm_stubbed_fabrication_rejected() -> None:
    """--llm aid text with a fabricated opcode → GroundingError."""
    analysis = da.load_analysis(STEP_BC)
    present = {op["name"] for op in analysis["ops"]}
    missing = sorted(set(OP_NAME.values()) - present)
    aid = "It calls %s on str999." % missing[0]
    with mock.patch(
        "urllib.request.urlopen",
        return_value=_FakeResp(_chat_payload(aid)),
    ):
        try:
            da.run_assist(
                STEP_BC,
                use_llm=True,
                base_url="http://127.0.0.1:4000",
                model="code",
            )
        except da.GroundingError as exc:
            assert exc.violations
            assert exc.meta["grounding"] == "fail"
        else:
            raise AssertionError("fabricated aid layer accepted")


def test_llm_degrade_states() -> None:
    """402/429/unreachable degrade to offline (normal states)."""
    for exc in (
        urllib.error.HTTPError(
            "u", 402, "budget", None, io.BytesIO(b"{}")
        ),
        urllib.error.HTTPError(
            "u", 429, "rate", None, io.BytesIO(b"{}")
        ),
        urllib.error.URLError("connection refused"),
    ):
        with mock.patch("urllib.request.urlopen", side_effect=exc):
            text, meta = da.run_assist(
                STEP_BC,
                use_llm=True,
                base_url="http://127.0.0.1:4000",
                model="code",
            )
        assert meta["llm"] == "degraded_offline", meta
        assert meta["grounding"] == "pass"
        assert "## LLM aid layer" not in text


def test_cli_json_shape() -> None:
    """--json emits parseable payload with meta + text."""
    from contextlib import redirect_stdout

    buf = io.StringIO()
    with redirect_stdout(buf):
        rc = da.main([str(SELF_BC), "--json"])
    assert rc == 0
    payload = json.loads(buf.getvalue())
    assert payload["ok"] is True
    assert payload["meta"]["grounding"] == "pass"
    assert payload["meta"]["sha256"] in payload["text"]


def main() -> int:
    """Run assist unit gates."""
    test_offline_tracks_input()
    test_grounding_rejects_injected_fake_opcode()
    test_offline_needs_no_network()
    test_llm_stubbed_grounded()
    test_llm_stubbed_fabrication_rejected()
    test_llm_degrade_states()
    test_cli_json_shape()
    print("ok test_decompile_assist")
    return 0


if __name__ == "__main__":
    sys.exit(main())
