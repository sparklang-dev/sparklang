#!/usr/bin/env python3
"""Independent Deepgram roundtrip judge for TTS candidates.

Given (text, synthesized_wav) pairs — e.g. SparkLang's own TTS output —
transcribe each wav with Deepgram and report WER/CER against the
intended text. This is the honest grader for the TTS roundtrip gate:
the base build currently self-grades with its own STT; this judge is
the independent upgrade the training phase wires in.

Usable both as a CLI and as a library::

    from dg_roundtrip_judge import judge_pairs
    verdicts = judge_pairs(rows, transcribe_fn=my_transcriber)

Input jsonl rows: ``{id, text, wav}`` (wav = candidate synthesis).
Output rows add ``dg_transcript``, ``wer``, ``cer``, ``pass``.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dg_common import (  # noqa: E402
    DEFAULT_MODEL,
    CredentialUnavailable,
    best_error_rates,
    load_deepgram_key,
    read_jsonl,
    transcribe_wav,
    write_jsonl,
)
from dg_transcribe import resolve_wav  # noqa: E402

PASS_WER = 0.1


def judge_pairs(
    rows: list[dict],
    transcribe_fn,
    manifest_dir: Path | None = None,
) -> list[dict]:
    """Score (text, wav) rows with a caller-supplied transcriber.

    ``transcribe_fn(wav_path)`` must return a dict with a
    ``transcript`` key (dg_common.transcribe_wav qualifies). Rows are
    scored in a copy; input rows are not mutated.
    """
    verdicts: list[dict] = []
    for row in rows:
        verdict = dict(row)
        wav = Path(row["wav"])
        if not wav.is_absolute() and manifest_dir is not None:
            wav = manifest_dir / wav
        if not wav.is_file():
            verdict["judge_error"] = f"missing wav: {wav}"
            verdict["pass"] = False
            verdicts.append(verdict)
            continue
        try:
            result = transcribe_fn(wav)
        except Exception as exc:  # noqa: BLE001 — report, keep judging
            verdict["judge_error"] = (
                f"{exc.__class__.__name__}: transcription failed"
            )
            verdict["pass"] = False
            verdicts.append(verdict)
            continue
        transcript = result.get("transcript", "")
        verdict["dg_transcript"] = transcript
        verdict.update(best_error_rates(row["text"], transcript))
        verdict["pass"] = verdict["wer"] <= PASS_WER
        verdicts.append(verdict)
    return verdicts


def summarize(verdicts: list[dict]) -> dict:
    """Aggregate judge verdicts into a gate summary."""
    scored = [v for v in verdicts if "wer" in v]
    passed = sum(1 for v in scored if v["pass"])
    return {
        "total": len(verdicts),
        "scored": len(scored),
        "passed": passed,
        "pass_rate": round(passed / len(scored), 4) if scored else None,
        "wer_mean": (
            round(sum(v["wer"] for v in scored) / len(scored), 4)
            if scored
            else None
        ),
        "wer_max": max((v["wer"] for v in scored), default=None),
        "failed_ids": [v.get("id") for v in scored if not v["pass"]],
        "errored_ids": [v.get("id") for v in verdicts if "wer" not in v],
    }


def main() -> int:
    """CLI: judge a jsonl of (text, wav) pairs with Deepgram."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--pairs",
        type=Path,
        required=True,
        help="jsonl of {id, text, wav} candidate rows",
    )
    parser.add_argument("--out", type=Path, default=None)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument(
        "--dry",
        action="store_true",
        help="validate inputs only; no network, no writes",
    )
    args = parser.parse_args()

    rows = read_jsonl(args.pairs)
    planned = rows if args.limit is None else rows[: args.limit]
    missing = [
        str(resolve_wav(r, args.pairs))
        for r in planned
        if not resolve_wav(r, args.pairs).is_file()
    ]
    print(f"candidate pairs: {len(planned)}; missing wavs: {len(missing)}")
    if args.dry:
        for path in missing[:10]:
            print(f"  MISSING {path}")
        print("dry run: no network calls made, nothing written")
        return 0 if not missing else 1

    try:
        api_key = load_deepgram_key()
    except CredentialUnavailable as exc:
        print(str(exc), file=sys.stderr)
        return 3

    def deepgram_fn(wav_path: Path) -> dict:
        return transcribe_wav(wav_path, api_key, model=args.model)

    verdicts = judge_pairs(
        planned, deepgram_fn, manifest_dir=args.pairs.parent
    )
    summary = summarize(verdicts)
    summary["model"] = args.model
    summary["pass_wer_threshold"] = PASS_WER

    out_path = args.out or args.pairs.with_suffix(".judged.jsonl")
    write_jsonl(out_path, verdicts)
    print(json.dumps(summary, indent=2))
    print(f"wrote {out_path}")
    return 0 if not summary["errored_ids"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
