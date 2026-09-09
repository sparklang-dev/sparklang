"""Deterministic byte-level BPE trainer (no downloads, no HF).

Starts from the 256 byte alphabet. Each merge picks the most frequent
adjacent pair; ties break by lexicographically smaller (left, right)
token ids. Same corpus bytes + merge count → identical vocab + hash.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

FORMAT = "spark-bpe-v1"
BASE_VOCAB = 256


def sha256_hex(data: bytes) -> str:
    """Return lowercase hex SHA-256 of data."""
    return hashlib.sha256(data).hexdigest()


def _pair_counts(seq: list[int]) -> dict[tuple[int, int], int]:
    counts: dict[tuple[int, int], int] = {}
    for i in range(len(seq) - 1):
        pair = (seq[i], seq[i + 1])
        counts[pair] = counts.get(pair, 0) + 1
    return counts


def _best_pair(
    counts: dict[tuple[int, int], int],
) -> tuple[int, int] | None:
    if not counts:
        return None
    # Highest count; tie → lexicographically smaller pair.
    def rank(item: tuple[tuple[int, int], int]) -> tuple[int, int, int]:
        (left, right), count = item
        return (-count, left, right)

    return min(counts.items(), key=rank)[0]


def _merge_once(seq: list[int], pair: tuple[int, int], new_id: int) -> list[int]:
    left, right = pair
    out: list[int] = []
    i = 0
    n = len(seq)
    while i < n:
        if i + 1 < n and seq[i] == left and seq[i + 1] == right:
            out.append(new_id)
            i += 2
        else:
            out.append(seq[i])
            i += 1
    return out


def _token_bytes(token_id: int, merges: list[tuple[int, int]]) -> bytes:
    if token_id < BASE_VOCAB:
        return bytes([token_id])
    left, right = merges[token_id - BASE_VOCAB]
    return _token_bytes(left, merges) + _token_bytes(right, merges)


@dataclass(frozen=True)
class VocabArtifact:
    """Pinned byte-level BPE vocab (JSON-serializable)."""

    format: str
    byte_level: bool
    num_merges: int
    vocab_size: int
    corpus_sha256: str
    merges: list[tuple[int, int]]
    tokens_hex: dict[str, str]

    def to_dict(self) -> dict[str, Any]:
        """Stable JSON object (sorted keys on dump)."""
        return {
            "byte_level": self.byte_level,
            "corpus_sha256": self.corpus_sha256,
            "format": self.format,
            "merges": [[a, b] for a, b in self.merges],
            "num_merges": self.num_merges,
            "tokens_hex": self.tokens_hex,
            "vocab_size": self.vocab_size,
        }

    def canonical_json(self) -> bytes:
        """UTF-8 JSON with sorted keys and trailing newline."""
        body = json.dumps(
            self.to_dict(),
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=True,
        )
        return (body + "\n").encode("utf-8")

    def sha256(self) -> str:
        """SHA-256 of canonical JSON bytes."""
        return sha256_hex(self.canonical_json())


def train_bpe(
    corpus: bytes,
    num_merges: int = 64,
) -> VocabArtifact:
    """Train byte-level BPE; deterministic for fixed corpus + merges."""
    if num_merges < 0:
        raise ValueError("num_merges must be >= 0")
    if not corpus:
        raise ValueError("corpus must be non-empty")

    seq = list(corpus)
    merges: list[tuple[int, int]] = []
    next_id = BASE_VOCAB

    for _ in range(num_merges):
        counts = _pair_counts(seq)
        pair = _best_pair(counts)
        if pair is None:
            break
        merges.append(pair)
        seq = _merge_once(seq, pair, next_id)
        next_id += 1

    tokens_hex: dict[str, str] = {}
    for tid in range(BASE_VOCAB + len(merges)):
        tokens_hex[str(tid)] = _token_bytes(tid, merges).hex()

    return VocabArtifact(
        format=FORMAT,
        byte_level=True,
        num_merges=len(merges),
        vocab_size=BASE_VOCAB + len(merges),
        corpus_sha256=sha256_hex(corpus),
        merges=merges,
        tokens_hex=tokens_hex,
    )


def apply_merges(data: bytes, merges: list[tuple[int, int]]) -> list[int]:
    """Encode bytes with a trained merge list (left-to-right)."""
    seq = list(data)
    for i, pair in enumerate(merges):
        seq = _merge_once(seq, pair, BASE_VOCAB + i)
    return seq


def write_vocab(path: Path, artifact: VocabArtifact) -> str:
    """Write canonical JSON + ``.sha256`` sidecar; return vocab hash."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    raw = artifact.canonical_json()
    digest = sha256_hex(raw)
    path.write_bytes(raw)
    sidecar = path.with_suffix(path.suffix + ".sha256")
    sidecar.write_text(digest + "\n", encoding="ascii")
    return digest


def load_vocab(path: Path) -> VocabArtifact:
    """Load a spark-bpe-v1 vocab JSON file."""
    path = Path(path)
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("format") != FORMAT:
        raise ValueError(f"unsupported format: {data.get('format')!r}")
    merges = [(int(a), int(b)) for a, b in data["merges"]]
    return VocabArtifact(
        format=FORMAT,
        byte_level=bool(data["byte_level"]),
        num_merges=int(data["num_merges"]),
        vocab_size=int(data["vocab_size"]),
        corpus_sha256=str(data["corpus_sha256"]),
        merges=merges,
        tokens_hex={str(k): str(v) for k, v in data["tokens_hex"].items()},
    )
