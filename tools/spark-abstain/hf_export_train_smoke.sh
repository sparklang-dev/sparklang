#!/usr/bin/env bash
# Optional live HF export→train→ask smoke (env-gated).
#
# Requires:
#   SPARK_ABSTAIN_HF=1
#   SPARK_ABSTAIN_MODEL=/path/to/local-hf-dir   (explicit; no aliases)
#
# Never downloads models. Sets TRANSFORMERS_OFFLINE +
# SPARK_ABSTAIN_HF_LOCAL_ONLY. Skips (exit 0) when env unset or
# model path missing — CI stays green without GPU/network.
set -euo pipefail
cd "$(dirname "$0")/../.."

if [[ "${SPARK_ABSTAIN_HF:-}" != "1" ]]; then
  echo "hf_export_train_smoke: skip (SPARK_ABSTAIN_HF!=1)"
  exit 0
fi

MODEL="${SPARK_ABSTAIN_MODEL:-}"
if [[ -z "$MODEL" ]]; then
  echo "hf_export_train_smoke: skip (SPARK_ABSTAIN_MODEL unset)"
  exit 0
fi
if [[ ! -e "$MODEL" ]]; then
  echo "hf_export_train_smoke: skip (model path missing: $MODEL)"
  exit 0
fi
case "$(basename "$MODEL" | tr '[:upper:]' '[:lower:]')" in
  auto|code|fast|best|code-bulk|code-hard|code-max|voice)
    echo "hf_export_train_smoke: refuse gateway alias $MODEL" >&2
    exit 2
    ;;
esac

export TRANSFORMERS_OFFLINE=1
export SPARK_ABSTAIN_HF_LOCAL_ONLY=1
export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-}"

OUT_DIR="${SPARK_ABSTAIN_SMOKE_OUT:-out/heads-hf-smoke}"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

DS="${SPARK_ABSTAIN_SMOKE_DATASET:-examples/fixtures/abstain/corpus_seed.jsonl}"

echo "hf_export_train_smoke: export from $MODEL"
./spark-abstain --live export \
  --dataset "$DS" \
  --model "$MODEL" \
  --source hf \
  --out "$OUT_DIR/from-hf.jsonl" | tee "$OUT_DIR/export.json"
grep -q '"source":"hf"' "$OUT_DIR/export.json"
grep -q '"state":"succeeded"' "$OUT_DIR/export.json"

DIM=$(python3 -c "import json;print(json.load(open('$OUT_DIR/export.json'))['hidden_dim'])")
echo "hf_export_train_smoke: train hidden_dim=$DIM"
./spark-abstain --live train \
  --dataset "$OUT_DIR/from-hf.jsonl" \
  --out "$OUT_DIR/abstain.pt" \
  --hidden-dim "$DIM" | tee "$OUT_DIR/train.json"
grep -q '"state":"succeeded"' "$OUT_DIR/train.json"
grep -q "\"hidden_dim\":$DIM" "$OUT_DIR/train.json"

./spark-abstain --live attach \
  --model "$OUT_DIR" \
  --weights "$OUT_DIR/abstain.pt" \
  --out "$OUT_DIR/manifest.json" >/dev/null

echo "hf_export_train_smoke: ask (HF prefill + trained head)"
SPARK_ABSTAIN_HF=1 SPARK_ABSTAIN_HF_LOCAL_ONLY=1 \
./spark-abstain --live ask \
  --prompt "Who is the mayor of Springfield?" \
  --model "$MODEL" \
  --weights "$OUT_DIR/abstain.pt" \
  --manifest "$OUT_DIR/manifest.json" \
  --threshold 0.5 | tee "$OUT_DIR/ask.json"
grep -q '"mode":"live' "$OUT_DIR/ask.json" || \
  grep -q '"mode": "live' "$OUT_DIR/ask.json"
grep -q '"op":"head_ask"' "$OUT_DIR/ask.json" || \
  grep -q '"op": "head_ask"' "$OUT_DIR/ask.json"

echo "hf_export_train_smoke OK (quality=hf_exported_unverified — not production accuracy)"
