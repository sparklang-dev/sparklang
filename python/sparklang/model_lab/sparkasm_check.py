"""Minimal shape check for Spark tensor-assembly (.sparkasm) source.

Parses .dim / .param / GQA invariants. Does **not** execute tensors,
JIT, or train. Exit 0 on ok; 1 on shape errors.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

_DIM_RE = re.compile(
    r"^\.dim\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(\d+)\b"
)
_DIM_SYM_RE = re.compile(
    r"^\.dim\s+([A-Za-z_][A-Za-z0-9_]*(?:\s*,\s*[A-Za-z_][A-Za-z0-9_]*)*)\s*$"
)
_PARAM_RE = re.compile(
    r"^\.param\s+([A-Za-z_][A-Za-z0-9_]*)\s*\[([^\]]+)\]\s+(\S+)"
)
_MODEL_RE = re.compile(r"^model\s+(\S+)")


def _strip_comment(line: str) -> str:
    """Drop ; comments outside the line's trailing note."""
    if ";" in line:
        return line.split(";", 1)[0].rstrip()
    return line.rstrip()


def parse_sparkasm(text: str) -> dict:
    """Parse dims, params, and model name from .sparkasm source."""
    dims: dict[str, int] = {}
    symbolic: list[str] = []
    params: dict[str, tuple[list[str], str]] = {}
    model = ""
    for raw in text.splitlines():
        line = _strip_comment(raw).strip()
        if not line or line.startswith("#"):
            continue
        m = _MODEL_RE.match(line)
        if m:
            model = m.group(1)
            continue
        m = _DIM_RE.match(line)
        if m:
            dims[m.group(1)] = int(m.group(2))
            continue
        m = _DIM_SYM_RE.match(line)
        if m:
            for name in re.split(r"\s*,\s*", m.group(1)):
                if name:
                    symbolic.append(name)
            continue
        m = _PARAM_RE.match(line)
        if m:
            shape = [p.strip() for p in m.group(2).split(",")]
            params[m.group(1)] = (shape, m.group(3))
    return {
        "model": model,
        "dims": dims,
        "symbolic": symbolic,
        "params": params,
    }


def _resolve(token: str, dims: dict[str, int]) -> int | None:
    """Resolve a shape token to an int, or None if symbolic/unknown."""
    token = token.strip()
    if token.isdigit():
        return int(token)
    if token in dims:
        return dims[token]
    return None


def check_control(ast: dict) -> list[str]:
    """Return human-readable errors (empty = ok)."""
    errors: list[str] = []
    dims = ast["dims"]
    params = ast["params"]

    required = ("V", "D", "L", "H", "KV", "HD", "Q", "K", "F")
    for name in required:
        if name not in dims:
            errors.append("missing .dim %s" % name)

    if errors:
        return errors

    d, h, kv, hd = dims["D"], dims["H"], dims["KV"], dims["HD"]
    q, k = dims["Q"], dims["K"]

    if h % kv != 0:
        errors.append("GQA: H (%d) must be divisible by KV (%d)" % (h, kv))
    if d != h * hd:
        errors.append(
            "D (%d) must equal H*HD (%d*%d=%d)" % (d, h, hd, h * hd)
        )
    if q != h * hd:
        errors.append(
            "Q (%d) must equal H*HD (%d*%d=%d)" % (q, h, hd, h * hd)
        )
    if k != kv * hd:
        errors.append(
            "K (%d) must equal KV*HD (%d*%d=%d)" % (k, kv, hd, kv * hd)
        )
    if dims["F"] != d * 4:
        errors.append(
            "F (%d) expected D*4 (%d) for control MLP" % (dims["F"], d * 4)
        )

    expect = {
        "embed": ["V", "D"],
        "w_q": ["L", "D", "Q"],
        "w_k": ["L", "D", "K"],
        "w_v": ["L", "D", "K"],
        "w_o": ["L", "Q", "D"],
        "w_gate": ["L", "D", "F"],
        "w_up": ["L", "D", "F"],
        "w_down": ["L", "F", "D"],
        "g_attn": ["L", "D"],
        "g_mlp": ["L", "D"],
        "g_out": ["D"],
        "head": ["D", "V"],
    }
    for name, want in expect.items():
        if name not in params:
            errors.append("missing .param %s" % name)
            continue
        got, _dtype = params[name]
        if got != want:
            errors.append(
                ".param %s shape %s != expected %s" % (name, got, want)
            )
        for tok in got:
            if _resolve(tok, dims) is None and tok not in ast["symbolic"]:
                errors.append(
                    ".param %s: unknown dim token %r" % (name, tok)
                )

    if not ast["model"]:
        errors.append("missing model <name>")

    return errors


def check_file(path: Path) -> list[str]:
    """Parse and shape-check one .sparkasm file."""
    text = path.read_text(encoding="utf-8")
    return check_control(parse_sparkasm(text))


def main(argv: list[str] | None = None) -> int:
    """CLI: shape-check one or more .sparkasm sources."""
    p = argparse.ArgumentParser(
        description="Shape-check Spark tensor-assembly source (.sparkasm)",
    )
    p.add_argument(
        "paths",
        nargs="*",
        type=Path,
        default=[Path("examples/models/control.sparkasm")],
    )
    args = p.parse_args(argv)
    any_err = False
    for path in args.paths:
        if not path.is_file():
            print("missing: %s" % path, file=sys.stderr)
            any_err = True
            continue
        errs = check_file(path)
        if errs:
            any_err = True
            print("FAIL %s" % path, file=sys.stderr)
            for e in errs:
                print("  - %s" % e, file=sys.stderr)
        else:
            ast = parse_sparkasm(path.read_text(encoding="utf-8"))
            print(
                "ok %s model=%s dims=%s n_param=%d (shape check only; "
                "no tensor VM)"
                % (
                    path,
                    ast["model"],
                    ",".join(
                        "%s=%d" % (k, ast["dims"][k])
                        for k in sorted(ast["dims"])
                    ),
                    len(ast["params"]),
                )
            )
    return 1 if any_err else 0


if __name__ == "__main__":
    raise SystemExit(main())
