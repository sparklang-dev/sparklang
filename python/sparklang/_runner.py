"""Invoke the ``spark`` CLI from a host language (Python)."""

from __future__ import annotations

import os
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Union

PathLike = Union[str, Path]


class SparkBinNotFound(RuntimeError):
    """Raised when no ``spark`` binary can be located."""


class SparkRunError(RuntimeError):
    """Raised by ``RunResult.check()`` on a non-zero exit."""

    def __init__(self, result: "RunResult") -> None:
        self.result = result
        msg = (
            f"spark exited {result.returncode}"
            f" (mode={result.mode})"
        )
        if result.stderr.strip():
            msg = f"{msg}: {result.stderr.strip()[:200]}"
        super().__init__(msg)


@dataclass(frozen=True)
class RunResult:
    """Outcome of one ``spark`` invocation."""

    returncode: int
    stdout: str
    stderr: str
    mode: str
    path: Optional[str] = None

    @property
    def ok(self) -> bool:
        """True when the process exited 0."""
        return self.returncode == 0

    def check(self) -> "RunResult":
        """Return self, or raise ``SparkRunError`` if not ok."""
        if not self.ok:
            raise SparkRunError(self)
        return self


def find_spark(explicit: Optional[PathLike] = None) -> Path:
    """Locate the ``spark`` ELF (fail loud if missing).

    Order: ``explicit`` → ``SPARK_BIN`` → ``./spark`` → walk-up
    from cwd / this package → ``PATH``.
    """
    candidates: list[Path] = []
    if explicit is not None:
        candidates.append(Path(explicit))
    env = os.environ.get("SPARK_BIN")
    if env:
        candidates.append(Path(env))
    candidates.append(Path.cwd() / "spark")
    here = Path(__file__).resolve()
    for base in (Path.cwd(), *here.parents):
        candidates.append(base / "spark")
    path_env = os.environ.get("PATH", "")
    for part in path_env.split(os.pathsep):
        if part:
            candidates.append(Path(part) / "spark")

    seen: set[Path] = set()
    for cand in candidates:
        try:
            resolved = cand.resolve()
        except OSError:
            continue
        if resolved in seen:
            continue
        seen.add(resolved)
        if resolved.is_file() and os.access(resolved, os.X_OK):
            return resolved

    raise SparkBinNotFound(
        "spark binary not found — build with `make`, set "
        "SPARK_BIN, or run from the repo root"
    )


def _looks_like_path(text: str) -> bool:
    """Heuristic: path vs inline source string."""
    if "\n" in text or "\r" in text:
        return False
    p = Path(text)
    if p.suffix == ".spark":
        return True
    if p.exists():
        return True
    return False


def run(
    program: PathLike,
    *,
    dry: bool = True,
    live: bool = False,
    spark_bin: Optional[PathLike] = None,
    timeout: Optional[float] = 120.0,
    cwd: Optional[PathLike] = None,
    check: bool = False,
) -> RunResult:
    """Execute a ``.spark`` path or source string via the CLI.

    Default is dry-run (fixtures). Pass ``live=True`` for
    ``./spark --live`` (needs gateway / backends as documented).
    ``dry=False`` without ``live=True`` is refused — fail loud.
    """
    if live and dry:
        # live wins only when caller sets dry=False
        dry = False
    if live:
        mode = "live"
        flag = "--live"
    elif dry:
        mode = "dry-run"
        flag = "--dry-run"
    else:
        raise ValueError(
            "run() needs dry=True (default) or live=True; "
            "open exec without a mode is not supported"
        )

    binary = find_spark(spark_bin)
    work_cwd = Path(cwd) if cwd is not None else Path.cwd()

    text = str(program)
    tmp_path: Optional[Path] = None
    try:
        if _looks_like_path(text):
            src = Path(text)
            if not src.is_file():
                raise FileNotFoundError(
                    f"spark program not found: {src}"
                )
            prog_path = src.resolve()
        else:
            fd, name = tempfile.mkstemp(
                suffix=".spark",
                prefix="sparklang-embed-",
            )
            os.close(fd)
            tmp_path = Path(name)
            tmp_path.write_text(text, encoding="utf-8")
            prog_path = tmp_path

        proc = subprocess.run(
            [str(binary), flag, str(prog_path)],
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=str(work_cwd),
            check=False,
        )
        result = RunResult(
            returncode=proc.returncode,
            stdout=proc.stdout or "",
            stderr=proc.stderr or "",
            mode=mode,
            path=str(prog_path) if tmp_path is None else None,
        )
    finally:
        if tmp_path is not None:
            try:
                tmp_path.unlink(missing_ok=True)
            except OSError:
                pass

    if check:
        result.check()
    return result
