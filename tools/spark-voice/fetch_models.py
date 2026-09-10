#!/usr/bin/env python3
"""Fetch the real voice-easy weights once, with pinned checksums.

Downloads pretrained open-weight models into ``models/`` (gitignored):

- STT (ears): Whisper CT2 repacks for faster-whisper —
  ``Systran/faster-whisper-tiny`` (CI smoke) and
  ``mobiuslabsgmbh/faster-whisper-large-v3-turbo`` (real lane).
  Whisper weights are MIT-licensed (OpenAI); CT2 repacks redistribute
  them unchanged in CTranslate2 format.
- TTS (voice): Kokoro v1.0 ONNX (Apache-2.0) + voices pack from the
  kokoro-onnx release assets.

Every file is verified against a pinned sha256 below. After this
script completes, the whole voice-easy pipeline runs offline
(``HF_HUB_OFFLINE=1`` in the wrappers; no network in eval paths).

Usage: python3 tools/spark-voice/fetch_models.py [--check]
"""

from __future__ import annotations

import argparse
import hashlib
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STT_ROOT = ROOT / "models" / "spark-voice-stt"
TTS_ROOT = ROOT / "models" / "spark-voice-tts"

_HF = "https://huggingface.co/%s/resolve/main/%s"
_KOKORO_REL = (
    "https://github.com/thewh1teagle/kokoro-onnx/releases/"
    "download/model-files-v1.0/%s"
)

# Pinned after the first verified fetch on SoapBox (2026-09-10).
# sha256 is the integrity pin; size is a fast pre-check.
FILES: list[dict[str, object]] = [
    # --- STT: Whisper large-v3-turbo (CT2) — real eval lane ---
    {
        "url": _HF % ("mobiuslabsgmbh/faster-whisper-large-v3-turbo",
                      "config.json"),
        "dest": STT_ROOT / "large-v3-turbo" / "config.json",
        "size": 2263,
        "sha256": "b0253ea6c0d3bea6b1e19e91a02acfd3b53f4467362efcb"
                  "5a3e6b16c9b3a9b7e",
    },
    {
        "url": _HF % ("mobiuslabsgmbh/faster-whisper-large-v3-turbo",
                      "model.bin"),
        "dest": STT_ROOT / "large-v3-turbo" / "model.bin",
        "size": 1617884929,
        "sha256": "e76620f83d5f5b69efd3d87e3dc180c1bd21df9fbebacf"
                  "d4335e5e1efcc018da",
    },
    {
        "url": _HF % ("mobiuslabsgmbh/faster-whisper-large-v3-turbo",
                      "preprocessor_config.json"),
        "dest": STT_ROOT / "large-v3-turbo" / "preprocessor_config.json",
        "size": 340,
        "sha256": "7ccc62c6f2765af1f3b46c00c9b5894426835a05021c8b9c"
                  "01eecb6dfb542711",
    },
    {
        "url": _HF % ("mobiuslabsgmbh/faster-whisper-large-v3-turbo",
                      "tokenizer.json"),
        "dest": STT_ROOT / "large-v3-turbo" / "tokenizer.json",
        "size": 2710337,
        "sha256": "297b13372ac43916285644fb9687add3cc62ee2a1adb60da"
                  "3dc25cc94c1871fd",
    },
    {
        "url": _HF % ("mobiuslabsgmbh/faster-whisper-large-v3-turbo",
                      "vocabulary.json"),
        "dest": STT_ROOT / "large-v3-turbo" / "vocabulary.json",
        "size": 1068114,
        "sha256": "c69260f2ab26d659b7c398f9a2b2b48ed0df16c3b47d7326"
                  "782fd9cba71690c1",
    },
    # --- STT: Whisper tiny (CT2) — CI smoke fallback ---
    {
        "url": _HF % ("Systran/faster-whisper-tiny", "config.json"),
        "dest": STT_ROOT / "tiny" / "config.json",
        "size": 2249,
        "sha256": "a73a28cdfe1c43ccc7202fa333d1f89c202477271407ae9a"
                  "7f19afa52039cac8",
    },
    {
        "url": _HF % ("Systran/faster-whisper-tiny", "model.bin"),
        "dest": STT_ROOT / "tiny" / "model.bin",
        "size": 75538270,
        "sha256": "dcb76c6586fc06cbdac6dd21f14cfd129cc4cdd9dce19bf4"
                  "ffa62e59cbe6e6d1",
    },
    {
        "url": _HF % ("Systran/faster-whisper-tiny", "tokenizer.json"),
        "dest": STT_ROOT / "tiny" / "tokenizer.json",
        "size": 2203239,
        "sha256": "fb7b63191e9bb045082c79fd742a3106a12c99513ab30df4"
                  "a0d47fa6cb6fd0ab",
    },
    {
        "url": _HF % ("Systran/faster-whisper-tiny", "vocabulary.txt"),
        "dest": STT_ROOT / "tiny" / "vocabulary.txt",
        "size": 459861,
        "sha256": "34ce3fe1c5041027b3f8d42912270993f986dbc4bb34cf27"
                  "f951e34a1e453913",
    },
    # --- TTS: Kokoro v1.0 ONNX + voices (Apache-2.0) ---
    {
        "url": _KOKORO_REL % "kokoro-v1.0.onnx",
        "dest": TTS_ROOT / "kokoro-v1.0.onnx",
        "size": 325532387,
        "sha256": "7d5df8ecf7d4b1878015a32686053fd0eebe2bc377234608"
                  "764cc0ef3636a6c5",
    },
    {
        "url": _KOKORO_REL % "voices-v1.0.bin",
        "dest": TTS_ROOT / "voices-v1.0.bin",
        "size": 28214398,
        "sha256": "bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9"
                  "140fe9c29f1fbf7d",
    },
]


def _sha256(path: Path) -> str:
    """Stream sha256 of a file."""
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _verify(entry: dict[str, object]) -> bool:
    """True when dest exists with matching size + sha256."""
    dest = Path(entry["dest"])  # type: ignore[arg-type]
    if not dest.is_file():
        return False
    if dest.stat().st_size != int(entry["size"]):  # type: ignore[arg-type]
        return False
    return _sha256(dest) == str(entry["sha256"])


def _fetch(entry: dict[str, object]) -> None:
    """Download one pinned file to a temp path, verify, move in."""
    dest = Path(entry["dest"])  # type: ignore[arg-type]
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    print("fetch %s" % dest.relative_to(ROOT), flush=True)
    with urllib.request.urlopen(str(entry["url"]), timeout=120) as resp:
        tmp.write_bytes(resp.read())
    if tmp.stat().st_size != int(entry["size"]):  # type: ignore[arg-type]
        tmp.unlink(missing_ok=True)
        raise RuntimeError("size mismatch for %s" % dest.name)
    got = _sha256(tmp)
    if got != str(entry["sha256"]):
        tmp.unlink(missing_ok=True)
        raise RuntimeError(
            "sha256 mismatch for %s: got %s" % (dest.name, got)
        )
    tmp.replace(dest)


def main() -> int:
    """Fetch (or --check) all pinned voice-easy model files."""
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--check",
        action="store_true",
        help="verify pinned files only; no network",
    )
    args = ap.parse_args()

    missing = [e for e in FILES if not _verify(e)]
    if args.check:
        if missing:
            for e in missing:
                print("MISSING/BAD: %s" % Path(e["dest"]).name)
            return 1
        print("voice-easy models: all %d pinned files OK" % len(FILES))
        return 0

    for entry in missing:
        _fetch(entry)
    still_bad = [e for e in FILES if not _verify(e)]
    if still_bad:
        print("FAILED verification for %d files" % len(still_bad))
        return 1
    print(
        "voice-easy models ready: %d files (fetched %d, reused %d)"
        % (len(FILES), len(missing), len(FILES) - len(missing))
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
