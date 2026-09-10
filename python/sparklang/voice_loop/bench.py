"""bench — two-agent per-class scoreboard (synthetic agents only)."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

DEFAULT_CLASSES = (
    "turn_taking,stall,dead_air,interrupt,"
    "filler,handoff,grounded"
)


def _agent_helper(name: str) -> str | None:
    """Map synthetic agent id to a local helper dir if present."""
    for c in (
        Path(f"out/bench/{name}"),
        Path(f"out/{name}"),
        Path(name),
        Path(f"examples/fixtures/voice_loop/agents/{name}"),
    ):
        if c.is_dir():
            return str(c)
    return None


def _helper_bonus(helper: str | None) -> float:
    """Small CPU bonus when a helper artifact dir exists."""
    if not helper:
        return 0.0
    h = Path(helper)
    if not h.is_dir():
        return 0.0
    names = {p.name for p in h.iterdir()}
    bonus = 0.1
    if "ARTIFACT" in names:
        bonus += 0.1
    if names & {"ranker.pt", "router.pt", "replies.json"}:
        bonus += 0.15
    return bonus


def _class_score(text: str, cls: str, helper: str | None) -> float:
    """Per-class CPU score from fixture cues + helper bonus."""
    cue = cls.replace("_", " ")
    hit = 1.0 if (cls in text or cue in text) else 0.35
    return round(min(1.0, 0.45 * hit + 0.25 + _helper_bonus(helper)), 4)


def run_bench(
    fixtures_glob: str,
    agent_a: str,
    agent_b: str,
    classes: str = DEFAULT_CLASSES,
    *,
    out_path: str | None = None,
    dry: bool = True,
) -> dict[str, Any]:
    """Score two synthetic agents across class labels."""
    root = Path(".")
    paths = sorted(root.glob(fixtures_glob))
    if not paths:
        p = Path(fixtures_glob)
        if p.is_file():
            paths = [p]
        else:
            raise FileNotFoundError(
                f"bench: no fixtures for {fixtures_glob!r}"
            )
    class_list = [c.strip() for c in classes.split(",") if c.strip()]
    ha = _agent_helper(agent_a)
    hb = _agent_helper(agent_b)
    board: dict[str, Any] = {}
    for cls in class_list:
        a_scores: list[float] = []
        b_scores: list[float] = []
        for fx in paths:
            text = fx.read_text(encoding="utf-8")
            a_scores.append(_class_score(text, cls, ha))
            b_scores.append(_class_score(text, cls, hb))
        a_mean = sum(a_scores) / len(a_scores)
        b_mean = sum(b_scores) / len(b_scores)
        board[cls] = {
            "agent_a": round(a_mean, 4),
            "agent_b": round(b_mean, 4),
            "gap": round(a_mean - b_mean, 4),
        }
    payload = {
        "op": "bench",
        "mode": "dry-run" if dry else "cpu",
        "fixtures": fixtures_glob,
        "agents": [agent_a, agent_b],
        "classes": class_list,
        "helpers": {"agent_a": ha, "agent_b": hb},
        "board": board,
        "n_fixtures": len(paths),
        "note": "synthetic two-agent scoreboard — CPU only",
    }
    if out_path:
        dest = Path(out_path)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(
            json.dumps(payload, indent=2) + "\n",
            encoding="utf-8",
        )
        payload["artifact"] = str(dest)
    return payload


_BENCH_RE = re.compile(
    r'bench\s+fixtures\s+"([^"]+)"\s+'
    r'against\s+"([^"]+)"\s+"([^"]+)"\s+'
    r'(?:classes\s+"([^"]+)"\s+)?'
    r"->\s*([A-Za-z_][A-Za-z0-9_]*)",
    re.I,
)


def parse_bench_stmt(stmt: str) -> dict[str, str]:
    """Parse bench fixtures … against … classes … -> board."""
    m = _BENCH_RE.search(stmt.strip())
    if not m:
        raise ValueError(
            'bench needs: fixtures "…" against "a" "b" '
            '[classes "…"] -> board'
        )
    return {
        "fixtures_glob": m.group(1),
        "agent_a": m.group(2),
        "agent_b": m.group(3),
        "classes": m.group(4) or DEFAULT_CLASSES,
        "bind": m.group(5),
    }
