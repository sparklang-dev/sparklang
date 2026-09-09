"""Thin wrap over real SparkLang compile + SPARK_BC dump paths.

Compile: ``spark-bootstrap --compile`` (or ``sparkc`` / ``./spark
--compile``). Decompile/inspect: ``sparklang.model_lab.bc_dump``.
No invented bytecode. Never 6000. Does not claim beat Claude.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


def _repo_root() -> Path:
    """Resolve pack root or repo root from this file location."""
    here = Path(__file__).resolve()
    # tools/spark-bc-gui → repo; or gui/spark-bc-gui inside a pack
    for parent in here.parents:
        if (parent / "python" / "sparklang").is_dir():
            return parent
        if (parent / "runtime" / "python" / "sparklang").is_dir():
            return parent
    return here.parents[2]


def _ensure_python_path(root: Path) -> None:
    """Put package python/ on sys.path (repo or pack layout)."""
    candidates = [
        root / "python",
        root / "runtime" / "python",
    ]
    for py in candidates:
        if py.is_dir() and str(py) not in sys.path:
            sys.path.insert(0, str(py))


def find_bootstrap(root: Path | None = None) -> Path:
    """Locate spark-bootstrap / sparkc / ./spark for --compile."""
    root = root or _repo_root()
    names = (
        "spark-bootstrap",
        "sparkc",
        "spark",
        "bin/spark-bootstrap",
        "bin/sparkc",
        "bin/spark",
        "runtime/bin/spark-bootstrap",
        "runtime/bin/sparkc",
    )
    for name in names:
        cand = root / name
        if cand.is_file() and os.access(cand, os.X_OK):
            return cand
    which = shutil.which("spark-bootstrap") or shutil.which("sparkc")
    if which:
        return Path(which)
    raise FileNotFoundError(
        "spark-bootstrap not found — build with "
        "`make spark-bootstrap` or unpack the SDK pack"
    )


def compile_spark(
    source: str | Path,
    out: str | Path | None = None,
    *,
    bootstrap: str | Path | None = None,
    root: Path | None = None,
) -> dict[str, Any]:
    """Compile a ``.spark`` file to ``.sparkbc`` via real bootstrap.

    Returns paths + sha256 of emitted bytes. Fails loud on non-zero exit.
    """
    root = root or _repo_root()
    src = Path(source).resolve()
    if not src.is_file():
        raise FileNotFoundError("source missing: %s" % src)
    if out is None:
        out_path = src.with_suffix(".sparkbc")
    else:
        out_path = Path(out).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    boot = Path(bootstrap) if bootstrap else find_bootstrap(root)
    cmd = [str(boot), "--compile", str(src), "-o", str(out_path)]
    proc = subprocess.run(
        cmd,
        cwd=str(root),
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "").strip()
        raise RuntimeError(
            "compile failed (exit %d): %s" % (proc.returncode, err)
        )
    if not out_path.is_file():
        raise RuntimeError("compile produced no file: %s" % out_path)
    raw = out_path.read_bytes()
    import hashlib

    return {
        "source": str(src),
        "out": str(out_path),
        "size": len(raw),
        "sha256": hashlib.sha256(raw).hexdigest(),
        "command": " ".join(cmd),
        "stdout": proc.stdout or "",
    }


def compile_source_text(
    text: str,
    *,
    out: str | Path | None = None,
    bootstrap: str | Path | None = None,
    root: Path | None = None,
    basename: str = "scratch.spark",
) -> dict[str, Any]:
    """Write text to a temp ``.spark`` and compile it."""
    root = root or _repo_root()
    with tempfile.TemporaryDirectory(prefix="spark-bc-gui-") as tmp:
        src = Path(tmp) / basename
        src.write_text(text, encoding="utf-8")
        if out is None:
            dest = Path(tmp) / (Path(basename).stem + ".sparkbc")
            result = compile_spark(
                src, dest, bootstrap=bootstrap, root=root
            )
            # Persist bytes outside the temp dir for callers
            lasting = Path(tempfile.mkstemp(suffix=".sparkbc")[1])
            lasting.write_bytes(Path(result["out"]).read_bytes())
            result["out"] = str(lasting)
            return result
        return compile_spark(
            src, out, bootstrap=bootstrap, root=root
        )


def decompile_sparkbc(
    sparkbc: str | Path,
    *,
    source: str = "",
    command: str = "",
    label: str = "SPARK_BC dump",
    root: Path | None = None,
) -> str:
    """Disassemble / inspect a real ``.sparkbc`` to readable text."""
    root = root or _repo_root()
    _ensure_python_path(root)
    from sparklang.model_lab.bc_dump import format_dump, load_sparkbc

    path = Path(sparkbc).resolve()
    bc = load_sparkbc(path)
    return format_dump(
        bc,
        source=source or str(path),
        command=command or "(gui decompile)",
        label=label,
    )


def sample_source() -> str:
    """Minimal ``.spark`` sample for the GUI starter pane."""
    return (
        "# SparkLang sample — compile to SPARK_BC\n"
        "model code\n"
        'ask "hello from SparkLang GUI" -> reply\n'
        "print reply\n"
    )
