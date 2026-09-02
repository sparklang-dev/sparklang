#!/usr/bin/env python3
"""Aggregate corpus ledger → stdout JSON + optional markdown report path."""

from __future__ import annotations

import argparse
import json
import time
from collections import Counter
from pathlib import Path

SPARK_ROOT = Path(__file__).resolve().parents[2]
DATA = SPARK_ROOT / "data"
LEDGER = DATA / "corpus-ledger.jsonl"
CHECKPOINT = DATA / "corpus-checkpoint.json"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", type=Path, help="Write markdown report")
    ap.add_argument("--target", type=int, default=1_000_000)
    args = ap.parse_args()

    ok = 0
    err_rows = 0
    shas: set[str] = set()
    classify = Counter()
    errors = Counter()
    synthetic = 0
    t0 = time.time()

    if LEDGER.exists():
        with LEDGER.open(encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    err_rows += 1
                    errors["bad_json"] += 1
                    continue
                if row.get("synthetic"):
                    synthetic += 1
                    continue
                if row.get("ok"):
                    ok += 1
                    shas.add(row.get("sha256", ""))
                    classify[row.get("classify", "?")] += 1
                else:
                    err_rows += 1
                    errors["ok_false"] += 1

    cp = {}
    if CHECKPOINT.exists():
        cp = json.loads(CHECKPOINT.read_text())

    summary = {
        "ok_count": ok,
        "unique_sha256": len(shas),
        "error_rows": err_rows,
        "synthetic_skipped": synthetic,
        "classify_distribution": dict(classify.most_common()),
        "top_errors": dict(errors.most_common(10)),
        "checkpoint": {
            "ok_count": cp.get("ok_count"),
            "err_count": cp.get("err_count"),
            "phase": cp.get("phase"),
            "last_run": cp.get("last_run"),
        },
        "reached_1m": ok >= args.target,
        "target": args.target,
        "aggregate_ms": int((time.time() - t0) * 1000),
    }
    print(json.dumps(summary, indent=2, sort_keys=True))

    if args.report:
        reached = "YES" if summary["reached_1m"] else "NO"
        lines = [
            "# Spark corpus 1M — 2026-08-31",
            "",
            "## Verdict (honest)",
            f"- **1,000,000 reached:** {reached}",
            f"- **ok examples processed:** {ok}",
            f"- **unique sha256:** {len(shas)}",
            f"- **error/bad rows:** {err_rows}",
            f"- **synthetic counted toward 1M:** 0 "
            f"(synthetic_skipped={synthetic})",
            "",
            "## Classify distribution",
        ]
        for k, v in classify.most_common(30):
            lines.append(f"- `{k}`: {v}")
        lines += [
            "",
            "## Top errors",
        ]
        if errors:
            for k, v in errors.most_common(10):
                lines.append(f"- `{k}`: {v}")
        else:
            lines.append("- (none in ledger parse)")
        if cp.get("err_count"):
            lines.append(
                f"- checkpoint err_count (IO skips): {cp.get('err_count')}"
            )
            for k, v in (cp.get("errors") or {}).items():
                lines.append(f"- checkpoint `{k}`: {v}")
        last = cp.get("last_run") or {}
        lines += [
            "",
            "## Throughput (last run)",
            f"- processed_this_run: {last.get('processed_this_run')}",
            f"- elapsed_sec: {last.get('elapsed_sec')}",
            f"- rate_per_sec: {last.get('rate_per_sec')}",
            f"- eta_sec_to_target: {last.get('eta_sec_to_target')}",
            "",
            "## Paths",
            f"- ledger: `{LEDGER}`",
            f"- checkpoint: `{CHECKPOINT}`",
            "",
            "## Resume command",
            "```bash",
            "cd <spark-repo>",
            "python3 tools/corpus_million/run_corpus.py "
            "--checkpoint-every 1000",
            "# or background:",
            "nohup python3 tools/corpus_million/run_corpus.py "
            "--checkpoint-every 2000 "
            "> data/corpus-run.log 2>&1 &",
            "python3 tools/corpus_million/aggregate.py "
            "--report reports/"
            "spark-corpus-1m-20260831.md",
            "```",
            "",
            "## Method (no inventing)",
            "- Sources: real paths under `~/workspaces` "
            "(excludes `.git`, `node_modules`, venvs, `.env`, recordings, "
            "binaries with NUL).",
            "- Identity: sha256 of exact bytes reviewed.",
            "- Chunks (phase 2): real file slices `path#offset=N`, "
            "not fabricated content.",
            "- classify/review: dry-run heuristics aligned with Spark "
            "VM buckets; no live LLM; downloaded JS never executed.",
            "",
            f"Generated: aggregate_ms={summary['aggregate_ms']}",
            "",
        ]
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text("\n".join(lines) + "\n")
        print(f"wrote {args.report}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
