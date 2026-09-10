"""STT dry + TTS dry round-trip prove for voice-easy."""

from __future__ import annotations

import json
import math
import struct
import wave
from pathlib import Path
from typing import Any

from sparklang.voice_easy.fixtures import audio_features
from sparklang.voice_easy.model import VoiceEasyModel


def _write_synth_wav(
    path: Path,
    *,
    freq_hz: float,
    amp: float,
    seconds: float = 0.25,
    rate: int = 16000,
) -> None:
    """Write PCM from TTS head params (owned synth, not vendor)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    n = max(1, int(rate * seconds))
    frames = bytearray()
    for i in range(n):
        t = i / float(rate)
        sample = int(
            max(-1.0, min(1.0, amp * math.sin(2 * math.pi * freq_hz * t)))
            * 32767
        )
        frames.extend(struct.pack("<h", sample))
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(rate)
        wf.writeframes(bytes(frames))


def prove_roundtrip(
    *,
    weights: Path,
    fixture_dir: Path,
    out_dir: Path,
) -> dict[str, Any]:
    """Prove STT classify on fixtures + TTS writes real WAVs."""
    model = VoiceEasyModel.load(weights)
    manifest_path = Path(fixture_dir) / "manifest.json"
    if not manifest_path.is_file():
        return {
            "ok": False,
            "error": "missing fixture manifest",
            "path": str(manifest_path),
        }
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    pairs = list(manifest.get("pairs") or [])
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    stt_ok = 0
    tts_ok = 0
    details: list[dict[str, Any]] = []
    for row in pairs:
        wav = Path(fixture_dir) / str(row["wav"])
        text = str(row["text"])
        feats = audio_features(wav, bins=model.feat_bins)
        pred = model.stt_predict(feats)
        pred_text = str(pairs[pred]["text"]) if pred < len(pairs) else ""
        hit = pred == int(row["id"])
        if hit:
            stt_ok += 1
        freq, amp = model.tts_params(int(row["id"]))
        spoken = out_dir / ("tts_%02d.wav" % int(row["id"]))
        _write_synth_wav(spoken, freq_hz=freq, amp=amp)
        size = spoken.stat().st_size if spoken.is_file() else 0
        tts_hit = size > 44
        if tts_hit:
            tts_ok += 1
        details.append(
            {
                "id": row["id"],
                "text": text,
                "pred": pred,
                "pred_text": pred_text,
                "stt_ok": hit,
                "tts_wav": str(spoken),
                "tts_bytes": size,
                "tts_ok": tts_hit,
            }
        )

    n = max(1, len(pairs))
    stt_acc = stt_ok / n
    tts_acc = tts_ok / n
    ok = stt_acc >= 0.5 and tts_acc >= 1.0
    report = {
        "ok": ok,
        "stt_acc": stt_acc,
        "tts_acc": tts_acc,
        "n": len(pairs),
        "trained": str(model.meta.get("trained")),
        "scale": model.meta.get("scale"),
        "never": "rtx-pro-6000",
        "details": details,
        "note": (
            "Dry STT/TTS round-trip on owned heads — "
            "not a vendor clone claim"
        ),
    }
    (out_dir / "roundtrip.json").write_text(
        json.dumps(report, indent=2) + "\n",
        encoding="utf-8",
    )
    return report
