#!/usr/bin/env python3
"""Determinism gate for Spark byte-level BPE seed vocab."""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PY = ROOT / "python"
if str(PY) not in sys.path:
    sys.path.insert(0, str(PY))

from sparklang.tokenize.bpe import (  # noqa: E402
    apply_merges,
    load_vocab,
    train_bpe,
    write_vocab,
)

CORPUS = ROOT / "examples/fixtures/tokenize/seed_corpus.txt"
COMMITTED = ROOT / "docs/examples/spark-bpe-vocab.json"
MERGES = 64


def main() -> int:
    """Train twice; match committed vocab sha256."""
    corpus = CORPUS.read_bytes()
    if not corpus:
        print("FAIL: empty corpus")
        return 1

    a = train_bpe(corpus, num_merges=MERGES)
    b = train_bpe(corpus, num_merges=MERGES)
    if a.sha256() != b.sha256():
        print("FAIL: two trains differ")
        return 1
    if a.canonical_json() != b.canonical_json():
        print("FAIL: canonical JSON differs")
        return 1
    if a.num_merges != MERGES:
        print(f"FAIL: expected {MERGES} merges got {a.num_merges}")
        return 1
    if a.vocab_size != 256 + MERGES:
        print(f"FAIL: vocab_size={a.vocab_size}")
        return 1

    with tempfile.TemporaryDirectory(prefix="spark-bpe-") as tmp:
        out = Path(tmp) / "vocab.json"
        digest = write_vocab(out, a)
        if digest != a.sha256():
            print("FAIL: write digest mismatch")
            return 1
        loaded = load_vocab(out)
        if loaded.sha256() != digest:
            print("FAIL: reload hash mismatch")
            return 1

    if not COMMITTED.is_file():
        print(f"FAIL: missing committed vocab {COMMITTED}")
        return 1
    committed = load_vocab(COMMITTED)
    if committed.sha256() != a.sha256():
        print(
            "FAIL: committed hash drift "
            f"fresh={a.sha256()} committed={committed.sha256()}"
        )
        return 1
    side = COMMITTED.with_suffix(COMMITTED.suffix + ".sha256")
    if side.is_file():
        side_hex = side.read_text(encoding="ascii").strip()
        if side_hex != a.sha256():
            print(f"FAIL: sidecar {side_hex} != {a.sha256()}")
            return 1

    encoded = apply_merges(corpus, a.merges)
    if not encoded:
        print("FAIL: empty encode")
        return 1
    if max(encoded) >= a.vocab_size:
        print("FAIL: encode id out of range")
        return 1

    print(f"OK vocab_sha256={a.sha256()}")
    print(f"OK corpus_sha256={a.corpus_sha256}")
    print(f"OK vocab_size={a.vocab_size} merges={a.num_merges}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
