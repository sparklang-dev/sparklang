"""Dry serve stub from SPARK_BC genome — not a production LLM.

Writes a SERVE marker under out/serve/<job>/. served=true means the
stub contract ran; trained stays false; production stays false.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from sparklang.model_lab.bc_dump import load_sparkbc


def emit_serve_stub(
    sparkbc_path: str | Path,
    dest_dir: str | Path,
    *,
    source: str = "",
    command: str = "",
    job_id: str = "serve-dry-001",
) -> dict[str, Any]:
    """Emit a dry SERVE marker for a real .sparkbc genome.

    This is not HTTP inference, not SGD, and not a foundation model.
    """
    bc = load_sparkbc(sparkbc_path)
    out = Path(dest_dir)
    out.mkdir(parents=True, exist_ok=True)
    marker = out / "SERVE"
    payload: dict[str, Any] = {
        "op": "serve",
        "mode": "dry-run",
        "status": "implemented",
        "job_id": job_id,
        "genome": "SPARK_BC",
        "sparkbc": str(sparkbc_path),
        "sha256": bc["sha256"],
        "size_bytes": bc["size"],
        "source": source or str(sparkbc_path),
        "command": command or "(already compiled)",
        "served": True,
        "trained": False,
        "not_sgd": True,
        "production": False,
        "note": (
            "dry serve stub — marker only; not a production LLM; "
            "not trained; not SGD"
        ),
        "marker": str(marker),
    }
    marker.write_text(
        json.dumps(payload, indent=2) + "\n",
        encoding="utf-8",
    )
    return payload
