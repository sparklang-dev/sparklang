"""TinyCoder — load/save owned weights + greedy generate.

Brain = Spark safetensors we train in-repo. Optional compile tools
sit on top; they are not the model.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from sparklang.model_lab.weights import (
    emit_init_weights,
    read_safetensors,
)
from sparklang.spark_coder import layers as L
from sparklang.spark_coder.arch import PROFILE, default_arch


class TinyCoder:
    """Owned tiny Spark coding LM (CPU)."""

    def __init__(
        self,
        tensors: dict[str, tuple[tuple[int, ...], bytes]],
        meta: dict[str, str] | None = None,
        *,
        weights_path: Path | None = None,
    ) -> None:
        """Bind tensors from Spark safetensors."""
        self.tensors = tensors
        self.meta = dict(meta or {})
        self.weights_path = weights_path
        emb = tensors["spark.embed.weight"][0]
        self.vocab = int(emb[0])
        self.dim = int(emb[1])

    @classmethod
    def from_weights(cls, path: str | Path) -> "TinyCoder":
        """Load Spark-written safetensors."""
        p = Path(path)
        meta, tensors = read_safetensors(p)
        return cls(tensors, meta, weights_path=p)

    @classmethod
    def seed_from_sparkbc(
        cls,
        sparkbc: str | Path,
        dest: str | Path,
        *,
        source: str = "",
    ) -> "TinyCoder":
        """Init owned layout from SPARK_BC (factory seed, not HF)."""
        out = Path(dest)
        out.parent.mkdir(parents=True, exist_ok=True)
        emit_init_weights(
            sparkbc,
            out,
            source=source or str(sparkbc),
            command=(
                "spark-coder seed from SPARK_BC "
                "(owned init; not trained yet)"
            ),
            dim=default_arch()["dim"],
            n_layer=default_arch()["n_layer"],
        )
        return cls.from_weights(out)

    def predict_next(self, token_ids: list[int]) -> dict[str, Any]:
        """Greedy next-byte via owned forward."""
        h = L.forward_hidden(self.tensors, token_ids)
        head = L.unpack_f32(
            self.tensors["spark.lm_head.weight"][1]
        )
        logits = L.logits_from_hidden(
            head, h["hidden_dim"], h["vocab"], h["hidden"]
        )
        argmax = max(range(h["vocab"]), key=lambda i: logits[i])
        return {
            "next_token": argmax,
            "argmax": argmax,
            "logit_max": round(logits[argmax], 6),
            "path": h["path"] + "->lm_head",
            "mlp0": h["mlp0"],
            "profile": PROFILE,
            "trained": str(self.meta.get("trained", "false")),
        }

    def generate(
        self,
        prompt: str,
        *,
        max_new: int = 64,
        stop: str | None = None,
    ) -> dict[str, Any]:
        """Greedy UTF-8 byte generation from owned weights."""
        ids = L.encode_text(prompt, self.vocab)
        new_ids: list[int] = []
        for _ in range(max(1, int(max_new))):
            pred = self.predict_next(ids + new_ids)
            nid = int(pred["next_token"])
            new_ids.append(nid)
            text = L.decode_ids(new_ids)
            if stop and stop in text:
                break
        completion = L.decode_ids(new_ids)
        return {
            "prompt": prompt,
            "completion": completion,
            "full": prompt + completion,
            "n_new": len(new_ids),
            "profile": PROFILE,
            "path": "owned-greedy",
            "trained": str(self.meta.get("trained", "false")),
            "beats_claude": False,
            "device": "cpu",
        }

    def score_next_byte(
        self,
        context: str,
        want: str,
    ) -> dict[str, Any]:
        """Score first-byte prediction for a coding pair."""
        ids = L.encode_text(context, self.vocab)
        pred = self.predict_next(ids)
        want_id = (want.encode("utf-8") or b"\0")[0] % self.vocab
        hit = int(pred["argmax"]) == int(want_id)
        return {
            "context": context,
            "want_byte": want_id,
            "pred_byte": int(pred["argmax"]),
            "hit": hit,
            "pred_char": L.decode_ids([int(pred["argmax"])]),
        }

    def arch_json(self) -> dict[str, Any]:
        """Merge default arch with weights meta arch if present."""
        arch = default_arch()
        raw = self.meta.get("arch")
        if raw:
            try:
                loaded = json.loads(raw)
                if isinstance(loaded, dict):
                    arch.update(loaded)
            except json.JSONDecodeError:
                pass
        arch["profile"] = PROFILE
        arch["trained"] = str(self.meta.get("trained", "false"))
        return arch
