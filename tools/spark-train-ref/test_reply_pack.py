#!/usr/bin/env python3
"""CPU proof for spark_reply_pack: SoT required, never fabricate."""
from __future__ import annotations

import sys
import tempfile
from pathlib import Path

_REF = Path(__file__).resolve().parent
if str(_REF) not in sys.path:
    sys.path.insert(0, str(_REF))

from reply_pack import (  # noqa: E402
    load_reply_rows,
    reply_or_idk,
    train_reply_pack,
)

ROOT = Path(__file__).resolve().parents[2]
GOOD = ROOT / "examples/fixtures/train/reply_pack.jsonl"
BAD = ROOT / "examples/fixtures/train/reply_pack_bad.jsonl"


def main() -> int:
    """Fail loud without SoT; train overlay with gate.no_fabricate."""
    try:
        load_reply_rows(BAD)
    except ValueError as exc:
        if "refuse fabricate" not in str(exc):
            print("FAIL: expected refuse fabricate", exc)
            return 1
    else:
        print("FAIL: bad dataset should fail loud")
        return 1

    with tempfile.TemporaryDirectory(prefix="spark-reply-") as tmp:
        result = train_reply_pack(
            str(GOOD),
            "text-only-base",
            tmp,
            "job-reply-001",
            steps=40,
        )
        meta = result["meta"]
        if not meta.get("no_fabricate"):
            print("FAIL: no_fabricate missing")
            return 1
        gate = Path(result["gate"]).read_text(encoding="utf-8")
        if '"no_fabricate": true' not in gate:
            print("FAIL: gate.json")
            return 1
        replies = Path(result["replies"]).read_text(encoding="utf-8")
        if "Hello. How can I help you today?" not in replies:
            print("FAIL: speak overlay missing")
            return 1
        if '"overlay_voice_on_text_base": true' not in replies:
            print("FAIL: overlay_voice_on_text_base")
            return 1
    if reply_or_idk("Who is the mayor of Springfield?") != "I don't know.":
        print("FAIL: reply_or_idk should IDK")
        return 1
    if reply_or_idk("hi") is not None:
        print("FAIL: greeting should route")
        return 1
    if reply_or_idk("what are your hours", sot_ok=True) is not None:
        print("FAIL: sot_ok should route")
        return 1
    print("PASS spark_reply_pack")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
