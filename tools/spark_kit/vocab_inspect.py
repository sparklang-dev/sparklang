#!/usr/bin/env python3
"""Inspect a spark-bpe-v1 vocab JSON artifact."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT / "python") not in sys.path:
    sys.path.insert(0, str(ROOT / "python"))

from sparklang.tokenize.bpe import load_vocab


def inspect_vocab(path: Path) -> str:
    """Human summary of a committed BPE vocab."""
    art = load_vocab(path)
    sample = []
    for tid in (0, 32, 97, 256, art.vocab_size - 1):
        if tid < 0 or tid >= art.vocab_size:
            continue
        hx = art.tokens_hex.get(str(tid), "")
        sample.append("  id=%d hex=%s" % (tid, hx[:32]))
    lines = [
        "# SparkLang vocab inspect",
        "path=%s" % path,
        "format=%s" % art.format,
        "vocab_size=%d" % art.vocab_size,
        "num_merges=%d" % art.num_merges,
        "byte_level=%s" % art.byte_level,
        "corpus_sha256=%s" % art.corpus_sha256,
        "artifact_sha256=%s" % art.sha256(),
        "sample_tokens:",
        *sample,
        "never=rtx-pro-6000",
    ]
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    """CLI: inspect one vocab JSON."""
    p = argparse.ArgumentParser(prog="spark-kit-vocab-inspect")
    p.add_argument(
        "vocab",
        type=Path,
        nargs="?",
        default=ROOT / "docs/examples/spark-bpe-vocab.json",
    )
    p.add_argument("-o", "--out", type=Path)
    args = p.parse_args(argv)
    text = inspect_vocab(args.vocab)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
        print("wrote %s" % args.out)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
