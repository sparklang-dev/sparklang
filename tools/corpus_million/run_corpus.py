#!/usr/bin/env python3
"""Resumable Spark corpus runner — real files only; no invented rows.

Walks ~/workspaces (configurable), sha256s content, dry-run
classify+review heuristics aligned with Spark asm VM dry-run buckets.
Writes data/corpus-ledger.jsonl and data/corpus-checkpoint.json.

Does NOT execute JS. Does NOT call live LLMs (default).
Synthetic rows are never written.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
from pathlib import Path

ROOT_DEFAULT = Path.home() / "workspaces"
SPARK_ROOT = Path(__file__).resolve().parents[2]
DATA = SPARK_ROOT / "data"
LEDGER = DATA / "corpus-ledger.jsonl"
CHECKPOINT = DATA / "corpus-checkpoint.json"
TARGET = 1_000_000

EXTS = {
    ".py", ".js", ".ts", ".tsx", ".jsx", ".mjs", ".cjs", ".mts", ".cts",
    ".md", ".txt", ".spark", ".s", ".asm", ".c", ".h", ".cc", ".cpp",
    ".hpp", ".hh", ".rs", ".go", ".json", ".yaml", ".yml", ".toml",
    ".sh", ".bash", ".zsh", ".css", ".scss", ".less", ".html", ".htm",
    ".vue", ".svelte", ".rb", ".java", ".kt", ".kts", ".swift", ".php",
    ".sql", ".xml", ".gradle", ".dart", ".lua", ".pl", ".pm", ".r",
    ".ex", ".exs", ".clj", ".cljs", ".scala", ".cs", ".fs", ".hs",
    ".ml", ".mli", ".erl", ".proto", ".graphql", ".gql", ".tf", ".hcl",
    ".nix", ".cmake", ".mk", ".ini", ".cfg", ".conf", ".properties",
    ".csv", ".tsv", ".editorconfig", ".gitignore", ".dockerignore",
    ".mod", ".sum", ".zig", ".nim", ".vim", ".el", ".lisp",
}
SPECIAL_NAMES = {
    "Makefile", "Dockerfile", "Gemfile", "Procfile", "Cargo.toml",
    "go.mod", "go.sum", "CMakeLists.txt",
}
EXCLUDE_DIRS = {
    ".git", "node_modules", ".venv", "venv", "__pycache__", ".tox",
    "dist", "build", ".next", ".turbo", "coverage", ".cache",
    "recordings", "agent-transcripts", ".cursor", "target", "vendor",
    ".pnpm-store", "__pypackages__", ".mypy_cache", ".ruff_cache",
    ".pytest_cache", "eggs", ".eggs", "site-packages",
    "spark-recordings-example",
}
EXCLUDE_NAME_SUBSTR = (".env",)
MAX_FILE = 5_000_000
CHUNK = 4096
CHUNK_MIN_FILE = 8192


def is_secret_name(name: str) -> bool:
    lower = name.lower()
    if lower in {".env", ".env.local", ".env.production", ".env.development"}:
        return True
    if lower.endswith(".env") or ".env." in lower:
        return True
    if lower in {"credentials.json", "secrets.yaml", "id_rsa", "id_ed25519"}:
        return True
    return False


def classify_path(path: Path, head: bytes) -> str:
    """Dry-run lang/intent buckets (mirrors Spark classify heuristics)."""
    suf = path.suffix.lower()
    name = path.name.lower()
    text = head.decode("utf-8", errors="ignore").lower()
    if suf in {".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx", ".mts", ".cts"}:
        label = "code_js_ts"
    elif suf == ".py":
        label = "code_py"
    elif suf in {".s", ".asm"}:
        label = "code_asm"
    elif suf in {".c", ".h", ".cc", ".cpp", ".hpp", ".hh", ".rs", ".go"}:
        label = "code_systems"
    elif suf in {".md", ".txt"}:
        label = "docs"
    elif suf == ".spark":
        label = "spark"
    elif suf in {".json", ".yaml", ".yml", ".toml"}:
        label = "config"
    elif suf in {".sh", ".bash", ".zsh"}:
        label = "shell"
    elif suf in {".html", ".htm", ".css", ".scss", ".vue", ".svelte"}:
        label = "web"
    else:
        label = "other"
    # intent overlay for review-ish content
    if "eval(" in text or "dangerouslysetinnerhtml" in text:
        intent = "risky"
    elif "todo" in text or "fixme" in text:
        intent = "needs_work"
    elif "test" in name or "/test" in str(path).lower():
        intent = "test"
    else:
        intent = "ok"
    return f"{label}/{intent}"


def review_summary(path: Path, head: bytes, label: str) -> str:
    """Static review stub — never executes content."""
    issues = []
    text = head.decode("utf-8", errors="ignore")
    low = text.lower()
    if "eval(" in low:
        issues.append("eval_call")
    if path.suffix.lower() in {".js", ".ts"} and "ai-generated" in low:
        issues.append("ai_authored_marker")
    if not issues:
        issues.append("none")
    level = "higher" if label.startswith("code_js") or label.startswith("web") else (
        "lower" if label.startswith("code_asm") or label.startswith("code_systems") else "mid"
    )
    return f"static:{','.join(issues[:3])};level={level}"


def iter_files(roots: list[Path]):
    for root in roots:
        if not root.is_dir():
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = sorted(
                d for d in dirnames
                if d not in EXCLUDE_DIRS and not d.endswith(".egg-info")
            )
            for fn in sorted(filenames):
                if is_secret_name(fn):
                    continue
                path = Path(dirpath) / fn
                suf = path.suffix.lower()
                if suf not in EXTS and fn not in SPECIAL_NAMES:
                    continue
                yield path


def load_checkpoint() -> dict:
    if CHECKPOINT.exists():
        return json.loads(CHECKPOINT.read_text())
    return {
        "next_id": 0,
        "ok_count": 0,
        "err_count": 0,
        "phase": "files",
        "seen_sha": 0,
        "last_path": "",
        "started_unix": time.time(),
    }


def save_checkpoint(cp: dict) -> None:
    DATA.mkdir(parents=True, exist_ok=True)
    tmp = CHECKPOINT.with_suffix(".tmp")
    tmp.write_text(json.dumps(cp, indent=2, sort_keys=True) + "\n")
    tmp.replace(CHECKPOINT)


def append_ledger(rows: list[dict]) -> None:
    DATA.mkdir(parents=True, exist_ok=True)
    with LEDGER.open("a", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, separators=(",", ":"), sort_keys=True))
            f.write("\n")


def process_bytes(
    source: str,
    raw: bytes,
    cp: dict,
    classify_dist: dict,
) -> dict | None:
    t0 = time.perf_counter()
    # skip empty
    if not raw:
        return None
    # skip binary chunk
    if b"\x00" in raw[:512]:
        return None
    sha = hashlib.sha256(raw).hexdigest()
    path_for_cls = Path(source.split("#", 1)[0])
    label = classify_path(path_for_cls, raw[:8192])
    rev = review_summary(path_for_cls, raw[:8192], label)
    ms = int((time.perf_counter() - t0) * 1000)
    row = {
        "id": cp["next_id"],
        "source": source,
        "sha256": sha,
        "classify": label,
        "review_summary": rev,
        "ok": True,
        "ms": ms,
        "bytes": len(raw),
        "synthetic": False,
    }
    cp["next_id"] += 1
    cp["ok_count"] += 1
    cp["seen_sha"] += 1
    classify_dist[label] = classify_dist.get(label, 0) + 1
    return row


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--root",
        action="append",
        type=Path,
        help="Root to walk (repeatable). Default: workspaces",
    )
    ap.add_argument("--target", type=int, default=TARGET)
    ap.add_argument("--checkpoint-every", type=int, default=500)
    ap.add_argument("--max-seconds", type=float, default=0,
                    help="Stop after N seconds (0=until target/exhaust)")
    ap.add_argument("--reset", action="store_true",
                    help="Delete ledger+checkpoint and start fresh")
    args = ap.parse_args()
    roots = args.root or [ROOT_DEFAULT]

    if args.reset:
        if LEDGER.exists():
            LEDGER.unlink()
        if CHECKPOINT.exists():
            CHECKPOINT.unlink()

    cp = load_checkpoint()
    if "classify_dist" not in cp:
        cp["classify_dist"] = {}
    classify_dist: dict = cp["classify_dist"]
    errors: dict = cp.setdefault("errors", {})

    t_start = time.time()
    buf: list[dict] = []
    processed_this_run = 0

    # Skip already-completed whole-file sources via last_path resume:
    # We resume by skipping paths <= last_path in walk order when phase=files.
    resume_path = cp.get("last_path") or ""
    skipping = bool(resume_path) and cp.get("phase") == "files"

    def flush() -> None:
        nonlocal buf
        if not buf:
            return
        append_ledger(buf)
        buf = []
        save_checkpoint(cp)

    print(
        f"[corpus] resume ok={cp['ok_count']} target={args.target} "
        f"phase={cp.get('phase')} ledger={LEDGER}",
        flush=True,
    )

    # Phase files
    files_complete = False
    timed_out = False
    if cp.get("phase", "files") == "files":
        for path in iter_files(roots):
            if args.max_seconds and (time.time() - t_start) >= args.max_seconds:
                timed_out = True
                break
            if cp["ok_count"] >= args.target:
                break
            sp = str(path)
            if skipping:
                if sp < resume_path:
                    continue
                if sp == resume_path:
                    skipping = False
                    continue  # already done
                skipping = False
            try:
                st = path.stat()
                if st.st_size == 0 or st.st_size > MAX_FILE:
                    continue
                with path.open("rb") as f:
                    raw = f.read()
                if b"\x00" in raw[:512]:
                    continue
            except OSError as exc:
                key = type(exc).__name__
                errors[key] = errors.get(key, 0) + 1
                cp["err_count"] = cp.get("err_count", 0) + 1
                continue
            row = process_bytes(sp, raw, cp, classify_dist)
            if row is None:
                continue
            buf.append(row)
            cp["last_path"] = sp
            processed_this_run += 1
            if len(buf) >= args.checkpoint_every:
                flush()
                print(
                    f"[corpus] ok={cp['ok_count']} err={cp.get('err_count',0)} "
                    f"last={sp[:80]}",
                    flush=True,
                )
        else:
            # for-else: loop not broken → walk exhausted
            files_complete = True

        flush()
        if (
            cp["ok_count"] < args.target
            and files_complete
            and not timed_out
        ):
            cp["phase"] = "chunks"
            cp["last_path"] = ""
            save_checkpoint(cp)
            print("[corpus] files phase complete → chunks", flush=True)
        elif timed_out:
            print(
                "[corpus] stopped on time budget; "
                "phase stays 'files' for resume",
                flush=True,
            )

    # Phase chunks — real slices of large files only (not synthetic content)
    if cp.get("phase") == "chunks" and cp["ok_count"] < args.target:
        resume_path = cp.get("last_path") or ""
        skipping = bool(resume_path)
        for path in iter_files(roots):
            if args.max_seconds and (time.time() - t_start) >= args.max_seconds:
                break
            if cp["ok_count"] >= args.target:
                break
            sp = str(path)
            if skipping:
                if sp < resume_path.split("#", 1)[0]:
                    continue
                skipping = False
            try:
                st = path.stat()
                if st.st_size < CHUNK_MIN_FILE or st.st_size > MAX_FILE:
                    continue
                with path.open("rb") as f:
                    # skip whole-file duplicate: start at CHUNK offset
                    offset = CHUNK
                    f.seek(offset)
                    while cp["ok_count"] < args.target:
                        if args.max_seconds and (
                            time.time() - t_start
                        ) >= args.max_seconds:
                            break
                        raw = f.read(CHUNK)
                        if not raw:
                            break
                        if len(raw) < 64:
                            break
                        source = f"{sp}#offset={offset}"
                        if resume_path and source <= resume_path:
                            offset += len(raw)
                            continue
                        row = process_bytes(source, raw, cp, classify_dist)
                        offset += len(raw)
                        if row is None:
                            continue
                        buf.append(row)
                        cp["last_path"] = source
                        processed_this_run += 1
                        if len(buf) >= args.checkpoint_every:
                            flush()
                            print(
                                f"[corpus] ok={cp['ok_count']} "
                                f"chunk={source[:90]}",
                                flush=True,
                            )
            except OSError as exc:
                key = type(exc).__name__
                errors[key] = errors.get(key, 0) + 1
                cp["err_count"] = cp.get("err_count", 0) + 1
                continue
        flush()

    elapsed = time.time() - t_start
    rate = processed_this_run / elapsed if elapsed > 0 else 0
    remain = max(0, args.target - cp["ok_count"])
    eta = (remain / rate) if rate > 0 else None
    cp["last_run"] = {
        "processed_this_run": processed_this_run,
        "elapsed_sec": round(elapsed, 3),
        "rate_per_sec": round(rate, 2),
        "eta_sec_to_target": None if eta is None else round(eta, 1),
        "reached_target": cp["ok_count"] >= args.target,
    }
    save_checkpoint(cp)
    print(json.dumps(cp["last_run"], indent=2), flush=True)
    print(
        f"[corpus] TOTAL ok={cp['ok_count']} err={cp.get('err_count',0)} "
        f"phase={cp.get('phase')} reached={cp['ok_count'] >= args.target}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
