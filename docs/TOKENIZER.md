# Byte-level BPE tokenizer seed (from nothing)

Spark trains a **deterministic byte-level BPE** vocab from a tiny
**in-repo** fixture — not FineWeb, not HuggingFace downloads.

| Piece | Path |
|-------|------|
| Trainer | `python/sparklang/tokenize/` |
| Pinned corpus | `examples/fixtures/tokenize/seed_corpus.txt` (LF ASCII) |
| Vocab artifact | `docs/examples/spark-bpe-vocab.json` |
| Hash sidecar | `docs/examples/spark-bpe-vocab.json.sha256` |
| Determinism gate | `tools/spark-bpe-seed/test_bpe.py` / `make test-bpe-seed` |

Format `spark-bpe-v1`: 256 byte base + N merges (default **64** →
vocab size **320**). Tie-break on equal pair counts is
lexicographically smaller `(left, right)` token id.

Packing this vocab into a SPARK_BC string/const pool is **optional
later** — the minimum ship is the reproducible JSON + sha256 under
`docs/examples/`.

## Reproduce

```bash
# Train (writes JSON + .sha256 sidecar)
PYTHONPATH=python python3 -m sparklang.tokenize train \
 --corpus examples/fixtures/tokenize/seed_corpus.txt \
 --merges 64 \
 --out docs/examples/spark-bpe-vocab.json

# Verify committed hash matches a fresh train
PYTHONPATH=python python3 -m sparklang.tokenize verify

# Determinism gate (trains twice + checks committed)
make test-bpe-seed
```

Pinned hashes (LF corpus; do not change without re-emitting):

```
corpus_sha256=63b47d211ddfcecf241fff0976294216c233448a5ef6ef67fe6668b733d32fdf
vocab_sha256=c20f899bbd552b2773447838be31827952d8494c110613c9ade1cb8a07c21226
```

## Never

- Download FineWeb / large web dumps for this seed
- Rely on platform CRLF (corpus is LF-only; `.gitattributes` pins it)
- Claim this tiny BPE beats a production LLM tokenizer
