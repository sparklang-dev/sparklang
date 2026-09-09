#!/usr/bin/env bash
# Stage K-lane helpers + shadows + spark_kit into dist/spark-sdk/.
# Additive overlay for I-lane out/sdk-pack when that stage exists.
# Never 6000. Does not claim beat Claude.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(
  if [[ -n "${SPARK_SDK_VERSION:-}" ]]; then
    echo "$SPARK_SDK_VERSION"
  elif [[ -f CHANGELOG.md ]]; then
    sed -n 's/^## \([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' \
      CHANGELOG.md | head -1
  else
    echo "0.6.37"
  fi
)"
NAME="sparklang-sdk-${VERSION}"
DEST="$ROOT/dist/spark-sdk/$NAME"
OUT_DIR="$ROOT/dist/spark-sdk"
MANIFEST="$OUT_DIR/MANIFEST-helpers-k.json"

echo "==> Staging helpers/shadows/kit into $DEST"
rm -rf "$DEST"
mkdir -p "$DEST"/{helpers,shadows,tools/spark_kit,tools/spark_shadow,bin,docs}

cp -a helpers/. "$DEST/helpers/"
chmod +x "$DEST"/helpers/spark-*
cp -a shadows/. "$DEST/shadows/"
cp -a tools/spark_kit "$DEST/tools/"
cp -a tools/spark_shadow "$DEST/tools/"
# Dump tool used by spark-bc-pp / spark-run / spark-analyze
mkdir -p "$DEST/tools/spark-bc-dump" "$DEST/tools/spark_analyze"
cp -a tools/spark-bc-dump/dump.py "$DEST/tools/spark-bc-dump/"
cp -a tools/spark_analyze/*.py "$DEST/tools/spark_analyze/"
# Thin bin wrappers for pack layout
cat >"$DEST/bin/spark-run" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$ROOT/helpers/spark-run" "$@"
EOF
cat >"$DEST/bin/spark-analyze" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PYTHONPATH="${ROOT}/tools:${ROOT}/python:${PYTHONPATH:-}"
exec bash "$ROOT/helpers/spark-analyze" "$@"
EOF
cat >"$DEST/bin/spark-shadow" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PYTHONPATH="${ROOT}/tools:${ROOT}/python:${ROOT}/runtime/python:${PYTHONPATH:-}"
export SPARK_ROOT="$ROOT"
exec bash "$ROOT/helpers/spark-shadow" "$@"
EOF
chmod +x "$DEST/bin/spark-run" "$DEST/bin/spark-analyze" \
  "$DEST/bin/spark-shadow"

if [[ -f docs/TOOLS_HELPERS.md ]]; then
  cp -a docs/TOOLS_HELPERS.md "$DEST/docs/"
fi
if [[ -f docs/METHODS_OPENBIN.md ]]; then
  cp -a docs/METHODS_OPENBIN.md "$DEST/docs/"
fi

cat >"$DEST/README-helpers-k.txt" <<EOF
SparkLang helpers / shadows / kit (K-lane) — ${VERSION}
=====================================================

  helpers/     spark-run, spark-analyze, spark-train-proof,
               spark-check-env, spark-bc-pp, spark-bc-diff, spark-shadow
  shadows/     shadow-build docs (build/shadow/)
  tools/spark_kit/      hexdump, opcode sheet, fixture lint, vocab
  tools/spark_shadow/   python module behind spark-shadow
  tools/spark_analyze/  project-loop analyze (local folders)

  make helpers / make tools-test / make test-spark-analyze
  in the full repo.

CPU only. Never RTX PRO 6000. Does not claim beat Claude.
EOF

# Overlay into I-lane stage if present
I_STAGE="$(find "$ROOT/out/sdk-pack/stage" -maxdepth 1 -type d \
  -name 'sparklang-sdk-*' 2>/dev/null | head -1 || true)"
if [[ -n "${I_STAGE:-}" && -d "$I_STAGE" ]]; then
  echo "==> Overlay helpers into I-lane stage $I_STAGE"
  mkdir -p "$I_STAGE/helpers" "$I_STAGE/shadows" \
    "$I_STAGE/tools" "$I_STAGE/bin"
  cp -a "$DEST/helpers/." "$I_STAGE/helpers/"
  cp -a "$DEST/shadows/." "$I_STAGE/shadows/"
  cp -a "$DEST/tools/spark_kit" "$I_STAGE/tools/"
  cp -a "$DEST/tools/spark_shadow" "$I_STAGE/tools/"
  cp -a "$DEST/bin/spark-run" "$I_STAGE/bin/"
  cp -a "$DEST/bin/spark-shadow" "$I_STAGE/bin/"
  chmod +x "$I_STAGE"/helpers/spark-* "$I_STAGE"/bin/spark-*
fi

python3 - <<'PY' "$DEST" "$VERSION" "$MANIFEST"
import hashlib, json, sys
from pathlib import Path

dest = Path(sys.argv[1])
version = sys.argv[2]
manifest = Path(sys.argv[3])
required = [
    "helpers/spark-run",
    "helpers/spark-train-proof",
    "helpers/spark-check-env",
    "helpers/spark-bc-pp",
    "helpers/spark-bc-diff",
    "helpers/spark-shadow",
    "shadows/README.md",
    "tools/spark_kit/opcode_sheet.py",
    "tools/spark_kit/hexdump_bc.py",
    "tools/spark_kit/fixture_lint.py",
    "tools/spark_kit/vocab_inspect.py",
    "tools/spark_kit/bc_diff.py",
    "tools/spark_shadow/__main__.py",
    "bin/spark-run",
    "bin/spark-shadow",
]
missing = [r for r in required if not (dest / r).exists()]
if missing:
    raise SystemExit("missing pack entries: %s" % missing)
files = {}
for p in sorted(dest.rglob("*")):
    if p.is_file():
        rel = str(p.relative_to(dest)).replace("\\", "/")
        files[rel] = hashlib.sha256(p.read_bytes()).hexdigest()
payload = {
    "name": dest.name,
    "version": version,
    "lane": "K",
    "kind": "helpers-shadows-tools",
    "required": required,
    "file_count": len(files),
    "never": "rtx-pro-6000",
    "beats_claude": False,
    "files": files,
}
manifest.parent.mkdir(parents=True, exist_ok=True)
manifest.write_text(
    json.dumps(payload, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
print("wrote %s (%d files)" % (manifest, len(files)))
for r in required:
    print("PACK_OK %s" % r)
PY

echo "==> K-lane pack ready under $DEST"
echo "MANIFEST $MANIFEST"
