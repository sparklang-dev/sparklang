#!/usr/bin/env python3
"""Build a local Spark analysis folder from .spark or .sparkbc.

Spark-native project loop (inspired by clear CLI→inspect→report
methods elsewhere — not a clone):

  compile (if needed) → dump → ops list → REPORT.md stub
  → screenshot placeholder → optional serve → optional Ask stub

Dump remains SoT. Never uploads. Never 6000. No parity claim.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT / "python") not in sys.path:
    sys.path.insert(0, str(ROOT / "python"))
if str(ROOT / "tools") not in sys.path:
    sys.path.insert(0, str(ROOT / "tools"))

from sparklang.model_lab.bc_dump import (  # noqa: E402
    decode_ops,
    format_dump,
    load_sparkbc,
)
from sparklang.model_lab.builder import emit_serve  # noqa: E402

SCREENSHOT_NOTE = """\
# Screenshot placeholder

Spark keeps analysis **local**. Drop a real capture here later
(e.g. `spark-bc-gui` pane, terminal dump, or IDE).

Do **not** paste third-party product UI screenshots into the
public site as if they were Spark.
"""

REPORT_STUB = """\
# Spark analysis report — {name}

Generated: {ts}
Tool: `helpers/spark-analyze` (SparkLang project loop)

## Identity

| Field | Value |
|-------|-------|
| Source | `{source}` |
| SPARK_BC | `{sparkbc}` |
| sha256 | `{sha256}` |
| size | {size} bytes |
| ops | {nop} |

## What this is

SPARK_BC is **orchestration bytecode** (TRAIN / STEP / ASK / …),
not ELF/PE malware pseudo-C and not neural weight tensors.
The dump file (`dump.txt`) is the deterministic SoT.

## Ops summary

{ops_md}

## Next steps (local)

1. Read `dump.txt` / `dump.json` / `dump.html` / `ops.json`.
2. Optional: `spark-bc-gui` for a readable pane.
3. Optional Ask stub: re-run with `--ask` (owned TinyCoder or
   notes — **not** a SaaS reverse-engineering agent).
4. Optional serve: re-run with `--serve` (tiny CPU forward).

## Honesty

- Not OpenBin / OpenAPK / Ghidra / JADX.
- No frontier-parity claim.
- Never RTX PRO 6000.
- No cloud upload from this tool.
"""

ASK_NO_WEIGHTS = """\
# Ask stub — capability note

`--ask` requested, but owned TinyCoder weights were not found at:

`{weights}`

### What Ask means here (Spark)

Local, honest stub — **not** a third-party BYOK RE agent and
**not** a claim that Spark recovers C source from arbitrary
binaries.

To enable a tiny local note from owned weights:

```bash
make spark-coder-train
./helpers/spark-analyze path/to/file.spark --ask
```

Or point at weights:

```bash
./helpers/spark-analyze file.sparkbc --ask \\
  --weights models/spark-coder/weights.safetensors
```

TinyCoder is a **toy** coding model on authored fixtures.
It makes **no** frontier-parity claim. Prefer `dump.txt` / `ops.json`
as SoT.
"""

ASK_WITH_WEIGHTS = """\
# Ask stub — owned spark-coder (local)

Weights: `{weights}`
Prompt focus: summarize SPARK_BC ops for `{name}`
Generated: {ts}

## Model honesty

- Brain: **owned** TinyCoder (`spark-coder`)
- Not a frontier API, not OpenBin Ask, not Bifrost SaaS
- No frontier-parity claim
- Prefer dump/ops as SoT if this text conflicts

## Ops context (from dump)

{ops_preview}

## Model output

```
{output}
```
"""


def find_bootstrap(root: Path) -> Path | None:
    """Locate spark-bootstrap binary under the repo root."""
    for cand in (
        root / "spark-bootstrap",
        root / "bin" / "spark-bootstrap",
    ):
        if cand.is_file() and cand.stat().st_mode & 0o111:
            return cand
    return None


def _stem_name(path: Path) -> str:
    name = path.name
    for suf in (".sparkbc", ".spark"):
        if name.endswith(suf):
            return name[: -len(suf)]
    return path.stem


def _rel(path: Path, root: Path) -> str:
    try:
        return str(path.resolve().relative_to(root.resolve()))
    except ValueError:
        return str(path.resolve())


def _ops_rows(bc: dict[str, Any]) -> list[dict[str, Any]]:
    """Decode SPARK_BC ops into JSON-friendly rows."""
    rows: list[dict[str, Any]] = []
    for op in decode_ops(bc):
        rows.append(
            {
                "ip": op["ip"],
                "name": op["name"],
                "op": op["op"],
                "operands": op["operands"],
                "hex": op["hex"],
            }
        )
    return rows


def _ops_markdown(rows: list[dict[str, Any]]) -> str:
    """Compact markdown table of opcode names."""
    if not rows:
        return "_No ops decoded._"
    lines = [
        "| ip | op | name |",
        "|----|----|------|",
    ]
    for r in rows:
        lines.append(
            "| %d | 0x%02x | `%s` |"
            % (r["ip"], r["op"], r["name"])
        )
    return "\n".join(lines)


def _run_ask(
    *,
    weights: Path,
    name: str,
    rows: list[dict[str, Any]],
) -> str:
    """Generate a short local note via owned TinyCoder."""
    from sparklang.spark_coder.model import TinyCoder

    model = TinyCoder.from_weights(weights)
    names = ", ".join(r["name"] for r in rows[:24])
    prompt = (
        "Spark SPARK_BC ops for %s: %s.\n"
        "One short note: bytecode orchestration, not malware C.\n"
        % (name, names or "(empty)")
    )
    out = model.generate(prompt, max_new=96)
    text = out.get("text") if isinstance(out, dict) else None
    if not text:
        text = json.dumps(out, indent=2)
    return str(text).strip()


def run_analyze(
    input_path: Path,
    *,
    out_dir: Path | None = None,
    root: Path = ROOT,
    serve: bool = False,
    ask: bool = False,
    weights: Path | None = None,
) -> dict[str, Any]:
    """Compile/dump into a local analysis folder; return meta."""
    src = input_path.resolve()
    if not src.is_file():
        raise FileNotFoundError("input not found: %s" % src)

    name = _stem_name(src)
    dest = (
        out_dir.resolve()
        if out_dir is not None
        else (root / "out" / "analyze" / name).resolve()
    )
    dest.mkdir(parents=True, exist_ok=True)

    sparkbc = dest / "program.sparkbc"
    source_note = _rel(src, root)
    compile_cmd = "(already .sparkbc)"

    if src.suffix == ".sparkbc":
        shutil.copy2(src, sparkbc)
    elif src.suffix == ".spark":
        boot = find_bootstrap(root)
        if boot is None:
            raise FileNotFoundError(
                "spark-bootstrap missing; "
                "run `make spark-bootstrap`"
            )
        spark_copy = dest / "source.spark"
        shutil.copy2(src, spark_copy)
        compile_cmd = "%s --compile %s -o %s" % (
            boot,
            spark_copy,
            sparkbc,
        )
        proc = subprocess.run(
            [
                str(boot),
                "--compile",
                str(spark_copy),
                "-o",
                str(sparkbc),
            ],
            cwd=str(root),
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode != 0 or not sparkbc.is_file():
            err = (proc.stderr or proc.stdout or "").strip()
            raise RuntimeError(
                "compile failed (%d): %s"
                % (proc.returncode, err or "no output")
            )
        source_note = _rel(spark_copy, root)
    else:
        raise ValueError(
            "want .spark or .sparkbc, got %s" % src.suffix
        )

    bc = load_sparkbc(sparkbc)
    rows = _ops_rows(bc)
    dump_text = format_dump(
        bc,
        source=source_note,
        command="helpers/spark-analyze %s" % src.name,
        label="SPARK_BC dump (analyze loop)",
    )
    (dest / "dump.txt").write_text(dump_text, encoding="utf-8")
    (dest / "ops.json").write_text(
        json.dumps(
            {
                "kind": "sparkbc_ops",
                "note": (
                    "SPARK_BC instruction list — not ELF "
                    "functions / pseudo-C"
                ),
                "sha256": bc["sha256"],
                "ops": rows,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
    (dest / "REPORT.md").write_text(
        REPORT_STUB.format(
            name=name,
            ts=ts,
            source=source_note,
            sparkbc=_rel(sparkbc, root),
            sha256=bc["sha256"],
            size=bc["size"],
            nop=len(rows),
            ops_md=_ops_markdown(rows),
        ),
        encoding="utf-8",
    )
    (dest / "screenshot.placeholder.md").write_text(
        SCREENSHOT_NOTE,
        encoding="utf-8",
    )

    serve_path: str | None = None
    if serve:
        serve_dir = dest / "serve"
        emit_serve(
            str(sparkbc),
            str(serve_dir),
            source=source_note,
            command=compile_cmd,
        )
        serve_path = _rel(serve_dir, root)

    ask_path: str | None = None
    ask_status = "skipped"
    if ask:
        wpath = weights or (
            root / "models" / "spark-coder" / "weights.safetensors"
        )
        ask_file = dest / "ASK.md"
        if not wpath.is_file():
            ask_file.write_text(
                ASK_NO_WEIGHTS.format(weights=wpath),
                encoding="utf-8",
            )
            ask_status = "no_weights"
        else:
            try:
                preview = _ops_markdown(rows[:16])
                output = _run_ask(
                    weights=wpath, name=name, rows=rows
                )
                ask_file.write_text(
                    ASK_WITH_WEIGHTS.format(
                        weights=wpath,
                        name=name,
                        ts=ts,
                        ops_preview=preview,
                        output=output,
                    ),
                    encoding="utf-8",
                )
                ask_status = "spark_coder"
            except (
                OSError,
                ValueError,
                KeyError,
                RuntimeError,
                ImportError,
            ) as exc:
                ask_file.write_text(
                    ASK_NO_WEIGHTS.format(weights=wpath)
                    + "\n\n## Error\n\n`%s`\n" % exc,
                    encoding="utf-8",
                )
                ask_status = "error"
        ask_path = _rel(ask_file, root)

    meta: dict[str, Any] = {
        "ok": True,
        "tool": "spark-analyze",
        "name": name,
        "out_dir": _rel(dest, root),
        "source": source_note,
        "sparkbc": _rel(sparkbc, root),
        "sha256": bc["sha256"],
        "size": bc["size"],
        "ops": len(rows),
        "dump": "dump.txt",
        "dump_json": "dump.json",
        "dump_html": "dump.html",
        "ops_json": "ops.json",
        "report": "REPORT.md",
        "screenshot_placeholder": "screenshot.placeholder.md",
        "serve": serve_path,
        "ask": ask_path,
        "ask_status": ask_status,
        "uploads": False,
        "device": "cpu",
        "ts": ts,
    }
    (dest / "META.json").write_text(
        json.dumps(meta, indent=2) + "\n", encoding="utf-8"
    )
    return meta


def main(argv: list[str] | None = None) -> int:
    """CLI entry for spark-analyze."""
    ap = argparse.ArgumentParser(
        prog="spark-analyze",
        description=(
            "Local Spark analysis folder: compile→dump→report. "
            "No upload. Never 6000. No frontier-parity claim."
        ),
    )
    ap.add_argument("input", help="path to .spark or .sparkbc")
    ap.add_argument(
        "-o",
        "--out",
        help="analysis folder (default out/analyze/<name>/)",
    )
    ap.add_argument(
        "--serve",
        action="store_true",
        help="also emit tiny CPU SERVE dir under the folder",
    )
    ap.add_argument(
        "--ask",
        action="store_true",
        help="write ASK.md via owned spark-coder or honesty note",
    )
    ap.add_argument(
        "--weights",
        help="TinyCoder weights for --ask",
    )
    ap.add_argument(
        "--json",
        action="store_true",
        help="print META.json to stdout",
    )
    args = ap.parse_args(argv)
    try:
        meta = run_analyze(
            Path(args.input),
            out_dir=Path(args.out) if args.out else None,
            serve=args.serve,
            ask=args.ask,
            weights=Path(args.weights) if args.weights else None,
        )
    except (OSError, RuntimeError, ValueError) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        return 1
    if args.json:
        print(json.dumps(meta, indent=2))
    else:
        print("OK analysis folder: %s" % meta["out_dir"])
        print(
            "  sha256=%s ops=%d"
            % (meta["sha256"], meta["ops"])
        )
        print(
            "  dump=%s report=%s"
            % (meta["dump"], meta["report"])
        )
        if meta.get("serve"):
            print("  serve=%s" % meta["serve"])
        if meta.get("ask"):
            print(
                "  ask=%s (%s)"
                % (meta["ask"], meta["ask_status"])
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
