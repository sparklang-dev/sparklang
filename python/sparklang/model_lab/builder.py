"""Builder whose genome is SPARK_BC bytes — not imported weights.

Implemented: decode a real .sparkbc and emit a stub plan.
Planned: train / serve a foundation model from that genome.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from sparklang.model_lab.bc_dump import (
    decode_ops,
    hex_preview,
    load_sparkbc,
)
from sparklang.model_lab.weights import emit_init_weights


def emit_stub(
    sparkbc_path: str | Path,
    *,
    source: str,
    command: str,
) -> dict[str, Any]:
    """Inspect SPARK_BC and emit a base-model builder stub.

    The genome is the bytecode file. This is not a trained LLM.
    """
    bc = load_sparkbc(sparkbc_path)
    ops = decode_ops(bc)
    mnemonics = [op["name"] for op in ops]
    return {
        "op": "builder",
        "status": "implemented",
        "genome": "SPARK_BC",
        "note": (
            "SPARK_BC seed plus Spark-created init weights. "
            "Not trained. SPARK_BC is not neural weights."
        ),
        "source": source,
        "command": command,
        "sparkbc": str(sparkbc_path),
        "sha256": bc["sha256"],
        "size_bytes": bc["size"],
        "magic": bc["magic"],
        "version": bc["version"],
        "first_32_hex": hex_preview(bc["raw"], 32),
        "nstrings": len(bc["strings"]),
        "nconsts": len(bc["consts"]),
        "ncode": bc["ncode"],
        "opcodes": mnemonics,
        "trained": False,
        "served": False,
        "implemented": [
            "compile .spark -> .sparkbc (spark-bootstrap --compile)",
            "TRAIN / TRAIN_STATUS ops in SPARK_BC (training program)",
            "execute TRAIN/TRAIN_STATUS from .sparkbc (dry fixture)",
            "dump hex + decoded ops",
            "emit this stub from those bytes",
            "emit structured Xavier init weights from those bytes",
        ],
        "planned": [
            "Spark-hosted compiler (self-host Stage 4 still C)",
            "train from this Spark-created init "
            "(owner train-grant)",
            "serve a model grown from this seed",
        ],
    }


def emit_base(
    sparkbc_path: str | Path,
    weights_dest: str | Path,
    *,
    source: str,
    command: str,
) -> dict[str, Any]:
    """Bytecode stub plus Spark-created init weights."""
    stub = emit_stub(sparkbc_path, source=source, command=command)
    weights = emit_init_weights(
        sparkbc_path,
        weights_dest,
        source=source,
        command=command,
    )
    stub["weights"] = weights
    return stub
