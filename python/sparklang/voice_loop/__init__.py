"""Voice agent loop language companions (CPU / dry-run).

pairs → train inputs · expect score · serve helper · ground ·
bench · schedule. No vendor/customer names. Synthetic fixtures only.
"""

from __future__ import annotations

from sparklang.voice_loop.bench import run_bench
from sparklang.voice_loop.expect_score import run_expect_score
from sparklang.voice_loop.ground_stmt import run_ground_fact
from sparklang.voice_loop.pairs import run_pairs
from sparklang.voice_loop.schedule import run_schedule_nightly
from sparklang.voice_loop.stmt import dispatch_stmt

__all__ = [
    "dispatch_stmt",
    "run_bench",
    "run_expect_score",
    "run_ground_fact",
    "run_pairs",
    "run_schedule_nightly",
]
