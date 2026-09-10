"""schedule nightly — capture → pairs → train → expect → serve summary."""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from sparklang.voice_loop.expect_score import run_expect_score
from sparklang.voice_loop.pairs import run_pairs


def run_schedule_nightly(
    program: str,
    *,
    pairs_source: str | None = None,
    helper_out: str = "out/pref-001",
    baseline: str = "out/none",
    fixture_glob: str = "examples/fixtures/voice_loop/*.spark",
    summary_path: str | None = None,
    dry: bool = True,
) -> dict[str, Any]:
    """Run a dry/CPU nightly loop and write a JSON summary artifact."""
    steps: list[dict[str, Any]] = []
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # capture: record the program path (no telephony)
    capture = {
        "step": "capture",
        "program": program,
        "ok": Path(program).is_file(),
        "note": "program path recorded — no live dial",
    }
    steps.append(capture)

    pairs_src = pairs_source or (
        "examples/fixtures/voice_loop/turns.jsonl"
    )
    pairs_out = "out/voice_loop/pairs-nightly.json"
    try:
        pairs_payload = run_pairs(
            pairs_src,
            out_path=pairs_out,
            dry=dry,
        )
        steps.append(
            {
                "step": "pairs",
                "ok": True,
                "n_out": pairs_payload.get("n_out"),
                "artifact": pairs_payload.get("artifact"),
            }
        )
    except (OSError, ValueError) as exc:
        steps.append({"step": "pairs", "ok": False, "error": str(exc)})

    train_marker = Path(helper_out) / "ARTIFACT"
    train_ok = train_marker.is_file() or dry
    if dry and not train_marker.is_file():
        Path(helper_out).mkdir(parents=True, exist_ok=True)
        train_marker.write_text(
            "spark-schedule-dry helper\nmethod=spark_pref_pack\n",
            encoding="utf-8",
        )
    steps.append(
        {
            "step": "train",
            "ok": train_ok,
            "helper": helper_out,
            "note": "dry writes ARTIFACT stub when missing",
        }
    )

    try:
        score_payload = run_expect_score(
            fixture_glob,
            helper_out,
            baseline,
            dry=dry,
        )
        steps.append(
            {
                "step": "expect",
                "ok": bool(score_payload.get("pass")),
                "helper_mean": score_payload.get("helper_mean"),
                "baseline_mean": score_payload.get("baseline_mean"),
            }
        )
    except (OSError, ValueError) as exc:
        steps.append({"step": "expect", "ok": False, "error": str(exc)})

    serve_log = Path("out/voice_loop/serve-shadow.jsonl")
    serve_log.parent.mkdir(parents=True, exist_ok=True)
    if dry:
        serve_log.write_text(
            json.dumps(
                {
                    "op": "serve",
                    "mode": "shadow",
                    "helper": helper_out,
                    "ts": now,
                }
            )
            + "\n",
            encoding="utf-8",
        )
    steps.append(
        {
            "step": "serve",
            "ok": True,
            "mode": "shadow",
            "log": str(serve_log),
        }
    )

    ok = all(bool(s.get("ok")) for s in steps)
    payload: dict[str, Any] = {
        "op": "schedule",
        "kind": "nightly",
        "mode": "dry-run" if dry else "cpu",
        "program": program,
        "ts": now,
        "ok": ok,
        "steps": steps,
        "note": "nightly loop summary — CPU/dry only",
    }
    dest = Path(
        summary_path
        or "out/voice_loop/nightly-summary.json"
    )
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(
        json.dumps(payload, indent=2) + "\n",
        encoding="utf-8",
    )
    payload["artifact"] = str(dest)
    return payload


_SCHED_RE = re.compile(
    r'schedule\s+nightly\s+"([^"]+)"'
    r'(?:\s+pairs\s+"([^"]+)")?'
    r'(?:\s+helper\s+"([^"]+)")?'
    r'(?:\s+->\s*([A-Za-z_][A-Za-z0-9_]*))?',
    re.I,
)


def parse_schedule_stmt(stmt: str) -> dict[str, str | None]:
    """Parse ``schedule nightly "prog.spark" …``."""
    m = _SCHED_RE.search(stmt.strip())
    if not m:
        raise ValueError(
            'schedule needs: nightly "program.spark" '
            '[pairs "…"] [helper "…"]'
        )
    return {
        "program": m.group(1),
        "pairs_source": m.group(2),
        "helper_out": m.group(3) or "out/pref-001",
        "bind": m.group(4),
    }
