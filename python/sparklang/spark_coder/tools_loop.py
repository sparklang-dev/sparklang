"""Optional compile/verify tools on top of the reference TinyCoder.

The brain remains owned weights — these tools only check/compile
Spark / SPARK_BC artifacts. The product coder is the self-hosted
30B endpoint (see `real_coder.py`).
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any

from sparklang.spark_coder.model import TinyCoder


def find_bootstrap(repo: Path) -> Path | None:
    """Locate spark-bootstrap / sparkc in repo root."""
    for name in ("spark-bootstrap", "sparkc"):
        p = repo / name
        if p.is_file():
            return p
    return None


def compile_spark(
    source: Path,
    out_bc: Path,
    *,
    bootstrap: Path,
) -> dict[str, Any]:
    """Compile .spark → .sparkbc via real bootstrap."""
    out_bc.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(bootstrap),
        "--compile",
        str(source),
        "-o",
        str(out_bc),
    ]
    proc = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        check=False,
    )
    return {
        "ok": proc.returncode == 0 and out_bc.is_file(),
        "returncode": proc.returncode,
        "cmd": cmd,
        "stdout": (proc.stdout or "")[-2000:],
        "stderr": (proc.stderr or "")[-2000:],
        "out": str(out_bc),
        "size": out_bc.stat().st_size if out_bc.is_file() else 0,
    }


def tool_loop_complete(
    model: TinyCoder,
    *,
    task: str,
    candidate_sources: list[Path],
    work_dir: Path,
    bootstrap: Path | None,
) -> dict[str, Any]:
    """Score authored candidates with TinyCoder; compile winner.

    Deterministic: model ranks first-byte / prompt affinity; tools
    compile. Does not invent HF/frontier-API completions as the brain.
    """
    work_dir.mkdir(parents=True, exist_ok=True)
    ranked: list[dict[str, Any]] = []
    for src in candidate_sources:
        text = src.read_text(encoding="utf-8")
        # Prefer candidates whose first assistant byte the model
        # predicts from the task prompt.
        sc = model.score_next_byte(task, text[:1] or "\0")
        ranked.append(
            {
                "path": str(src),
                "hit": sc["hit"],
                "pred": sc["pred_byte"],
                "want": sc["want_byte"],
                "chars": len(text),
            }
        )
    ranked.sort(key=lambda r: (not r["hit"], r["chars"]))
    if not ranked:
        return {
            "ok": False,
            "error": "no candidates",
            "brain": "owned-weights",
        }
    winner = Path(ranked[0]["path"])
    gen = model.generate(task + "\n", max_new=24)
    result: dict[str, Any] = {
        "ok": False,
        "task": task,
        "winner": str(winner),
        "ranked": ranked,
        "generate_preview": gen,
        "brain": "owned-weights",
    }
    if bootstrap is None:
        result["compile"] = {
            "ok": False,
            "skipped": True,
            "reason": "no spark-bootstrap",
        }
        result["ok"] = ranked[0]["hit"]
        return result
    out_bc = work_dir / (winner.stem + ".sparkbc")
    compile_info = compile_spark(
        winner, out_bc, bootstrap=bootstrap
    )
    result["compile"] = compile_info
    result["ok"] = bool(compile_info["ok"] and ranked[0]["hit"])
    marker = work_dir / "tool_loop.json"
    marker.write_text(
        json.dumps(result, indent=2) + "\n", encoding="utf-8"
    )
    result["marker"] = str(marker)
    return result
