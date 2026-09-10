"""Parse and dispatch voice-loop language statements."""

from __future__ import annotations

import json
import re
import sys
from typing import Any

from sparklang.voice_loop.bench import parse_bench_stmt, run_bench
from sparklang.voice_loop.expect_score import (
    parse_expect_score_stmt,
    run_expect_score,
)
from sparklang.voice_loop.ground_stmt import (
    parse_ground_stmt,
    run_ground_fact,
)
from sparklang.voice_loop.pairs import parse_pairs_stmt, run_pairs
from sparklang.voice_loop.schedule import (
    parse_schedule_stmt,
    run_schedule_nightly,
)


def _print(payload: dict[str, Any]) -> None:
    """Emit JSON payload on one line then pretty bind hint."""
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")


_SERVE_RE = re.compile(
    r'model\s+serve\s+helper\s+"([^"]+)"\s+'
    r'as\s+"([^"]+)"\s+'
    r"port\s+(\d+)\s+"
    r'mode\s+"(shadow|live)"',
    re.I,
)


def parse_serve_stmt(stmt: str) -> dict[str, Any]:
    """Parse ``model serve helper "…" as "…" port N mode "…"``."""
    m = _SERVE_RE.search(stmt.strip())
    if not m:
        raise ValueError(
            'model serve helper needs: "path" as "name" '
            'port N mode "shadow"|"live"'
        )
    return {
        "helper": m.group(1),
        "name": m.group(2),
        "port": int(m.group(3)),
        "mode": m.group(4).lower(),
    }


def run_serve_dry(
    helper: str,
    name: str,
    port: int,
    mode: str,
    *,
    dry: bool = True,
) -> dict[str, Any]:
    """Dry-run serve helper — no bind; prints planned endpoint."""
    return {
        "op": "serve_helper",
        "mode": "dry-run" if dry else mode,
        "helper": helper,
        "name": name,
        "port": port,
        "serve_mode": mode,
        "endpoint": f"http://127.0.0.1:{port}/v1/rank",
        "note": (
            "dry-run plans serve; live uses "
            "./spark-serve-ref (CPU HTTP)"
        ),
    }


def dispatch_stmt(stmt: str, *, dry: bool = True) -> dict[str, Any]:
    """Route one language line to the matching CPU/dry handler."""
    s = stmt.strip()
    low = s.lower()

    if re.match(r"^(model\s+)?pairs\b", low):
        p = parse_pairs_stmt(s)
        out = f"out/voice_loop/pairs-{p.get('bind') or 'ds'}.json"
        return run_pairs(
            p["source"],
            p["schema"],
            class_eq=p.get("class_eq"),
            min_gap=p.get("min_gap"),
            out_path=out,
            dry=dry,
        )

    if low.startswith("expect score"):
        p = parse_expect_score_stmt(s)
        payload = run_expect_score(
            p["fixture_glob"],
            p["helper"],
            p["baseline"],
            dry=dry,
        )
        if not payload.get("pass"):
            raise SystemExit(
                "error: expect score failed "
                f"(helper_mean={payload.get('helper_mean')} "
                f"< baseline_mean={payload.get('baseline_mean')})"
            )
        return payload

    if low.startswith("ground "):
        p = parse_ground_stmt(s)
        return run_ground_fact(
            p["key"],
            p["facts_path"],
            else_mode=p["else_mode"],
            dry=dry,
        )

    if low.startswith("bench "):
        p = parse_bench_stmt(s)
        out = f"out/voice_loop/bench-{p['bind']}.json"
        return run_bench(
            p["fixtures_glob"],
            p["agent_a"],
            p["agent_b"],
            p["classes"],
            out_path=out,
            dry=dry,
        )

    if low.startswith("schedule "):
        p = parse_schedule_stmt(s)
        return run_schedule_nightly(
            p["program"] or "",
            pairs_source=p.get("pairs_source"),
            helper_out=p.get("helper_out") or "out/pref-001",
            dry=dry,
        )

    if re.search(r"\bserve\s+helper\b", low):
        p = parse_serve_stmt(s)
        return run_serve_dry(
            p["helper"],
            p["name"],
            p["port"],
            p["mode"],
            dry=dry,
        )

    raise ValueError(f"unrecognized voice-loop statement: {s[:80]}")


def main(argv: list[str] | None = None) -> int:
    """CLI: --dry|--live --stmt-file PATH | --stmt TEXT."""
    import argparse

    ap = argparse.ArgumentParser(prog="spark-voice-loop")
    ap.add_argument("--dry", action="store_true", default=True)
    ap.add_argument("--live", action="store_true")
    ap.add_argument("--stmt-file")
    ap.add_argument("--stmt")
    args = ap.parse_args(argv)
    dry = not args.live
    if args.stmt_file:
        text = open(args.stmt_file, encoding="utf-8").read()
    elif args.stmt:
        text = args.stmt
    else:
        ap.error("need --stmt-file or --stmt")
        return 2
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            payload = dispatch_stmt(line, dry=dry)
        except SystemExit as exc:
            sys.stderr.write(str(exc) + "\n")
            return 1
        except (OSError, ValueError, KeyError) as exc:
            sys.stderr.write(f"error: {exc}\n")
            return 1
        _print(payload)
        # ground else abstain is a successful refuse (exit 0)
        if payload.get("abstain") and payload.get("op") != "ground":
            return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
