#!/usr/bin/env python3
"""spark-ground — forced grounding / anti-guess companion.

Usage:
  spark-ground ask --prompt "…" --expect "…" [--candidate "…"]
  spark-ground ask --prompt "…" --fixture PATH --candidate "…"
  spark-ground ask --prompt "…" --dump PATH --candidate "…"
  spark-ground verify --candidate "…" --expect "…"
  spark-ground verify --candidate '{"a":1}' --schema PATH
  spark-ground adapter-attach --base qwen --keep-existing PATH \\
      --add PATH [--out PATH]

Exit 0 when verified; exit 2 when abstain / refuse (CI-fail guess).
Does not beat Claude. Never 6000.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
_PY = ROOT / "python"
if _PY.is_dir() and str(_PY) not in sys.path:
    sys.path.insert(0, str(_PY))

from sparklang.ground.adapter import (  # noqa: E402
    AdapterSpec,
    attach_adapter_manifest,
)
from sparklang.ground.gate import (  # noqa: E402
    grounded_ask,
    verify_before_speak,
)


def _load_schema(path: str | None) -> dict | None:
    """Load JSON schema file if provided."""
    if not path:
        return None
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _emit(payload: dict, out: str | None) -> int:
    """Write JSON; exit 2 on abstain."""
    text = json.dumps(payload, indent=2, sort_keys=True)
    if out:
        Path(out).parent.mkdir(parents=True, exist_ok=True)
        Path(out).write_text(text + "\n", encoding="utf-8")
    else:
        sys.stdout.write(text + "\n")
    if payload.get("abstain"):
        return 2
    return 0


def main(argv: list[str] | None = None) -> int:
    """CLI entry for grounded ask / verify / adapter-attach."""
    p = argparse.ArgumentParser(prog="spark-ground")
    sub = p.add_subparsers(dest="cmd", required=True)

    ask = sub.add_parser("ask", help="grounded ask (refuse if guess)")
    ask.add_argument("--prompt", required=True)
    ask.add_argument("--candidate", default=None)
    ask.add_argument("--expect", default=None)
    ask.add_argument(
        "--expect-mode",
        choices=["equal", "contains"],
        default="equal",
    )
    ask.add_argument("--fixture", default=None)
    ask.add_argument("--dump", default=None)
    ask.add_argument("--schema", default=None)
    ask.add_argument(
        "--sot-ok",
        action="store_true",
        help="SoT already verified upstream",
    )
    ask.add_argument(
        "--allow-ungrounded",
        action="store_true",
        help="opt-out of require_ground (not for CI)",
    )
    ask.add_argument("--tool", default=None)
    ask.add_argument(
        "--tool-allow",
        action="append",
        default=[],
        help="repeatable tool allowlist entry",
    )
    ask.add_argument("--out", default=None)

    ver = sub.add_parser("verify", help="verify-before-speak only")
    ver.add_argument("--candidate", required=True)
    ver.add_argument("--expect", default=None)
    ver.add_argument(
        "--expect-mode",
        choices=["equal", "contains"],
        default="equal",
    )
    ver.add_argument("--fixture", default=None)
    ver.add_argument("--dump", default=None)
    ver.add_argument("--schema", default=None)
    ver.add_argument(
        "--allow-ungrounded",
        action="store_true",
    )
    ver.add_argument("--out", default=None)

    ad = sub.add_parser(
        "adapter-attach",
        help="write attach-only modify manifest",
    )
    ad.add_argument("--base", required=True)
    ad.add_argument("--keep-existing", required=True)
    ad.add_argument(
        "--add",
        action="append",
        required=True,
        help="adapter/head path (repeatable)",
    )
    ad.add_argument(
        "--kind",
        default="adapter",
        help="kind for --add entries",
    )
    ad.add_argument(
        "--base-kind",
        default="external",
        choices=["external", "spark"],
    )
    ad.add_argument(
        "--out",
        default="out/ground/adapter_manifest.json",
    )

    args = p.parse_args(argv)

    if args.cmd == "ask":
        payload = grounded_ask(
            args.prompt,
            candidate=args.candidate,
            expect=args.expect,
            expect_mode=args.expect_mode,
            fixture=args.fixture,
            dump=args.dump,
            schema=_load_schema(args.schema),
            sot_ok=bool(args.sot_ok),
            tool_allowlist=list(args.tool_allow or []),
            tool_requested=args.tool,
            require_ground=not bool(args.allow_ungrounded),
        )
        return _emit(payload, args.out)

    if args.cmd == "verify":
        payload = verify_before_speak(
            args.candidate,
            expect=args.expect,
            expect_mode=args.expect_mode,
            fixture=args.fixture,
            dump=args.dump,
            schema=_load_schema(args.schema),
            require_ground=not bool(args.allow_ungrounded),
        )
        return _emit(payload, args.out)

    if args.cmd == "adapter-attach":
        specs = [
            AdapterSpec(path=a, kind=args.kind) for a in args.add
        ]
        payload = attach_adapter_manifest(
            base=args.base,
            keep_existing=args.keep_existing,
            add=specs,
            out=args.out,
            base_kind=args.base_kind,
        )
        payload["abstain"] = False
        return _emit(payload, None)

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
