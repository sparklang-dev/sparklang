"""Spark IDE core — real compile/decompile/browse/ask/weights/report.

Wraps ``spark-bootstrap --compile``, ``sparklang.model_lab.bc_dump``,
optional ``spark_ask`` / TinyCoder, safetensors list/play, helpers and
shadows. No invented bytecode. Never 6000. No frontier-parity claim.
Not an OpenBin clone — Spark-native workflow only.
"""

from __future__ import annotations

import hashlib
import importlib.util
import os
import shutil
import struct
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

HONESTY = (
    "Honest note: Spark Ask uses dump SoT + optional tiny owned "
    "coder. Not OpenBin-level RE Q&A. No frontier-parity claim."
)


def _repo_root() -> Path:
    """Resolve pack root or repo root from this file location."""
    here = Path(__file__).resolve()
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
    tools = root / "tools"
    if tools.is_dir() and str(tools) not in sys.path:
        sys.path.insert(0, str(tools))


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
    """Compile a ``.spark`` file to ``.sparkbc`` via real bootstrap."""
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
            lasting = Path(tempfile.mkstemp(suffix=".sparkbc")[1])
            lasting.write_bytes(Path(result["out"]).read_bytes())
            result["out"] = str(lasting)
            return result
        return compile_spark(
            src, out, bootstrap=bootstrap, root=root
        )


def load_bc(
    sparkbc: str | Path,
    *,
    root: Path | None = None,
) -> dict[str, Any]:
    """Load a real ``.sparkbc`` dict via model_lab."""
    root = root or _repo_root()
    _ensure_python_path(root)
    from sparklang.model_lab.bc_dump import load_sparkbc

    return load_sparkbc(Path(sparkbc).resolve())


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
    from sparklang.model_lab.bc_dump import format_dump

    path = Path(sparkbc).resolve()
    bc = load_bc(path, root=root)
    return format_dump(
        bc,
        source=source or str(path),
        command=command or "(gui decompile)",
        label=label,
    )


def decode_ops_list(
    sparkbc: str | Path,
    *,
    root: Path | None = None,
) -> list[dict[str, Any]]:
    """Return opcode rows for browse / jump."""
    root = root or _repo_root()
    _ensure_python_path(root)
    from sparklang.model_lab.bc_dump import decode_ops

    return decode_ops(load_bc(sparkbc, root=root))


def browse_opcodes(
    sparkbc: str | Path,
    *,
    root: Path | None = None,
) -> list[dict[str, Any]]:
    """Browse list: ip, name, hex, dump_line hint for jump."""
    root = root or _repo_root()
    ops = decode_ops_list(sparkbc, root=root)
    out: list[dict[str, Any]] = []
    for op in ops:
        needle = "code+%d" % int(op["ip"])
        out.append(
            {
                "ip": int(op["ip"]),
                "name": str(op["name"]),
                "hex": str(op["hex"]),
                "operands": list(op.get("operands") or []),
                "dump_needle": needle,
                "label": "%s  %s" % (needle, op["name"]),
            }
        )
    return out


def browse_source_symbols(source_text: str) -> list[dict[str, Any]]:
    """Simple source outline: model / ask / print / labels."""
    rows: list[dict[str, Any]] = []
    for i, line in enumerate(source_text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        kind = None
        if stripped.startswith("model "):
            kind = "model"
        elif stripped.startswith("ask ") or stripped.startswith("ask\t"):
            kind = "ask"
        elif stripped.startswith("print "):
            kind = "print"
        elif stripped.endswith(":") and " " not in stripped:
            kind = "label"
        if kind:
            rows.append(
                {
                    "line": i,
                    "kind": kind,
                    "text": stripped[:120],
                    "label": "L%d %s" % (i, kind),
                }
            )
    return rows


def list_workspace_files(
    root: Path | None = None,
    *,
    limit: int = 200,
) -> list[dict[str, Any]]:
    """List nearby ``.spark`` / ``.sparkbc`` for the Files pane."""
    root = root or _repo_root()
    roots = [
        root / "examples",
        root / "docs" / "examples",
        root / "selfhost",
        root / "out",
    ]
    found: list[dict[str, Any]] = []
    for base in roots:
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*")):
            if not path.is_file():
                continue
            if path.suffix.lower() not in (".spark", ".sparkbc"):
                continue
            rel = str(path.relative_to(root))
            found.append(
                {
                    "path": str(path),
                    "rel": rel,
                    "suffix": path.suffix.lower(),
                    "label": rel,
                }
            )
            if len(found) >= limit:
                return found
    return found


def _const_string(bc: dict[str, Any], idx: int) -> str | None:
    """Resolve const index → UTF-8 string when kind is STR."""
    consts = bc.get("consts") or []
    strings = bc.get("strings") or []
    if idx >= len(consts):
        return None
    c = consts[idx]
    if int(c.get("kind", -1)) != 0:
        return None
    si = int(c.get("payload", -1))
    if si < 0 or si >= len(strings):
        return None
    return strings[si].decode("utf-8", errors="replace")


def sync_map(
    source_text: str,
    sparkbc: str | Path,
    *,
    root: Path | None = None,
) -> list[dict[str, Any]]:
    """Map dump opcodes ↔ source lines via string-pool hits.

    Best-effort sync highlight for split view — not a full DWARF map.
    """
    root = root or _repo_root()
    bc = load_bc(sparkbc, root=root)
    ops = decode_ops_list(sparkbc, root=root)
    src_lines = source_text.splitlines()
    maps: list[dict[str, Any]] = []
    for op in ops:
        hit_line: int | None = None
        hit_str: str | None = None
        for operand in op.get("operands") or []:
            text = _const_string(bc, int(operand))
            if not text:
                continue
            for i, line in enumerate(src_lines, start=1):
                if text in line:
                    hit_line = i
                    hit_str = text
                    break
            if hit_line is not None:
                break
        maps.append(
            {
                "ip": int(op["ip"]),
                "name": str(op["name"]),
                "dump_needle": "code+%d" % int(op["ip"]),
                "source_line": hit_line,
                "string": hit_str,
            }
        )
    return maps


def _ops_names(ops: list[Any]) -> list[str]:
    """Collect opcode names from decode rows."""
    names: list[str] = []
    for row in ops:
        if isinstance(row, dict) and "name" in row:
            names.append(str(row["name"]))
        elif isinstance(row, str):
            names.append(row)
    return names


def factual_ask(
    question: str,
    *,
    dump_text: str = "",
    ops: list[Any] | None = None,
    sha256: str = "",
) -> str | None:
    """Answer dump-grounded factual asks without a neural model."""
    q = question.lower().strip()
    names = _ops_names(ops or [])
    if any(k in q for k in ("how many op", "opcode count", "ops count")):
        if names:
            return (
                "This SPARK_BC has %d opcodes: %s."
                % (len(names), ", ".join(names))
            )
    if any(k in q for k in ("what op", "list op", "opcodes", "mnemonics")):
        if names:
            return (
                "Opcodes in this dump: %s. "
                "SPARK_BC is orchestration bytecode, not ELF/PE."
                % ", ".join(names)
            )
    if "sha" in q or "hash" in q:
        if sha256:
            return "Dump sha256 is %s." % sha256
    if any(k in q for k in ("magic", "spbc", "what is this")):
        if "SPBC" in dump_text or names:
            return (
                "This is a SPARK_BC dump (magic SPBC) — Spark "
                "orchestration bytecode. Dump text is SoT; not "
                "neural weights and not a malware RE project."
            )
    if "train" in q and names:
        has = "TRAIN" in names
        return (
            "TRAIN opcode is %s in this dump."
            % ("present" if has else "absent")
        )
    return None


def _try_voice_ask(
    question: str,
    ctx: dict[str, Any],
    *,
    root: Path,
) -> dict[str, Any] | None:
    """Hook sibling ``spark_ask.voice_ask`` when present on PYTHONPATH."""
    _ensure_python_path(root)
    path = root / "tools" / "spark_ask" / "voice_ask.py"
    if not path.is_file():
        return None
    spec = importlib.util.spec_from_file_location(
        "spark_ask_voice_ask", path
    )
    if spec is None or spec.loader is None:
        return None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    fn = getattr(mod, "answer_question", None)
    if not callable(fn):
        return None
    return fn(question, ctx, root=root)


def ask_over_dump(
    question: str,
    *,
    dump_text: str = "",
    ops: list[Any] | None = None,
    sha256: str = "",
    sparkbc: str | Path | None = None,
    root: Path | None = None,
    use_voice_hook: bool = True,
) -> dict[str, Any]:
    """Text Ask over dump context — factual, voice hook, or honesty.

    Prefer dump SoT. Optional voice-ask sibling / TinyCoder when landed.
    """
    root = root or _repo_root()
    ops = list(ops or [])
    if sparkbc and not ops:
        try:
            ops = decode_ops_list(sparkbc, root=root)
            bc = load_bc(sparkbc, root=root)
            sha256 = sha256 or str(bc.get("sha256") or "")
            if not dump_text:
                dump_text = decompile_sparkbc(
                    sparkbc, root=root
                )
        except (OSError, ValueError, RuntimeError):
            pass
    ctx: dict[str, Any] = {
        "dump_text": dump_text,
        "ops": ops,
        "sha256": sha256,
        "sparkbc": str(sparkbc) if sparkbc else None,
    }
    fact = factual_ask(
        question,
        dump_text=dump_text,
        ops=ops,
        sha256=sha256,
    )
    if fact:
        return {
            "engine": "factual",
            "answer": fact,
            "honesty": HONESTY,
        }
    if use_voice_hook:
        hooked = _try_voice_ask(question, ctx, root=root)
        if isinstance(hooked, dict) and hooked.get("answer"):
            hooked.setdefault("honesty", HONESTY)
            return hooked
    names = _ops_names(ops)
    fallback = (
        "No owned coder answer for that open-ended ask yet. "
        "Dump SoT: %d opcodes%s. %s"
        % (
            len(names),
            (" (%s)" % ", ".join(names[:12])) if names else "",
            HONESTY,
        )
    )
    return {
        "engine": "fallback",
        "answer": fallback,
        "honesty": HONESTY,
    }


def list_weight_files(
    root: Path | None = None,
    *,
    limit: int = 50,
) -> list[dict[str, Any]]:
    """Find Spark ``.safetensors`` (gallery catalog when present)."""
    root = root or _repo_root()
    _ensure_python_path(root)
    try:
        from sparklang.model_lab.weight_gallery import catalog

        doc = catalog(root=root)
        rows = list(doc.get("files") or [])
        found: list[dict[str, Any]] = []
        for row in rows:
            if row.get("error"):
                continue
            rel = str(row.get("path") or "")
            if not rel:
                continue
            path = (root / rel).resolve()
            if not path.is_file():
                continue
            found.append(
                {
                    "path": str(path),
                    "rel": rel,
                    "size": path.stat().st_size,
                    "label": "%s [%s]"
                    % (
                        rel,
                        row.get("kind") or row.get("size_class") or "?",
                    ),
                    "kind": row.get("kind"),
                    "size_class": row.get("size_class"),
                }
            )
            if len(found) >= limit:
                return found
        if found:
            return found
    except (ImportError, OSError, ValueError, TypeError):
        pass
    found = []
    for base in (root / "models", root / "out", root / "docs" / "examples"):
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.safetensors")):
            if not path.is_file():
                continue
            rel = str(path.relative_to(root))
            found.append(
                {
                    "path": str(path),
                    "rel": rel,
                    "size": path.stat().st_size,
                    "label": rel,
                }
            )
            if len(found) >= limit:
                return found
    return found


def summarize_weights(
    path: str | Path,
    *,
    root: Path | None = None,
) -> dict[str, Any]:
    """List tensor names/shapes from a Spark safetensors file."""
    root = root or _repo_root()
    _ensure_python_path(root)
    from sparklang.model_lab.weights import read_safetensors

    meta, tensors = read_safetensors(Path(path).resolve())
    rows = []
    for name, (shape, blob) in sorted(tensors.items()):
        rows.append(
            {
                "name": name,
                "shape": list(shape),
                "nbytes": len(blob),
                "nfloat": len(blob) // 4,
            }
        )
    return {
        "path": str(path),
        "metadata": meta,
        "tensors": rows,
        "count": len(rows),
    }


def play_tensor(
    path: str | Path,
    name: str,
    *,
    root: Path | None = None,
    sample: int = 8,
) -> dict[str, Any]:
    """CPU stats + sample floats for one tensor (weights play)."""
    root = root or _repo_root()
    _ensure_python_path(root)
    from sparklang.model_lab.weights import read_safetensors

    _meta, tensors = read_safetensors(Path(path).resolve())
    if name not in tensors:
        raise KeyError("tensor missing: %s" % name)
    shape, blob = tensors[name]
    n = len(blob) // 4
    if n == 0:
        return {
            "name": name,
            "shape": list(shape),
            "n": 0,
            "mean": 0.0,
            "min": 0.0,
            "max": 0.0,
            "sample": [],
        }
    vals = [
        struct.unpack_from("<f", blob, i * 4)[0] for i in range(n)
    ]
    take = vals[: max(1, min(sample, n))]
    return {
        "name": name,
        "shape": list(shape),
        "n": n,
        "mean": sum(vals) / float(n),
        "min": min(vals),
        "max": max(vals),
        "sample": take,
        "device": "cpu",
        "note": "CPU play only — never RTX PRO 6000",
    }


def export_report_markdown(
    *,
    dump_text: str = "",
    ops: list[Any] | None = None,
    sha256: str = "",
    source_path: str = "",
    sparkbc_path: str = "",
    ask_notes: str = "",
    title: str = "Spark IDE analysis",
) -> str:
    """Export a markdown analysis stub from dump + optional ask notes."""
    names = _ops_names(ops or [])
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
    lines = [
        "# %s" % title,
        "",
        "- Generated: %s" % now,
        "- Source: `%s`" % (source_path or "(buffer)"),
        "- SPARK_BC: `%s`" % (sparkbc_path or "(none)"),
        "- sha256: `%s`" % (sha256 or "(unknown)"),
        "- opcode count: %d" % len(names),
        "- never_6000: true",
        "",
        "## Opcodes",
        "",
    ]
    if names:
        for i, n in enumerate(names):
            lines.append("%d. `%s`" % (i, n))
    else:
        lines.append("(none decoded)")
    lines.extend(["", "## Dump excerpt", "", "```"])
    excerpt = (dump_text or "").strip()
    if len(excerpt) > 4000:
        excerpt = excerpt[:4000] + "\n…(truncated)…"
    lines.append(excerpt or "(empty)")
    lines.extend(["```", ""])
    if ask_notes.strip():
        lines.extend(["## Ask notes", "", ask_notes.strip(), ""])
    lines.extend(
        [
            "## Honesty",
            "",
            HONESTY,
            "",
        ]
    )
    return "\n".join(lines)


def _tool_dirs(root: Path) -> dict[str, Path]:
    """Resolve helpers / shadows directories (repo or pack)."""
    helpers = root / "tools" / "spark_helpers"
    if not helpers.is_dir():
        helpers = root / "helpers"
    shadows = root / "tools" / "spark_shadows"
    if not shadows.is_dir():
        shadows = root / "shadows"
    return {"helpers": helpers, "shadows": shadows}


def list_helpers(root: Path | None = None) -> list[dict[str, Any]]:
    """One-click helper entries for the IDE Tools pane."""
    root = root or _repo_root()
    d = _tool_dirs(root)["helpers"]
    entries = [
        ("opcodes", "opcode_sheet.py", "python"),
        ("fixture_lint", "fixture_lint.py", "python"),
        ("compile", "compile.sh", "bash"),
        ("decompile", "decompile.sh", "bash"),
    ]
    out: list[dict[str, Any]] = []
    for key, name, kind in entries:
        path = d / name
        out.append(
            {
                "key": key,
                "name": name,
                "kind": kind,
                "path": str(path),
                "available": path.is_file(),
                "label": "helper:%s" % key,
            }
        )
    return out


def list_shadows(root: Path | None = None) -> list[dict[str, Any]]:
    """One-click shadow workflow entries."""
    root = root or _repo_root()
    d = _tool_dirs(root)["shadows"]
    entries = [
        ("copy", "shadow_copy.sh"),
        ("build", "shadow_build.sh"),
        ("verify", "shadow_verify.sh"),
    ]
    out: list[dict[str, Any]] = []
    for key, name in entries:
        path = d / name
        out.append(
            {
                "key": key,
                "name": name,
                "kind": "bash",
                "path": str(path),
                "available": path.is_file(),
                "label": "shadow:%s" % key,
            }
        )
    return out


def run_helper(
    key: str,
    *,
    root: Path | None = None,
    extra_args: list[str] | None = None,
    timeout: int = 60,
) -> dict[str, Any]:
    """Run a named helper script; return stdout/stderr/exit."""
    root = root or _repo_root()
    match = next((h for h in list_helpers(root) if h["key"] == key), None)
    if match is None or not match["available"]:
        raise FileNotFoundError("helper unavailable: %s" % key)
    path = Path(match["path"])
    if match["kind"] == "python":
        cmd = [sys.executable, str(path)]
    else:
        cmd = ["bash", str(path)]
    if extra_args:
        cmd.extend(extra_args)
    proc = subprocess.run(
        cmd,
        cwd=str(root),
        capture_output=True,
        text=True,
        check=False,
        timeout=timeout,
    )
    return {
        "key": key,
        "command": " ".join(cmd),
        "returncode": proc.returncode,
        "stdout": proc.stdout or "",
        "stderr": proc.stderr or "",
        "ok": proc.returncode == 0,
    }


def run_shadow(
    key: str,
    name: str = "ide-shadow",
    *,
    root: Path | None = None,
    timeout: int = 120,
) -> dict[str, Any]:
    """Run shadow copy/build/verify for an isolated name."""
    root = root or _repo_root()
    match = next((s for s in list_shadows(root) if s["key"] == key), None)
    if match is None or not match["available"]:
        raise FileNotFoundError("shadow unavailable: %s" % key)
    env = os.environ.copy()
    env["SPARK_SHADOW_ROOT"] = str(root / "out" / "shadow")
    cmd = ["bash", match["path"], name]
    proc = subprocess.run(
        cmd,
        cwd=str(root),
        capture_output=True,
        text=True,
        check=False,
        timeout=timeout,
        env=env,
    )
    return {
        "key": key,
        "name": name,
        "command": " ".join(cmd),
        "returncode": proc.returncode,
        "stdout": proc.stdout or "",
        "stderr": proc.stderr or "",
        "ok": proc.returncode == 0,
    }


def dump_line_for_needle(dump_text: str, needle: str) -> int | None:
    """1-based dump pane line containing needle, or None."""
    for i, line in enumerate(dump_text.splitlines(), start=1):
        if needle in line:
            return i
    return None


def sample_source() -> str:
    """Minimal ``.spark`` sample for the GUI starter pane."""
    return (
        "# SparkLang sample — compile to SPARK_BC\n"
        "model code\n"
        'ask "hello from SparkLang IDE" -> reply\n'
        "print reply\n"
    )


def theme_colors() -> dict[str, str]:
    """Spark dark engineer palette (delegates to theme.IDE)."""
    from .theme import IDE

    return {
        "bg": IDE["bg"],
        "panel": IDE["bg_panel"],
        "panel2": IDE["bg_elevated"],
        "border": IDE["border"],
        "text": IDE["text"],
        "muted": IDE["text_muted"],
        "brand": IDE["accent"],
        "brand_dim": IDE["accent_dark"],
        "accent": IDE["focus"],
        "code_bg": IDE["bg"],
        "select": IDE["selection"],
    }
