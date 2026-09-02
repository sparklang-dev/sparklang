"""Export last-token hiddens for abstain head train (CPU).

Dim-matched JSONL for ``head train``. Prefer a real HF backbone when
``model`` is set. Without HF / model:

* ``source=toy`` — seeded toy vectors (CI dim 16 default)
* ``source=synthetic`` — dim-matched **synthetic** backbone vectors
  with a learnable abstain/answer signal (proves wide-dim train/ask;
  **not** a real LM and **not** production accuracy)

Never claim Llama-70B / production gate quality from fixtures.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Optional, Union

os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")

import torch

from sparklang.abstain.corpus import (
    SOURCE_HF,
    SOURCE_SYNTHETIC,
    SOURCE_TOY,
    load_corpus,
    normalize_row,
)
from sparklang.abstain.generate import (
    require_explicit_model,
    try_hf_last_hidden,
)
from sparklang.abstain.train import _hash_feats

PathLike = Union[str, Path]

_VALID_EXPORT_SOURCES = frozenset(
    {"auto", "toy", "synthetic", "hf"}
)


def toy_backbone_hidden(
    text: str,
    dim: int,
    *,
    seed: int = 42,
) -> list[float]:
    """Deterministic dim-D vector — CI stand-in for LM export.

    Not a real backbone. Use only when documenting the export→train
    pipeline offline / without downloading weights.
    """
    if dim < 1:
        raise ValueError(f"dim must be >= 1, got {dim}")
    # Bag-hash into dim, then rotate with a seeded sign pattern so
    # vectors are dense-ish and match a fixed width like a real head.
    bag = _hash_feats(text, dim)
    g = torch.Generator()
    g.manual_seed(int(seed) + dim)
    signs = torch.randint(
        0, 2, (dim,), generator=g, dtype=torch.int64
    )
    signs = signs.mul(2).sub(1).to(torch.float32)
    v = torch.tensor(bag, dtype=torch.float32) * signs
    n = float(torch.linalg.vector_norm(v).item()) or 1.0
    return (v / n).tolist()


def synthetic_backbone_hidden(
    text: str,
    dim: int,
    label: int,
    *,
    seed: int = 42,
) -> list[float]:
    """Dim-matched synthetic 'backbone' vector for wide-head CI.

    Uses a reserved head-slice for the abstain/answer signal so a
    linear probe can learn on CPU at real LM widths (e.g. 768)
    without HF weights. Remaining dims carry text bag-hash noise.

    Honest: ``source=synthetic_backbone`` — **not** HF prefill,
    **not** production accuracy, **not** a 27B/70B claim.
    """
    if dim < 8:
        raise ValueError(
            f"synthetic backbone needs dim >= 8, got {dim}"
        )
    label_i = int(label)
    if label_i not in (0, 1):
        raise ValueError(f"label must be 0 or 1, got {label_i}")
    # Text diversity (normalized bag).
    bag = _hash_feats(text, dim)
    g = torch.Generator()
    g.manual_seed(int(seed) + 17 * dim + label_i)
    noise = torch.randn(dim, generator=g, dtype=torch.float32)
    noise = noise * 0.05
    v = torch.tensor(bag, dtype=torch.float32) + noise
    # Reserved slice: first 4 dims carry a strong class signal.
    # answer → +1 on even indices; abstain → +1 on odd.
    v[0:4] = 0.0
    if label_i == 0:
        v[0] = 1.0
        v[2] = 1.0
    else:
        v[1] = 1.0
        v[3] = 1.0
    n = float(torch.linalg.vector_norm(v).item()) or 1.0
    return (v / n).tolist()


def export_hiddens(
    dataset: PathLike,
    out: PathLike,
    *,
    model: Optional[str] = None,
    hidden_dim: Optional[int] = None,
    seed: int = 42,
    kind: str = "internal",
    source: str = "auto",
) -> dict[str, Any]:
    """Write JSONL rows with ``hidden`` + ``label`` (+ text).

    * ``model`` set (or ``source=hf``) → HF last-token hidden.
      ``hidden_dim`` must match the model width or be omitted.
    * ``source=synthetic`` → synthetic_backbone at ``hidden_dim``
      (default **768** — common LM width; not a real LM).
    * ``source=toy`` / unset model → toy backbone (default dim 16).
    """
    src_arg = (source or "auto").strip().lower()
    if src_arg not in _VALID_EXPORT_SOURCES:
        raise ValueError(
            f"source must be one of {sorted(_VALID_EXPORT_SOURCES)}, "
            f"got {source!r}"
        )

    rows_in = load_corpus(dataset)
    out_p = Path(out)
    out_p.parent.mkdir(parents=True, exist_ok=True)

    model_id: Optional[str] = None
    if model:
        model_id = require_explicit_model(model)
        if src_arg == "auto":
            src_arg = "hf"
        elif src_arg != "hf":
            raise ValueError(
                f"--model requires source=hf/auto, got {source!r}"
            )
    elif src_arg == "hf":
        raise ValueError("source=hf needs --model")
    elif src_arg == "auto":
        src_arg = "toy"

    if src_arg == "hf":
        export_source = SOURCE_HF
    elif src_arg == "synthetic":
        export_source = SOURCE_SYNTHETIC
    else:
        export_source = SOURCE_TOY

    dim: Optional[int] = hidden_dim
    if export_source == SOURCE_SYNTHETIC and dim is None:
        dim = 768
    if export_source == SOURCE_TOY and dim is None:
        dim = 16

    exported: list[dict[str, Any]] = []
    for row in rows_in:
        text = str(row["text"])
        label = int(row["label"])
        if export_source == SOURCE_HF:
            assert model_id is not None
            tens = try_hf_last_hidden(model_id, text)
            if tens is None:
                raise SystemExit(
                    "export: HF hidden unavailable "
                    f"(model={model_id!r}; install "
                    "python/[hf] + local weights, set "
                    "SPARK_ABSTAIN_HF=1 for hub ids, or use "
                    "--source toy|synthetic)"
                )
            feats = tens.tolist()
            if dim is None:
                dim = len(feats)
            elif len(feats) != dim:
                raise ValueError(
                    f"hidden_dim mismatch: want {dim} "
                    f"got {len(feats)} for {text!r}"
                )
        elif export_source == SOURCE_SYNTHETIC:
            assert dim is not None
            feats = synthetic_backbone_hidden(
                text, dim, label, seed=seed
            )
        else:
            assert dim is not None
            feats = toy_backbone_hidden(text, dim, seed=seed)

        out_row: dict[str, Any] = {
            "text": text,
            "label": label,
            "label_name": row.get("label_name")
            or ("abstain" if label else "answer"),
            "hidden": feats,
            "dim": dim,
            "source": export_source,
            "kind": kind,
        }
        if row.get("reason"):
            out_row["reason"] = row["reason"]
        if row.get("id"):
            out_row["id"] = row["id"]
        if row.get("tags"):
            out_row["tags"] = row["tags"]
        exported.append(normalize_row(out_row))

    assert dim is not None
    with out_p.open("w", encoding="utf-8") as fh:
        for r in exported:
            fh.write(json.dumps(r, separators=(",", ":")) + "\n")

    quality = {
        SOURCE_HF: "hf_exported_unverified",
        SOURCE_SYNTHETIC: "synthetic_backbone_dim_match",
        SOURCE_TOY: "toy_backbone",
    }.get(export_source, "unknown")

    return {
        "op": "head_export",
        "dataset": str(dataset),
        "out": str(out_p),
        "n": len(exported),
        "hidden_dim": dim,
        "source": export_source,
        "model": model_id or "",
        "kind": kind,
        "quality": quality,
        "note": (
            "not production accuracy — retrain on target "
            "backbone before gate-quality claims"
        ),
        "state": "succeeded",
    }
