"""CLI: train / verify pinned byte-level BPE vocab."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from sparklang.tokenize.bpe import load_vocab, train_bpe, write_vocab


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def cmd_train(args: argparse.Namespace) -> int:
    """Train from a pinned corpus and write vocab + hash sidecar."""
    corpus_path = Path(args.corpus)
    corpus = corpus_path.read_bytes()
    artifact = train_bpe(corpus, num_merges=args.merges)
    digest = write_vocab(Path(args.out), artifact)
    print(f"vocab_sha256={digest}")
    print(f"corpus_sha256={artifact.corpus_sha256}")
    print(f"vocab_size={artifact.vocab_size}")
    print(f"num_merges={artifact.num_merges}")
    print(f"wrote={args.out}")
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    """Re-train and require the committed vocab hash to match."""
    corpus = Path(args.corpus).read_bytes()
    artifact = train_bpe(corpus, num_merges=args.merges)
    fresh = artifact.sha256()
    committed = load_vocab(Path(args.vocab))
    want = committed.sha256()
    if fresh != want:
        print(f"FAIL: vocab hash mismatch fresh={fresh} want={want}")
        return 1
    sidecar = Path(args.vocab).with_suffix(
        Path(args.vocab).suffix + ".sha256"
    )
    if sidecar.is_file():
        side = sidecar.read_text(encoding="ascii").strip()
        if side != want:
            print(f"FAIL: sidecar mismatch side={side} want={want}")
            return 1
    print(f"OK vocab_sha256={want}")
    return 0


def main(argv: list[str] | None = None) -> int:
    """Entry for ``python -m sparklang.tokenize``."""
    root = _repo_root()
    default_corpus = root / "examples/fixtures/tokenize/seed_corpus.txt"
    default_out = root / "docs/examples/spark-bpe-vocab.json"

    ap = argparse.ArgumentParser(
        prog="python -m sparklang.tokenize",
        description="Deterministic Spark byte-level BPE seed",
    )
    sub = ap.add_subparsers(dest="cmd", required=True)

    train_p = sub.add_parser("train", help="Train and write vocab JSON")
    train_p.add_argument(
        "--corpus",
        default=str(default_corpus),
        help="Pinned in-repo corpus (bytes)",
    )
    train_p.add_argument(
        "--merges",
        type=int,
        default=64,
        help="Number of BPE merges (default 64)",
    )
    train_p.add_argument(
        "--out",
        default=str(default_out),
        help="Output vocab JSON path",
    )
    train_p.set_defaults(func=cmd_train)

    ver_p = sub.add_parser("verify", help="Re-train; match committed hash")
    ver_p.add_argument("--corpus", default=str(default_corpus))
    ver_p.add_argument("--merges", type=int, default=64)
    ver_p.add_argument("--vocab", default=str(default_out))
    ver_p.set_defaults(func=cmd_verify)

    ns = ap.parse_args(argv)
    return int(ns.func(ns))


if __name__ == "__main__":
    sys.exit(main())
