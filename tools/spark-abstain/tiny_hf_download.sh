#!/usr/bin/env bash
# Optional tiny HF causal-LM download for abstain smoke (owner machines).
#
# Default OFF. Never runs in CI. Requires explicit:
#   SPARK_ABSTAIN_ALLOW_TINY_DOWNLOAD=1
#
# Downloads a small public GPT-2 into a local cache dir (not the
# mega hub dump). Prints SPARK_ABSTAIN_MODEL path for export/train.
set -euo pipefail
cd "$(dirname "$0")/../.."

if [[ "${SPARK_ABSTAIN_ALLOW_TINY_DOWNLOAD:-}" != "1" ]]; then
  cat >&2 <<'EOF'
tiny_hf_download: refused (default OFF).
Set SPARK_ABSTAIN_ALLOW_TINY_DOWNLOAD=1 to download a tiny
causal LM for local abstain smoke. CI must leave this unset.
EOF
  exit 2
fi

MODEL_ID="${SPARK_ABSTAIN_TINY_MODEL:-sshleifer/tiny-gpt2}"
OUT_DIR="${SPARK_ABSTAIN_TINY_DIR:-$HOME/.cache/sparklang/tiny-hf}"
mkdir -p "$OUT_DIR"
TARGET="$OUT_DIR/${MODEL_ID//\//__}"

case "$(basename "$MODEL_ID" | tr '[:upper:]' '[:lower:]')" in
  auto|code|fast|best|code-bulk|code-hard|code-max|voice)
    echo "tiny_hf_download: refuse gateway alias $MODEL_ID" >&2
    exit 2
    ;;
esac

if [[ -f "$TARGET/config.json" ]]; then
  echo "tiny_hf_download: already present: $TARGET"
  echo "export SPARK_ABSTAIN_MODEL=$TARGET"
  echo "export SPARK_ABSTAIN_HF=1"
  exit 0
fi

python3 - <<PY
from pathlib import Path
mid = "$MODEL_ID"
out = Path("$TARGET")
out.mkdir(parents=True, exist_ok=True)
from transformers import AutoModelForCausalLM, AutoTokenizer
tok = AutoTokenizer.from_pretrained(mid)
model = AutoModelForCausalLM.from_pretrained(mid)
tok.save_pretrained(out)
model.save_pretrained(out)
print(f"saved {mid} -> {out}")
PY

echo "export SPARK_ABSTAIN_MODEL=$TARGET"
echo "export SPARK_ABSTAIN_HF=1"
echo "tiny_hf_download OK — next: make smoke-abstain-hf"
