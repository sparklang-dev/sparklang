#!/usr/bin/env python3
"""spark-schedule-ref — run nightly voice-loop summary (CPU/dry).

Usage:
  python3 tools/spark-schedule-ref/run_schedule.py \\
    --program examples/pairs_basic.spark --dry

Systemd template: sparklang-schedule@.service
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))

from sparklang.voice_loop.schedule import run_schedule_nightly  # noqa: E402


def main(argv: list[str] | None = None) -> int:
    """CLI for nightly schedule summary."""
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--program", required=True)
    ap.add_argument(
        "--pairs",
        default="examples/fixtures/voice_loop/turns.jsonl",
    )
    ap.add_argument("--helper", default="out/pref-001")
    ap.add_argument(
        "--summary",
        default="out/voice_loop/nightly-summary.json",
    )
    ap.add_argument("--dry", action="store_true", default=True)
    ap.add_argument("--live", action="store_true")
    args = ap.parse_args(argv)
    dry = not args.live
    payload = run_schedule_nightly(
        args.program,
        pairs_source=args.pairs,
        helper_out=args.helper,
        summary_path=args.summary,
        dry=dry,
    )
    print(json.dumps(payload, indent=2))
    return 0 if payload.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
