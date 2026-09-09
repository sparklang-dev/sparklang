#!/usr/bin/env python3
"""Prove SPARK_BC dump + Spark-created weights (no GPU)."""

from __future__ import annotations

import hashlib
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))

from sparklang.model_lab.bc_dump import (
    decode_ops,
    format_dump,
    hex_preview,
    load_sparkbc,
)
from sparklang.model_lab.builder import emit_base, emit_serve, emit_stub
from sparklang.model_lab.weights import (
    apply_dry_step,
    emit_init_weights,
    read_safetensors_meta,
)

BUILDER_BC = ROOT / "docs/examples/spark-builder.sparkbc"
SELF_BC = ROOT / "docs/examples/spark-self.sparkbc"
STEP_BC = ROOT / "docs/examples/spark-train-step.sparkbc"
STEP_DUMP = ROOT / "docs/examples/spark-train-step-bc.txt"
STEP_SHA256 = (
    "d08925b52bf8c840de626c9cfec619d4dbae5a674b94bb8c7c5837eb1ac64551"
)
BUILDER_SRC = "examples/spark_builder.spark"
BUILDER_CMD = (
    "./spark-bootstrap --compile examples/spark_builder.spark "
    "-o docs/examples/spark-builder.sparkbc"
)
SELF_SRC = "selfhost/compile.spark"
SELF_CMD = (
    "./spark-bootstrap --compile selfhost/compile.spark "
    "-o docs/examples/spark-self.sparkbc"
)
STEP_SRC = "examples/spark_train_step.spark"
STEP_CMD = (
    "./spark-bootstrap --compile examples/spark_train_step.spark "
    "-o docs/examples/spark-train-step.sparkbc"
)


def test_self_magic_and_weights() -> dict:
    """Load compiler-seed SPARK_BC and emit deterministic init weights."""
    bc = load_sparkbc(SELF_BC)
    assert bc["magic"] == "SPBC"
    assert bc["version"] == 1
    assert bc["raw"][:4] == b"SPBC"
    first = hex_preview(bc["raw"], 32)
    assert first.startswith("53 50 42 43 01")
    dest = ROOT / "docs/examples/spark-self.init.safetensors"
    w1 = emit_init_weights(
        SELF_BC, dest, source=SELF_SRC, command=SELF_CMD
    )
    w2 = emit_init_weights(
        SELF_BC, dest, source=SELF_SRC, command=SELF_CMD
    )
    assert w1["sha256"] == w2["sha256"]
    assert w1["trained"] is False
    assert w1["n_tensors"] >= 10
    assert dest.is_file()
    raw = dest.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == w1["sha256"]
    return {"bc": bc, "first": first, "weights": w1}


def test_builder_train_opcode() -> list[str]:
    """Decode TRAIN 0x26 from the real builder .sparkbc (no invented hex)."""
    assert BUILDER_BC.is_file(), BUILDER_BC
    bc = load_sparkbc(BUILDER_BC)
    assert bc["magic"] == "SPBC"
    assert bc["raw"][:4] == b"SPBC"
    ops = decode_ops(bc)
    names = [o["name"] for o in ops]
    train = [o for o in ops if o["op"] == 0x26]
    status = [o for o in ops if o["op"] == 0x27]
    assert len(train) == 1, names
    assert train[0]["name"] == "TRAIN"
    assert train[0]["hex"].startswith("26 ")
    assert len(train[0]["operands"]) == 5
    assert len(status) == 1, names
    assert status[0]["name"] == "TRAIN_STATUS"
    dump = format_dump(
        bc,
        source=BUILDER_SRC,
        command=BUILDER_CMD,
        label="Builder SPARK_BC (train ops in the binary)",
    )
    assert "TRAIN (0x26)" in dump, dump
    assert "TRAIN_STATUS (0x27)" in dump, dump
    assert "26 07 00" in dump
    assert dump.split("sha256:", 1)[1].strip().startswith(bc["sha256"])
    return names


def test_builder_weights_stay_init() -> None:
    """Weights from builder SPARK_BC stay Spark-created init."""
    with tempfile.TemporaryDirectory() as tmp:
        dest = Path(tmp) / "spark-builder.init.safetensors"
        stub = emit_stub(
            BUILDER_BC, source=BUILDER_SRC, command=BUILDER_CMD
        )
        assert stub["trained"] is False
        assert "TRAIN" in stub["opcodes"]
        assert "TRAIN_STATUS" in stub["opcodes"]
        payload = emit_base(
            BUILDER_BC,
            dest,
            source=BUILDER_SRC,
            command=BUILDER_CMD,
        )
        weights = payload["weights"]
        assert payload["trained"] is False
        assert weights["trained"] is False
        assert dest.is_file()
        w2 = emit_init_weights(
            BUILDER_BC, dest, source=BUILDER_SRC, command=BUILDER_CMD
        )
        assert w2["sha256"] == weights["sha256"]
        assert w2["trained"] is False


def test_train_step_opcode() -> list[str]:
    """Decode STEP 0x28: TRAIN → STEP → TRAIN_STATUS (dry ≠ trained)."""
    assert STEP_BC.is_file(), STEP_BC
    raw = STEP_BC.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == STEP_SHA256
    bc = load_sparkbc(STEP_BC)
    assert bc["sha256"] == STEP_SHA256
    ops = decode_ops(bc)
    names = [o["name"] for o in ops]
    assert "TRAIN" in names and "STEP" in names
    assert "TRAIN_STATUS" in names
    i_train = names.index("TRAIN")
    i_step = names.index("STEP")
    i_status = names.index("TRAIN_STATUS")
    assert i_train < i_step < i_status, names
    step = ops[i_step]
    assert step["op"] == 0x28
    assert step["name"] == "STEP"
    assert step["hex"].startswith("28 ")
    assert len(step["operands"]) == 2
    dump = format_dump(
        bc,
        source=STEP_SRC,
        command=STEP_CMD,
        label="Train-step SPARK_BC (TRAIN → STEP → TRAIN_STATUS)",
    )
    assert "TRAIN (0x26)" in dump, dump
    assert "STEP (0x28)" in dump, dump
    assert "TRAIN_STATUS (0x27)" in dump, dump
    assert "28 07 00 06 00" in dump
    STEP_DUMP.write_text(dump, encoding="utf-8")
    return names


def test_dry_step_writes_weights() -> dict:
    """apply_dry_step leaves step_n>=1 and trained=false."""
    with tempfile.TemporaryDirectory() as tmp:
        dest = Path(tmp) / "weights.safetensors"
        r1 = apply_dry_step(
            STEP_BC,
            dest,
            step_n=1,
            source=STEP_SRC,
            command=STEP_CMD,
        )
        assert r1["trained"] is False
        assert r1["not_sgd"] is True
        assert r1["step_n"] >= 1
        assert dest.is_file()
        meta = read_safetensors_meta(dest)
        assert int(meta["step_n"]) >= 1
        assert meta["trained"] == "false"
        assert meta["not_sgd"] == "true"
        r2 = apply_dry_step(STEP_BC, dest, step_n=1)
        assert r2["step_n"] > r1["step_n"]
        assert r2["sha256"] != r1["sha256"]
        return r1


def test_serve_stub() -> dict:
    """Dry SERVE marker: served stub, not trained, not production."""
    with tempfile.TemporaryDirectory() as tmp:
        dest = Path(tmp) / "serve-dry-001"
        payload = emit_serve(
            BUILDER_BC,
            dest,
            source=BUILDER_SRC,
            command=BUILDER_CMD,
        )
        assert payload["served"] is True
        assert payload["trained"] is False
        assert payload["not_sgd"] is True
        assert payload["production"] is False
        marker = dest / "SERVE"
        assert marker.is_file()
        body = marker.read_text(encoding="utf-8")
        assert '"op": "serve"' in body
        assert '"production": false' in body
        return payload


def main() -> int:
    """Run dump + weight checks against committed SPARK_BC files."""
    self_info = test_self_magic_and_weights()
    bops = test_builder_train_opcode()
    test_builder_weights_stay_init()
    sops = test_train_step_opcode()
    step_w = test_dry_step_writes_weights()
    serve = test_serve_stub()
    print(
        "ok sha256=%s n_tensors=%d first32=%s train_ops=%s "
        "step_ops=%s step_n=%s serve=%s"
        % (
            self_info["bc"]["sha256"][:12],
            self_info["weights"]["n_tensors"],
            self_info["first"],
            " ".join(bops),
            " ".join(sops),
            step_w["step_n"],
            serve["job_id"],
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
