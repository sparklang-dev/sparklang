#!/usr/bin/env python3
"""Spark-native voice/text ask over a SPARK_BC dump or analysis dir.

Ears (STT) → question + dump context → brain → speaking (TTS).

Brain prefers owned TinyCoder when weights exist; always injects
dump/ops context. TinyCoder is tiny — open-ended RE answers get an
capability note. Dump remains SoT. Local tools only.
No OpenBin login.
"""

from __future__ import annotations

import argparse
import json
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT / "python") not in sys.path:
    sys.path.insert(0, str(ROOT / "python"))

from sparklang.model_lab.bc_dump import (  # noqa: E402
    decode_ops,
    format_dump,
    load_sparkbc,
)

HONESTY = (
    "Honest note: TinyCoder is a tiny owned Spark model — "
    "not OpenBin-level binary RE Q&A, and it does not beat "
    "Claude. Prefer dump.txt / ops.json as SoT."
)

WEAK_MARKERS = (
    "\x00",
    "capability note",
)


def find_bootstrap(root: Path) -> Path | None:
    """Return spark-bootstrap binary if present."""
    for name in ("spark-bootstrap", "out/spark-bootstrap"):
        p = root / name
        if p.is_file():
            return p
    return None


def find_stt_tts(root: Path) -> Path | None:
    """Return spark-stt-tts companion if built."""
    p = root / "spark-stt-tts"
    return p if p.is_file() else None


def _read_text(path: Path, limit: int = 120_000) -> str:
    """Read UTF-8 text capped for prompt injection."""
    raw = path.read_text(encoding="utf-8", errors="replace")
    if len(raw) > limit:
        return raw[:limit] + "\n…(truncated)…\n"
    return raw


def load_context(
    target: Path,
    *,
    root: Path | None = None,
) -> dict[str, Any]:
    """Load dump/ops context from analysis dir or .sparkbc/.txt.

    Compatible with helpers/spark-analyze folders:
    dump.txt, ops.json, program.sparkbc, META.json.
    """
    root = root or ROOT
    target = target.resolve()
    meta: dict[str, Any] = {
        "source": str(target),
        "kind": "unknown",
        "dump_text": "",
        "ops": [],
        "sha256": "",
        "sparkbc": None,
        "analysis_dir": None,
    }

    if target.is_dir():
        meta["kind"] = "analysis_dir"
        meta["analysis_dir"] = str(target)
        dump_p = target / "dump.txt"
        ops_p = target / "ops.json"
        bc_p = target / "program.sparkbc"
        meta_p = target / "META.json"
        if dump_p.is_file():
            meta["dump_text"] = _read_text(dump_p)
        if ops_p.is_file():
            ops_doc = json.loads(ops_p.read_text(encoding="utf-8"))
            meta["ops"] = list(ops_doc.get("ops") or [])
            meta["sha256"] = str(ops_doc.get("sha256") or "")
        if bc_p.is_file():
            meta["sparkbc"] = str(bc_p)
            if not meta["dump_text"]:
                bc = load_sparkbc(bc_p)
                meta["dump_text"] = format_dump(
                    bc,
                    source=str(bc_p),
                    command="spark-ask load analysis",
                    label="SPARK_BC dump",
                )
                meta["ops"] = decode_ops(bc)
                meta["sha256"] = str(bc["sha256"])
        if meta_p.is_file():
            try:
                m = json.loads(meta_p.read_text(encoding="utf-8"))
                if isinstance(m, dict) and not meta["sha256"]:
                    meta["sha256"] = str(m.get("sha256") or "")
            except json.JSONDecodeError:
                pass
        return meta

    suffix = target.suffix.lower()
    if suffix == ".sparkbc":
        meta["kind"] = "sparkbc"
        meta["sparkbc"] = str(target)
        bc = load_sparkbc(target)
        meta["dump_text"] = format_dump(
            bc,
            source=str(target),
            command="spark-ask load sparkbc",
            label="SPARK_BC dump",
        )
        meta["ops"] = decode_ops(bc)
        meta["sha256"] = str(bc["sha256"])
        return meta

    if suffix in (".txt", ".md") or target.name == "dump.txt":
        meta["kind"] = "dump_text"
        meta["dump_text"] = _read_text(target)
        m = re.search(r"sha256:\s*([0-9a-f]{64})", meta["dump_text"])
        if m:
            meta["sha256"] = m.group(1)
        return meta

    raise FileNotFoundError(
        "spark-ask: need analysis dir, .sparkbc, or dump.txt — "
        "got %s" % target
    )


def _ops_names(ops: list[Any]) -> list[str]:
    """Collect opcode names from ops list or decode rows."""
    names: list[str] = []
    for row in ops:
        if isinstance(row, dict) and "name" in row:
            names.append(str(row["name"]))
        elif isinstance(row, str):
            names.append(row)
    return names


def _factual_answer(question: str, ctx: dict[str, Any]) -> str | None:
    """Answer dump-grounded factual asks without TinyCoder."""
    q = question.lower().strip()
    names = _ops_names(ctx.get("ops") or [])
    sha = str(ctx.get("sha256") or "")
    dump = str(ctx.get("dump_text") or "")

    if any(k in q for k in ("how many op", "opcode count", "ops count")):
        if names:
            return (
                "This SPARK_BC has %d opcodes: %s."
                % (len(names), ", ".join(names))
            )
    if any(k in q for k in ("what op", "list op", "opcodes", "mnemonics")):
        if names:
            return (
                "Opcodes in this dump: %s. "
                "SPARK_BC is orchestration bytecode, not ELF/PE."
                % ", ".join(names)
            )
    if "sha" in q or "hash" in q:
        if sha:
            return "Dump sha256 is %s." % sha
    if any(k in q for k in ("magic", "spbc", "what is this")):
        if "SPBC" in dump or names:
            return (
                "This is a SPARK_BC dump (magic SPBC) — Spark "
                "orchestration bytecode. Dump text is SoT; not "
                "neural weights and not a malware RE project."
            )
    if "train" in q and names:
        has = "TRAIN" in names
        return (
            "TRAIN opcode is %s in this dump."
            % ("present" if has else "absent")
        )
    return None


def _weak_completion(text: str) -> bool:
    """Heuristic: TinyCoder output too weak for spoken RE Q&A."""
    t = (text or "").strip()
    if len(t) < 8:
        return True
    if any(m in t for m in WEAK_MARKERS):
        return True
    # Mostly non-printable / garbage bytes from tiny LM
    printable = sum(1 for c in t if c.isprintable() or c in "\n\t")
    if printable < max(4, int(0.6 * len(t))):
        return True
    return False


def answer_with_tinycoder(
    question: str,
    ctx: dict[str, Any],
    *,
    weights: Path,
    max_new: int = 48,
) -> dict[str, Any]:
    """Generate with owned TinyCoder + dump context prefix."""
    from sparklang.spark_coder.model import TinyCoder

    model = TinyCoder.from_weights(weights)
    dump_snip = str(ctx.get("dump_text") or "")[:2500]
    names = _ops_names(ctx.get("ops") or [])
    prompt = (
        "SPARK_BC context (SoT dump excerpt):\n"
        "%s\n"
        "opcodes: %s\n"
        "sha256: %s\n"
        "Question: %s\n"
        "Answer:"
        % (
            dump_snip,
            ", ".join(names) if names else "(none)",
            ctx.get("sha256") or "(unknown)",
            question.strip(),
        )
    )
    gen = model.generate(prompt, max_new=max_new, stop="\n\n")
    completion = str(gen.get("completion") or "").strip()
    weak = _weak_completion(completion)
    body = completion if not weak else (
        "I heard your question about this SPARK_BC dump, but "
        "TinyCoder is too small for reliable open-ended RE Q&A. "
        "From context: %d opcodes%s. Read dump.txt for SoT."
        % (
            len(names),
            (" (%s)" % ", ".join(names[:12])) if names else "",
        )
    )
    return {
        "engine": "spark_coder",
        "weak": weak,
        "completion": completion,
        "answer": ("%s\n\n%s" % (body, HONESTY)).strip(),
        "trained": gen.get("trained"),
    }


def answer_question(
    question: str,
    ctx: dict[str, Any],
    *,
    weights: Path | None = None,
    root: Path | None = None,
) -> dict[str, Any]:
    """Answer using dump facts first, else TinyCoder, else honesty."""
    root = root or ROOT
    q = (question or "").strip()
    if not q:
        return {
            "engine": "empty",
            "weak": True,
            "answer": "No question heard. " + HONESTY,
            }

    factual = _factual_answer(q, ctx)
    if factual:
        return {
            "engine": "dump_facts",
            "weak": False,
            "answer": factual + "\n\n" + HONESTY,
            }

    wpath = weights
    if wpath is None:
        cand = root / "models" / "spark-coder" / "weights.safetensors"
        if cand.is_file():
            wpath = cand
    if wpath is not None and wpath.is_file():
        try:
            return answer_with_tinycoder(q, ctx, weights=wpath)
        except (OSError, KeyError, ValueError) as exc:
            return {
                "engine": "error",
                "weak": True,
                "answer": (
                    "TinyCoder failed (%s). Dump remains SoT. %s"
                    % (exc, HONESTY)
                ),
                    }

    names = _ops_names(ctx.get("ops") or [])
    return {
        "engine": "honesty",
        "weak": True,
        "answer": (
            "No TinyCoder weights found. Dump-grounded summary: "
            "%d opcodes%s. Run `make spark-coder-train` for a "
            "tiny local brain, or ask dump-fact questions "
            "(opcodes, sha256, magic). %s"
            % (
                len(names),
                (" — " + ", ".join(names[:16])) if names else "",
                HONESTY,
            )
        ),
    }


def listen_question(
    *,
    root: Path,
    dry: bool,
    wav_in: Path | None,
    mic: bool,
    seconds: int,
    fixture_text: str | None,
) -> str:
    """STT: dry fixture, sidecar, or spark-stt-tts live/file."""
    if dry or fixture_text is not None:
        return (
            fixture_text
            or "What opcodes are in this SPARK_BC dump?"
        )

    companion = find_stt_tts(root)
    if companion is None:
        raise RuntimeError(
            "spark-stt-tts not built — run `make spark-stt-tts` "
            "or use --text / --dry"
        )

    with tempfile.TemporaryDirectory(prefix="spark-ask-stt-") as td:
        out_txt = Path(td) / "transcript.txt"
        cmd = [str(companion), "listen", "--out", str(out_txt)]
        if wav_in is not None:
            cmd.extend(["--in", str(wav_in)])
        elif mic:
            cmd.extend(["--mic", "--seconds", str(seconds)])
        else:
            raise RuntimeError(
                "voice listen needs --wav, --mic, --text, or --dry"
            )
        proc = subprocess.run(
            cmd,
            cwd=str(root),
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode != 0:
            err = (proc.stderr or proc.stdout or "").strip()
            raise RuntimeError(
                "spark-stt-tts listen failed (exit %d): %s"
                % (proc.returncode, err[:400])
            )
        if out_txt.is_file():
            return out_txt.read_text(encoding="utf-8").strip()
        # Companion may print transcript on stdout
        return (proc.stdout or "").strip()


def speak_answer(
    text: str,
    *,
    root: Path,
    dry: bool,
    wav_out: Path | None,
    play: bool,
) -> Path | None:
    """TTS: dry stub wav marker or spark-stt-tts speak."""
    out = wav_out or (root / "out" / "spark-ask-reply.wav")
    out.parent.mkdir(parents=True, exist_ok=True)

    if dry:
        # Tiny RIFF/WAVE marker — offline / CI
        rate = 8000
        n = rate // 20
        pcm = b"\x00\x00" * n
        data = pcm + b"SPARKASK"
        byte_rate = rate * 2
        hdr = struct.pack(
            "<4sI4s4sIHHIIHH4sI",
            b"RIFF",
            36 + len(data),
            b"WAVE",
            b"fmt ",
            16,
            1,
            1,
            rate,
            byte_rate,
            2,
            16,
            b"data",
            len(data),
        )
        out.write_bytes(hdr + data)
        return out

    companion = find_stt_tts(root)
    if companion is None:
        raise RuntimeError(
            "spark-stt-tts not built — run `make spark-stt-tts` "
            "or use --dry"
        )
    cmd = [
        str(companion),
        "speak",
        "--text",
        text[:4000],
        "--out",
        str(out),
    ]
    if play:
        cmd.append("--play")
    proc = subprocess.run(
        cmd,
        cwd=str(root),
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "").strip()
        raise RuntimeError(
            "spark-stt-tts speak failed (exit %d): %s"
            % (proc.returncode, err[:400])
        )
    return out


def run_ask(
    target: Path,
    *,
    root: Path | None = None,
    text: str | None = None,
    voice: bool = False,
    dry: bool = False,
    wav_in: Path | None = None,
    mic: bool = False,
    seconds: int = 3,
    wav_out: Path | None = None,
    play: bool = False,
    weights: Path | None = None,
    write_ask_md: bool = True,
) -> dict[str, Any]:
    """Full ask loop: load context → listen/text → answer → speak."""
    root = root or ROOT
    ctx = load_context(target, root=root)

    if text is not None:
        question = text.strip()
        stt_mode = "text"
    elif voice or mic or wav_in is not None:
        question = listen_question(
            root=root,
            dry=dry,
            wav_in=wav_in,
            mic=mic or (voice and wav_in is None and not dry),
            seconds=seconds,
            fixture_text=(
                "What opcodes are in this SPARK_BC dump?"
                if dry
                else None
            ),
        )
        stt_mode = "dry" if dry else ("wav" if wav_in else "mic")
    else:
        # Default interactive text when no --voice
        if sys.stdin.isatty():
            print("spark-ask> ", end="", flush=True)
            question = sys.stdin.readline().strip()
            stt_mode = "stdin"
        else:
            question = "What opcodes are in this SPARK_BC dump?"
            stt_mode = "default"

    result = answer_question(
        question, ctx, weights=weights, root=root
    )
    answer = str(result["answer"])

    tts_path = None
    tts_mode = "skip"
    if voice or wav_out is not None or play:
        tts_path = speak_answer(
            answer,
            root=root,
            dry=dry,
            wav_out=wav_out,
            play=play and not dry,
        )
        tts_mode = "dry" if dry else "live"

    payload: dict[str, Any] = {
        "ok": True,
        "question": question,
        "answer": answer,
        "engine": result.get("engine"),
        "weak": bool(result.get("weak")),
        "stt_mode": stt_mode,
        "tts_mode": tts_mode,
        "tts_wav": str(tts_path) if tts_path else None,
        "context_kind": ctx.get("kind"),
        "sha256": ctx.get("sha256"),
        "ops": len(_ops_names(ctx.get("ops") or [])),
        "never": "rtx-pro-6000",
        "openbin_login": False,
    }

    if write_ask_md:
        out_dir = None
        if ctx.get("analysis_dir"):
            out_dir = Path(str(ctx["analysis_dir"]))
        else:
            out_dir = root / "out" / "spark-ask"
            out_dir.mkdir(parents=True, exist_ok=True)
        ask_md = out_dir / "ASK.md"
        ask_md.write_text(
            "# Spark ask\n\n"
            "**Question:** %s\n\n"
            "**Answer:**\n\n%s\n\n"
            "---\n"
            "engine=%s · weak=%s · stt=%s · tts=%s\n"
            % (
                question,
                answer,
                payload["engine"],
                payload["weak"],
                stt_mode,
                tts_mode,
            ),
            encoding="utf-8",
        )
        payload["ask_md"] = str(ask_md)

    return payload


def main(argv: list[str] | None = None) -> int:
    """CLI entry for spark-ask / spark-speak-ask."""
    p = argparse.ArgumentParser(
        prog="spark-ask",
        description=(
            "Spark voice/text ask over SPARK_BC dump or "
            "analysis folder (no OpenBin login)"
        ),
    )
    p.add_argument(
        "target",
        help="analysis dir, .sparkbc, or dump.txt",
    )
    p.add_argument(
        "--text",
        metavar="Q",
        help="text question (no mic)",
    )
    p.add_argument(
        "--voice",
        action="store_true",
        help="STT in → answer → TTS out",
    )
    p.add_argument(
        "--dry",
        action="store_true",
        help="offline STT fixture + stub WAV (CI)",
    )
    p.add_argument("--wav", type=Path, help="listen from WAV")
    p.add_argument(
        "--mic",
        action="store_true",
        help="capture mic via spark-stt-tts",
    )
    p.add_argument(
        "--seconds",
        type=int,
        default=3,
        help="mic seconds (default 3)",
    )
    p.add_argument(
        "--out-wav",
        type=Path,
        help="write spoken answer WAV",
    )
    p.add_argument(
        "--play",
        action="store_true",
        help="aplay after speak (needs live TTS)",
    )
    p.add_argument(
        "--weights",
        type=Path,
        help="TinyCoder safetensors path",
    )
    p.add_argument(
        "--json",
        action="store_true",
        help="print JSON result on stdout",
    )
    args = p.parse_args(argv)

    # spark-speak-ask alias → force voice
    prog = Path(sys.argv[0]).name
    if prog in ("spark-speak-ask", "spark-speak-ask.py"):
        args.voice = True

    target = Path(args.target)
    try:
        payload = run_ask(
            target,
            root=ROOT,
            text=args.text,
            voice=args.voice,
            dry=args.dry,
            wav_in=args.wav,
            mic=args.mic,
            seconds=args.seconds,
            wav_out=args.out_wav,
            play=args.play,
            weights=args.weights,
        )
    except (
        OSError,
        RuntimeError,
        FileNotFoundError,
        ValueError,
    ) as exc:
        print("spark-ask: %s" % exc, file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(payload, indent=2))
    else:
        print("Q: %s" % payload["question"])
        print()
        print(payload["answer"])
        if payload.get("tts_wav"):
            print()
            print(
                "spoke → %s (%s)"
                % (payload["tts_wav"], payload["tts_mode"])
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
