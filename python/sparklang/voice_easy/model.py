"""Owned VoiceEasy heads — STT classify + TTS synth params.

Written and trained in this repo. Tiny or large dims from scales.
Not a downloaded mega TTS. Does not beat Claude.
"""

from __future__ import annotations

import json
import math
import struct
from pathlib import Path
from typing import Any

from sparklang.model_lab.weights import (
    read_safetensors,
    write_safetensors,
)


def _pack_f32(values: list[float]) -> bytes:
    """Little-endian F32 pack."""
    return b"".join(struct.pack("<f", float(v)) for v in values)


def _unpack_f32(raw: bytes) -> list[float]:
    """Little-endian F32 unpack."""
    n = len(raw) // 4
    return list(struct.unpack("<%df" % n, raw[: n * 4]))


def _xavier(n_in: int, n_out: int, seed: int) -> list[float]:
    """Deterministic fan-in init (no torch required)."""
    scale = math.sqrt(2.0 / max(1, n_in + n_out))
    out: list[float] = []
    x = seed * 1103515245 + 12345
    for _ in range(n_in * n_out):
        x = (1103515245 * x + 12345) & 0x7FFFFFFF
        u = (x / 0x7FFFFFFF) * 2.0 - 1.0
        out.append(u * scale)
    return out


class VoiceEasyModel:
    """Shared embed + STT logits + TTS tone head."""

    def __init__(
        self,
        *,
        dim: int,
        n_phrases: int,
        feat_bins: int,
        stt_w: list[float],
        tts_w: list[float],
        meta: dict[str, Any] | None = None,
    ) -> None:
        """Bind owned weight vectors."""
        self.dim = int(dim)
        self.n_phrases = int(n_phrases)
        self.feat_bins = int(feat_bins)
        self.stt_w = list(stt_w)
        self.tts_w = list(tts_w)
        self.meta = dict(meta or {})

    @classmethod
    def init_from_scale(
        cls,
        scale: dict[str, Any],
        *,
        seed: int = 7,
    ) -> "VoiceEasyModel":
        """Allocate fresh owned heads for a scale config."""
        dim = int(scale["dim"])
        n_phrases = int(scale["n_phrases"])
        bins = int(scale["feat_bins"])
        # STT: feat_bins -> dim -> n_phrases
        stt = _xavier(bins, dim, seed) + _xavier(dim, n_phrases, seed + 1)
        # TTS: n_phrases one-hot proxy dim -> 2 (freq_norm, amp)
        tts = _xavier(n_phrases, 2, seed + 2)
        return cls(
            dim=dim,
            n_phrases=n_phrases,
            feat_bins=bins,
            stt_w=stt,
            tts_w=tts,
            meta={
                "profile": "spark-voice-easy",
                "scale": str(scale.get("name") or "tiny"),
                "trained": "false",
                "beats_claude": "false",
                "never": "rtx-pro-6000",
                "brain": "owned-weights",
                "vram_gi_hint": str(scale.get("vram_gi_hint") or 0),
            },
        )

    def stt_logits(self, feats: list[float]) -> list[float]:
        """Forward STT: features → phrase logits."""
        bins = self.feat_bins
        dim = self.dim
        n = self.n_phrases
        x = list(feats[:bins]) + [0.0] * max(0, bins - len(feats))
        w1 = self.stt_w[: bins * dim]
        w2 = self.stt_w[bins * dim : bins * dim + dim * n]
        h = [0.0] * dim
        for j in range(dim):
            s = 0.0
            for i in range(bins):
                s += x[i] * w1[i * dim + j]
            h[j] = math.tanh(s)
        logits = [0.0] * n
        for k in range(n):
            s = 0.0
            for j in range(dim):
                s += h[j] * w2[j * n + k]
            logits[k] = s
        return logits

    def stt_predict(self, feats: list[float]) -> int:
        """Argmax phrase id."""
        logits = self.stt_logits(feats)
        best = 0
        for i, v in enumerate(logits):
            if v > logits[best]:
                best = i
        return best

    def tts_params(self, phrase_id: int) -> tuple[float, float]:
        """TTS head → (freq_hz, amp) for PCM synth."""
        n = self.n_phrases
        pid = max(0, min(n - 1, int(phrase_id)))
        # Row pid of n×2
        f_n = self.tts_w[pid * 2]
        a_n = self.tts_w[pid * 2 + 1]
        freq = 180.0 + (math.tanh(f_n) + 1.0) * 200.0
        amp = 0.15 + (math.tanh(a_n) + 1.0) * 0.2
        return freq, amp

    def save(self, out_dir: Path) -> Path:
        """Write safetensors + arch.json under out_dir."""
        out_dir = Path(out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        bins = self.feat_bins
        dim = self.dim
        n = self.n_phrases
        tensors = {
            "voice.stt.w1": (
                (bins, dim),
                _pack_f32(self.stt_w[: bins * dim]),
            ),
            "voice.stt.w2": (
                (dim, n),
                _pack_f32(
                    self.stt_w[bins * dim : bins * dim + dim * n]
                ),
            ),
            "voice.tts.w": (
                (n, 2),
                _pack_f32(self.tts_w[: n * 2]),
            ),
        }
        meta = {
            str(k): str(v) for k, v in self.meta.items()
        }
        meta.update(
            {
                "dim": str(dim),
                "n_phrases": str(n),
                "feat_bins": str(bins),
                "profile": "spark-voice-easy",
                "beats_claude": "false",
                "never": "rtx-pro-6000",
                "brain": "owned-weights",
            }
        )
        dest = out_dir / "weights.safetensors"
        write_safetensors(tensors, meta, dest)
        arch = {
            "profile": "spark-voice-easy",
            "dim": dim,
            "n_phrases": n,
            "feat_bins": bins,
            "scale": self.meta.get("scale", "tiny"),
            "beats_claude": False,
            "never": "rtx-pro-6000",
            "brain": "owned-weights",
            "note": (
                "Owned STT/TTS heads written+trained in sparklang; "
                "not a downloaded base model"
            ),
        }
        (out_dir / "arch.json").write_text(
            json.dumps(arch, indent=2) + "\n",
            encoding="utf-8",
        )
        return dest

    @classmethod
    def load(cls, weights: Path) -> "VoiceEasyModel":
        """Load owned voice-easy safetensors."""
        meta, tensors = read_safetensors(weights)
        dim = int(meta.get("dim") or 16)
        n = int(meta.get("n_phrases") or 6)
        bins = int(meta.get("feat_bins") or 8)
        w1 = _unpack_f32(tensors["voice.stt.w1"][1])
        w2 = _unpack_f32(tensors["voice.stt.w2"][1])
        tts = _unpack_f32(tensors["voice.tts.w"][1])
        return cls(
            dim=dim,
            n_phrases=n,
            feat_bins=bins,
            stt_w=w1 + w2,
            tts_w=tts,
            meta=dict(meta),
        )
