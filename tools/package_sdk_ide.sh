#!/usr/bin/env bash
# Build the SparkLang SDK + runtime + IDE + GUI download pack.
# Output: out/sdk-pack/sparklang-sdk-<ver>.tar.gz + MANIFEST.json
# Never 6000. Does not claim beat Claude.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(
  if [[ -n "${SPARK_SDK_VERSION:-}" ]]; then
    echo "$SPARK_SDK_VERSION"
  elif [[ -f CHANGELOG.md ]]; then
    # First ## X.Y.Z heading in CHANGELOG
    sed -n 's/^## \([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' \
      CHANGELOG.md | head -1
  else
    echo ""
  fi
)"
if [[ -z "$VERSION" ]]; then
  VERSION="$(
    ./spark-bootstrap --version 2>/dev/null | awk '{print $2}' \
      || echo "0.6.35"
  )"
fi
STAGE="$ROOT/out/sdk-pack/stage"
NAME="sparklang-sdk-${VERSION}"
DEST="$STAGE/$NAME"
OUT_DIR="$ROOT/out/sdk-pack"
TARBALL="$OUT_DIR/${NAME}.tar.gz"
MANIFEST="$OUT_DIR/MANIFEST.json"
WEB_DL="$ROOT/website/downloads"

echo "==> Ensuring spark-bootstrap"
make -q spark-bootstrap 2>/dev/null || make spark-bootstrap

echo "==> Staging $NAME"
rm -rf "$STAGE"
mkdir -p "$DEST"/{bin,runtime/python,runtime/scripts,runtime/docs/examples,runtime/tools,sdk/docs,sdk/examples,sdk/include,ide,gui}

# --- Runtime ---
cp -a spark-bootstrap "$DEST/bin/spark-bootstrap"
ln -sfn spark-bootstrap "$DEST/bin/sparkc"
if [[ -f scripts/spark-bc ]]; then
  cp -a scripts/spark-bc "$DEST/runtime/scripts/spark-bc"
  chmod +x "$DEST/runtime/scripts/spark-bc"
fi
cp -a python/sparklang "$DEST/runtime/python/sparklang"
# Published bytecode examples (CPU serve / inspect)
mkdir -p "$DEST/runtime/docs/examples"
cp -a docs/examples/*.sparkbc "$DEST/runtime/docs/examples/" 2>/dev/null || true
cp -a docs/examples/*.txt "$DEST/runtime/docs/examples/" 2>/dev/null || true
cp -a tools/spark-bc-dump "$DEST/runtime/tools/spark-bc-dump"
# Serve helpers (CPU only)
if [[ -f tools/spark-bc-dump/spark_serve.sh ]]; then
  cp -a tools/spark-bc-dump/spark_serve.sh \
    "$DEST/runtime/tools/spark-bc-dump/"
fi
if [[ -f spark-model-lab ]]; then
  cp -a spark-model-lab "$DEST/bin/spark-model-lab"
fi

# --- SDK ---
for doc in SPARK_BC.md SPARK_BUILDER.md LANGUAGE.md ADOPTION_BAR.md FACTORY.md DIAGRAMS.md; do
  if [[ -f "docs/$doc" ]]; then
    cp -a "docs/$doc" "$DEST/sdk/docs/"
  fi
done
cp -a LICENSE "$DEST/sdk/LICENSE"
cp -a README.md "$DEST/sdk/README.md"
# Headers
if [[ -f tools/spark_rt/spark_rt.h ]]; then
  cp -a tools/spark_rt/spark_rt.h "$DEST/sdk/include/"
fi
# Example sources
mkdir -p "$DEST/sdk/examples"
for f in examples/spark_builder.spark examples/spark_train_step.spark \
  examples/model_lab.spark selfhost/compile.spark; do
  if [[ -f "$f" ]]; then
    cp -a "$f" "$DEST/sdk/examples/"
  fi
done
# Python SDK surface (same package — documented as SDK)
cp -a python/sparklang "$DEST/sdk/python-sparklang"

# --- IDE ---
cp -a tools/spark-ide-extension "$DEST/ide/spark-ide-extension"
cp -a spark.code-workspace "$DEST/ide/spark.code-workspace"
cp -a tools/open-spark-ide.sh "$DEST/ide/open-spark-ide.sh"
chmod +x "$DEST/ide/open-spark-ide.sh"
# Wrapper that resolves pack-relative paths
cat >"$DEST/bin/spark-ide" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export SPARK_ROOT="$ROOT"
WS="$ROOT/ide/spark.code-workspace"
EXT="$ROOT/ide/spark-ide-extension"
CURSOR_BIN="${CURSOR_BIN:-/usr/share/cursor/cursor}"
if [[ ! -f "$WS" ]]; then
  echo "missing workspace: $WS" >&2
  exit 1
fi
if [[ -d "$EXT" ]] && command -v cursor >/dev/null 2>&1; then
  cursor --install-extension "$EXT" >/dev/null 2>&1 || true
elif [[ -d "$EXT" ]] && command -v code >/dev/null 2>&1; then
  code --install-extension "$EXT" >/dev/null 2>&1 || true
fi
if [[ -x "$CURSOR_BIN" ]]; then
  exec env SPARK_IDE=1 "$CURSOR_BIN" --new-window "$WS"
fi
if command -v cursor >/dev/null 2>&1; then
  exec env SPARK_IDE=1 cursor --new-window "$WS"
fi
if command -v code >/dev/null 2>&1; then
  exec env SPARK_IDE=1 code --new-window "$WS"
fi
echo "spark-ide: install Cursor or VS Code, or open $WS" >&2
exit 1
EOF
chmod +x "$DEST/bin/spark-ide"

# --- GUI compiler / decompiler ---
cp -a tools/spark_bc_gui "$DEST/gui/spark_bc_gui"
# Also expose under tools/ for PYTHONPATH parity with repo
mkdir -p "$DEST/tools"
cp -a tools/spark_bc_gui "$DEST/tools/spark_bc_gui"
cat >"$DEST/bin/spark-bc-gui" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PYTHONPATH="${ROOT}/tools:${ROOT}/runtime/python:${ROOT}/sdk/python-sparklang:${PYTHONPATH:-}"
cd "$ROOT"
# Prefer pack binary; fall back to PATH
if [[ ! -x "$ROOT/bin/spark-bootstrap" ]]; then
  echo "spark-bc-gui: missing bin/spark-bootstrap" >&2
  exit 1
fi
exec python3 -m spark_bc_gui "$@"
EOF
chmod +x "$DEST/bin/spark-bc-gui"

# --- Helpers + shadows + assorted tools (I-lane / K-ready) ---
mkdir -p "$DEST/helpers" "$DEST/shadows" "$DEST/tools"
cp -a tools/spark_helpers/. "$DEST/helpers/"
cp -a tools/spark_shadows/. "$DEST/shadows/"
# Also keep under tools/ for PYTHONPATH / sibling-K layout
cp -a tools/spark_helpers "$DEST/tools/spark_helpers"
cp -a tools/spark_shadows "$DEST/tools/spark_shadows"
chmod +x "$DEST/helpers/"*.sh "$DEST/shadows/"*.sh \
  "$DEST/tools/spark_helpers/"*.sh "$DEST/tools/spark_shadows/"*.sh
# Assorted tools already useful for compile/decompile/build
cp -a tools/spark-bc-dump "$DEST/tools/spark-bc-dump"
if [[ -d tools/spark-eval ]]; then
  mkdir -p "$DEST/tools/spark-eval"
  cp -a tools/spark-eval/README.md "$DEST/tools/spark-eval/" 2>/dev/null || true
  cp -a tools/spark-eval/run.py "$DEST/tools/spark-eval/" 2>/dev/null || true
fi
if [[ -d tools/spark-bpe-seed ]]; then
  mkdir -p "$DEST/tools/spark-bpe-seed"
  cp -a tools/spark-bpe-seed/README.md \
    "$DEST/tools/spark-bpe-seed/" 2>/dev/null || true
fi
# Include K-lane tree if present on main (tools/spark_kit or similar)
for kdir in tools/spark_kit tools/spark-kit tools/helpers tools/shadows; do
  if [[ -d "$kdir" ]]; then
    base="$(basename "$kdir")"
    cp -a "$kdir" "$DEST/tools/$base"
  fi
done
# Bin wrappers (scripts, not symlinks — $0 must stay under bin/)
cat >"$DEST/bin/spark-helper-compile" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$ROOT/helpers/compile.sh" "$@"
EOF
chmod +x "$DEST/bin/spark-helper-compile"
cat >"$DEST/bin/spark-helper-decompile" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$ROOT/helpers/decompile.sh" "$@"
EOF
chmod +x "$DEST/bin/spark-helper-decompile"
cat >"$DEST/bin/spark-helper-opcodes" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PYTHONPATH="${ROOT}/runtime/python:${ROOT}/sdk/python-sparklang:${PYTHONPATH:-}"
exec python3 "$ROOT/helpers/opcode_sheet.py" "$@"
EOF
chmod +x "$DEST/bin/spark-helper-opcodes"
cat >"$DEST/bin/spark-helper-fixture-lint" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$ROOT/helpers/fixture_lint.py" "$@"
EOF
chmod +x "$DEST/bin/spark-helper-fixture-lint"
cat >"$DEST/bin/spark-shadow-copy" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export SPARK_SHADOW_ROOT="${SPARK_SHADOW_ROOT:-$ROOT/out/shadow}"
exec bash "$ROOT/tools/spark_shadows/shadow_copy.sh" "$@"
EOF
chmod +x "$DEST/bin/spark-shadow-copy"
cat >"$DEST/bin/spark-shadow-build" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export SPARK_SHADOW_ROOT="${SPARK_SHADOW_ROOT:-$ROOT/out/shadow}"
exec bash "$ROOT/tools/spark_shadows/shadow_build.sh" "$@"
EOF
chmod +x "$DEST/bin/spark-shadow-build"
cat >"$DEST/bin/spark-shadow-verify" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export SPARK_SHADOW_ROOT="${SPARK_SHADOW_ROOT:-$ROOT/out/shadow}"
exec bash "$ROOT/tools/spark_shadows/shadow_verify.sh" "$@"
EOF
chmod +x "$DEST/bin/spark-shadow-verify"

# Sources so shadow-build can remake bootstrap inside the pack
for d in bootstrap selfhost asm; do
  if [[ -d "$d" ]]; then
    cp -a "$d" "$DEST/$d"
  fi
done
cp -a Makefile spark.toml "$DEST/" 2>/dev/null || true

# Desktop entry (optional; graphical launcher)
mkdir -p "$DEST/share/applications"
cat >"$DEST/share/applications/sparklang-bc-gui.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=SparkLang SPARK_BC Compile/Decompile
Comment=Graphical compile and decompile for SparkLang bytecode
Exec=$NAME/bin/spark-bc-gui
Path=$NAME
Terminal=false
Categories=Development;IDE;
EOF

# Pack README
cat >"$DEST/README.txt" <<EOF
SparkLang SDK + runtime + IDE + GUI + helpers pack (${VERSION})
==============================================================

Contents
--------
  bin/spark-bootstrap        CPU runtime / --compile / --run-bc
  bin/sparkc                 symlink → spark-bootstrap
  bin/spark-bc-gui           Graphical compile + decompile (tkinter)
  bin/spark-ide              Open workspace + language extension
  bin/spark-helper-compile   Helper: compile .spark → .sparkbc
  bin/spark-helper-decompile Helper: dump/inspect .sparkbc
  bin/spark-helper-opcodes   Opcode sheet from real OP tables
  bin/spark-helper-fixture-lint  JSONL fixture lint
  bin/spark-shadow-copy|build|verify  Isolated shadow workflows
  runtime/                   Python package, dump tools, .sparkbc
  sdk/                       Docs, headers, examples, python APIs
  ide/                       VS Code / Cursor extension + workspace
  gui/                       SPARK_BC GUI sources
  helpers/                   Compile/decompile/opcode/fixture helpers
  shadows/                   Shadow copy / build / verify scripts
  tools/                     BC dump + helpers/shadows + assorted

Quick start
-----------
  # Graphical compiler / decompiler (requires a display + python3-tk)
  ./bin/spark-bc-gui

  # Helpers
  ./bin/spark-helper-compile sdk/examples/spark_builder.spark /tmp/x.sparkbc
  ./bin/spark-helper-decompile /tmp/x.sparkbc
  ./bin/spark-helper-opcodes

  # Shadows (isolated rebuild)
  ./bin/spark-shadow-copy mybuild
  ./bin/spark-shadow-build mybuild
  ./bin/spark-shadow-verify mybuild

  # IDE (Cursor or VS Code)
  ./bin/spark-ide

CPU only. Never RTX PRO 6000. Does not claim beat Claude.

Docs: https://sparklang.dev/docs/sdk-ide-download.html
EOF

# Expected-path manifest (consumed by tests + website)
python3 - <<'PY' "$DEST" "$VERSION" "$MANIFEST" "$TARBALL"
import hashlib, json, os, sys, tarfile
from pathlib import Path

dest = Path(sys.argv[1])
version = sys.argv[2]
manifest_path = Path(sys.argv[3])
tarball = Path(sys.argv[4])
required = [
    "bin/spark-bootstrap",
    "bin/sparkc",
    "bin/spark-bc-gui",
    "bin/spark-ide",
    "bin/spark-helper-compile",
    "bin/spark-helper-decompile",
    "bin/spark-helper-opcodes",
    "bin/spark-helper-fixture-lint",
    "bin/spark-shadow-copy",
    "bin/spark-shadow-build",
    "bin/spark-shadow-verify",
    "runtime/python/sparklang/__init__.py",
    "runtime/python/sparklang/model_lab/bc_dump.py",
    "runtime/tools/spark-bc-dump/dump.py",
    "sdk/docs/SPARK_BC.md",
    "sdk/include/spark_rt.h",
    "sdk/examples/spark_builder.spark",
    "ide/spark-ide-extension/package.json",
    "ide/spark.code-workspace",
    "ide/open-spark-ide.sh",
    "gui/spark_bc_gui/app.py",
    "gui/spark_bc_gui/core.py",
    "tools/spark_bc_gui/__main__.py",
    "helpers/compile.sh",
    "helpers/decompile.sh",
    "helpers/opcode_sheet.py",
    "helpers/fixture_lint.py",
    "shadows/shadow_copy.sh",
    "shadows/shadow_build.sh",
    "shadows/shadow_verify.sh",
    "tools/spark-bc-dump/dump.py",
    "tools/spark_helpers/compile.sh",
    "tools/spark_shadows/shadow_copy.sh",
    "bootstrap/main.c",
    "README.txt",
]
missing = [p for p in required if not (dest / p).exists()]
if missing:
    raise SystemExit("pack missing paths: %s" % missing)

# Prefer at least one published .sparkbc
bcs = list((dest / "runtime/docs/examples").glob("*.sparkbc"))
if not bcs:
    raise SystemExit("pack missing runtime/docs/examples/*.sparkbc")

stage = dest.parent
name = dest.name
tarball.parent.mkdir(parents=True, exist_ok=True)
with tarfile.open(tarball, "w:gz") as tar:
    tar.add(dest, arcname=name)

sha = hashlib.sha256(tarball.read_bytes()).hexdigest()
payload = {
    "name": name,
    "version": version,
    "tarball": tarball.name,
    "sha256": sha,
    "size_bytes": tarball.stat().st_size,
    "required_paths": required,
    "sparkbc_examples": [p.name for p in sorted(bcs)],
    "launch": {
        "gui": "./bin/spark-bc-gui",
        "ide": "./bin/spark-ide",
        "compile": "./bin/spark-helper-compile <file.spark> [out.sparkbc]",
        "decompile": "./bin/spark-helper-decompile <file.sparkbc>",
        "shadow": "./bin/spark-shadow-copy <name> && ./bin/spark-shadow-build <name>",
    },
    "notes": [
        "CPU runtime only — never RTX PRO 6000",
        "Does not claim beat Claude",
        "GUI uses real --compile + bc_dump.format_dump",
        "Includes helpers + shadows + BC dump tools",
    ],
}
manifest_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
print("wrote", tarball)
print("sha256", sha)
print("manifest", manifest_path)
PY

# Mirror into website/downloads for Pages (tarball may be large — copy manifest always)
mkdir -p "$WEB_DL"
cp -a "$MANIFEST" "$WEB_DL/sdk-pack-MANIFEST.json"
# Copy tarball if under ~50MB; otherwise leave in out/ only
SIZE="$(stat -c%s "$TARBALL")"
if [[ "$SIZE" -lt 52428800 ]]; then
  cp -a "$TARBALL" "$WEB_DL/"
  echo "==> Mirrored tarball to website/downloads/"
else
  echo "==> Tarball ${SIZE} bytes — left in out/sdk-pack (not mirrored)"
fi

echo "==> SDK pack ready: $TARBALL"
ls -lh "$TARBALL" "$MANIFEST"
