#!/usr/bin/env python3
"""Lint train/eval JSONL fixtures used by SPARK_BC STEP / SGD."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def lint_jsonl(path: Path) -> list[str]:
    """Return human-readable problems; empty list means OK."""
    errors: list[str] = []
    if not path.is_file():
        return ["missing file: %s" % path]
    raw = path.read_text(encoding="utf-8")
    if not raw.strip():
        return ["empty file: %s" % path]
    for i, line in enumerate(raw.splitlines(), 1):
        if not line.strip():
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as exc:
            errors.append("line %d: JSON %s" % (i, exc))
            continue
        if not isinstance(obj, dict):
            errors.append("line %d: want object" % i)
            continue
        has_pair = (
            ("user" in obj and "assistant" in obj)
            or ("prompt" in obj and "completion" in obj)
            or ("input" in obj and "target" in obj)
        )
        if not has_pair and "messages" in obj:
            msgs = obj.get("messages")
            if isinstance(msgs, list) and msgs:
                roles = {
                    m.get("role")
                    for m in msgs
                    if isinstance(m, dict)
                }
                has_pair = "user" in roles and "assistant" in roles
            else:
                has_pair = False
        if not has_pair:
            errors.append(
                "line %d: need messages[user/assistant] or "
                "user/assistant or prompt/completion or "
                "input/target" % i
            )
    return errors


def main(argv: list[str] | None = None) -> int:
    """CLI: lint one or more fixture JSONL paths."""
    p = argparse.ArgumentParser(prog="spark-kit-fixture-lint")
    p.add_argument("paths", nargs="+", help="JSONL fixture paths")
    args = p.parse_args(argv)
    failed = 0
    for raw in args.paths:
        path = Path(raw)
        errs = lint_jsonl(path)
        if errs:
            failed += 1
            print("FAIL %s" % path)
            for e in errs:
                print("  %s" % e)
        else:
            print("OK %s" % path)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
