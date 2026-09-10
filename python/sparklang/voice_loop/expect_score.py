"""expect score replay gate — helper vs baseline fixture scores."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any


def _glob_fixtures(pattern: str) -> list[Path]:
    """Expand a relative glob; fail loud if empty."""
    root = Path(".")
    paths = sorted(root.glob(pattern))
    if not paths:
        # also try as literal path
        p = Path(pattern)
        if p.is_file():
            return [p]
        raise FileNotFoundError(f"expect score: no fixtures for {pattern!r}")
    return paths


def score_fixture(path: Path, helper: str | None) -> float:
    """Deterministic CPU score for a synthetic .spark fixture.

    Heuristic: count grounded / expect / pairs cues; bonus if helper
    directory exists and contains ARTIFACT or ranker.pt / replies.json.
    """
    text = path.read_text(encoding="utf-8")
    base = 0.35
    for cue, w in (
        ("expect ", 0.05),
        ("ground ", 0.08),
        ("pairs ", 0.06),
        ("abstain", 0.04),
        ("stall", 0.03),
        ("dead_air", 0.03),
        ("handoff", 0.03),
    ):
        if cue in text:
            base += w
    bonus = 0.0
    if helper:
        h = Path(helper)
        if h.is_dir():
            names = {p.name for p in h.iterdir()}
            if "ARTIFACT" in names:
                bonus += 0.12
            if "ranker.pt" in names or "router.pt" in names:
                bonus += 0.15
            if "replies.json" in names or "pref_pack.json" in names:
                bonus += 0.1
            if "playbooks.json" in names:
                bonus += 0.08
        elif h.is_file():
            bonus += 0.05
    # Clamp
    return round(min(1.0, base + bonus), 4)


def run_expect_score(
    fixture_glob: str,
    helper: str,
    baseline: str,
    *,
    dry: bool = True,
) -> dict[str, Any]:
    """Replay fixtures with helper and baseline; fail if not ≥."""
    fixtures = _glob_fixtures(fixture_glob)
    helper_scores: list[float] = []
    base_scores: list[float] = []
    detail: list[dict[str, Any]] = []
    for fx in fixtures:
        hs = score_fixture(fx, helper)
        bs = score_fixture(fx, baseline if baseline != "out/none" else None)
        # Explicit none baseline = zero pack
        if baseline in ("out/none", "none", ""):
            bs = score_fixture(fx, None)
        helper_scores.append(hs)
        base_scores.append(bs)
        detail.append(
            {
                "fixture": str(fx),
                "helper_score": hs,
                "baseline_score": bs,
                "delta": round(hs - bs, 4),
            }
        )
    h_mean = sum(helper_scores) / len(helper_scores)
    b_mean = sum(base_scores) / len(base_scores)
    ok = h_mean >= b_mean
    payload = {
        "op": "expect_score",
        "mode": "dry-run" if dry else "cpu",
        "fixture_glob": fixture_glob,
        "helper": helper,
        "baseline": baseline,
        "n": len(fixtures),
        "helper_mean": round(h_mean, 4),
        "baseline_mean": round(b_mean, 4),
        "pass": ok,
        "detail": detail,
        "note": "CPU replay heuristic — not a live judge model",
    }
    return payload


_REPLAY_RE = re.compile(
    r'expect\s+score\s+replay\s+"([^"]+)"\s+'
    r'with\s+helper\s+"([^"]+)"\s*>=\s*'
    r'baseline\s+"([^"]+)"',
    re.I,
)


def parse_expect_score_stmt(stmt: str) -> dict[str, str]:
    """Parse expect score replay statement."""
    m = _REPLAY_RE.search(stmt.strip())
    if not m:
        raise ValueError(
            "expect score needs: replay \"…\" with helper \"…\" "
            '>= baseline "…"'
        )
    return {
        "fixture_glob": m.group(1),
        "helper": m.group(2),
        "baseline": m.group(3),
    }


def http_replay(
    fixture: str,
    helper: str | None,
) -> dict[str, Any]:
    """Trainer contract POST /replay body handler (CPU)."""
    path = Path(fixture)
    if not path.is_file():
        raise FileNotFoundError(f"replay fixture missing: {fixture}")
    score = score_fixture(path, helper)
    return {
        "op": "replay",
        "fixture": fixture,
        "helper": helper,
        "score": score,
        "note": "CPU replay — Trainer contract",
    }
