"""Held-out abstain gate evaluation (honest metrics, not SOTA).

Split a labeled corpus → optionally train on the train fold → score
precision / recall / F1 on held-out. Never claim production accuracy.
"""

from __future__ import annotations

import json
import os
import random
from pathlib import Path
from typing import Any, Optional, Union

os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")

import torch

from sparklang.abstain.corpus import (
    LABEL_ABSTAIN,
    LABEL_ANSWER,
    load_corpus,
    write_corpus,
)
from sparklang.abstain.gate import GateConfig, select_before_sample
from sparklang.abstain.head import AbstainHead, load_head
from sparklang.abstain.train import _hash_feats, train_abstain_head

PathLike = Union[str, Path]


def split_train_heldout(
    rows: list[dict[str, Any]],
    *,
    holdout_frac: float = 0.2,
    seed: int = 42,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Stratified train / held-out split by abstain label.

    Ensures both folds keep at least one answer and one abstain row
    when the corpus is large enough; otherwise raises.
    """
    if not 0.0 < float(holdout_frac) < 1.0:
        raise ValueError(
            f"holdout_frac must be in (0,1), got {holdout_frac}"
        )
    by_label: dict[int, list[dict[str, Any]]] = {
        LABEL_ANSWER: [],
        LABEL_ABSTAIN: [],
    }
    for row in rows:
        by_label[int(row["label"])].append(row)
    rng = random.Random(int(seed))
    train: list[dict[str, Any]] = []
    held: list[dict[str, Any]] = []
    for label, group in by_label.items():
        if not group:
            raise ValueError(
                f"corpus missing label={label} rows for split"
            )
        idxs = list(range(len(group)))
        rng.shuffle(idxs)
        n_hold = max(1, int(round(len(group) * holdout_frac)))
        if n_hold >= len(group):
            n_hold = len(group) - 1
        if n_hold < 1:
            raise ValueError(
                f"need ≥2 rows for label={label} to split"
            )
        hold_set = set(idxs[:n_hold])
        for i, row in enumerate(group):
            if i in hold_set:
                held.append(row)
            else:
                train.append(row)
    if not train or not held:
        raise ValueError("split produced empty train or held-out")
    rng.shuffle(train)
    rng.shuffle(held)
    return train, held


def _row_features(row: dict[str, Any], dim: int) -> list[float]:
    """Hidden vector or bag-hash fallback for one row."""
    feats = row.get("hidden")
    if feats is not None:
        out = [float(x) for x in feats]
        if len(out) != dim:
            raise ValueError(
                f"hidden dim {len(out)} != expected {dim}"
            )
        return out
    return _hash_feats(str(row["text"]), dim)


def _binary_metrics(
    y_true: list[int],
    y_pred: list[int],
    *,
    positive: int = LABEL_ABSTAIN,
) -> dict[str, float]:
    """Precision / recall / F1 for the abstain (positive) class."""
    tp = fp = tn = fn = 0
    for t, p in zip(y_true, y_pred):
        if t == positive and p == positive:
            tp += 1
        elif t != positive and p == positive:
            fp += 1
        elif t != positive and p != positive:
            tn += 1
        else:
            fn += 1
    prec = tp / (tp + fp) if (tp + fp) else 0.0
    rec = tp / (tp + fn) if (tp + fn) else 0.0
    f1 = (
        (2.0 * prec * rec / (prec + rec))
        if (prec + rec)
        else 0.0
    )
    n = len(y_true) or 1
    acc = (tp + tn) / n
    return {
        "precision": round(prec, 6),
        "recall": round(rec, 6),
        "f1": round(f1, 6),
        "accuracy": round(acc, 6),
        "tp": float(tp),
        "fp": float(fp),
        "tn": float(tn),
        "fn": float(fn),
    }


def score_heldout(
    head: AbstainHead,
    rows: list[dict[str, Any]],
    config: GateConfig,
) -> dict[str, Any]:
    """Score held-out rows; return metrics + per-row summary."""
    y_true: list[int] = []
    y_pred: list[int] = []
    details: list[dict[str, Any]] = []
    dim = int(head.hidden_dim)
    head.eval()
    with torch.no_grad():
        for row in rows:
            feats = _row_features(row, dim)
            h = torch.tensor(feats, dtype=torch.float32)
            p = float(head.p_abstain(h).item())
            d = select_before_sample(p, config)
            pred = LABEL_ABSTAIN if d.abstain else LABEL_ANSWER
            lab = int(row["label"])
            y_true.append(lab)
            y_pred.append(pred)
            details.append(
                {
                    "id": row.get("id"),
                    "label": lab,
                    "pred": pred,
                    "p_abstain": round(p, 6),
                    "reason": d.reason,
                    "correct": pred == lab,
                }
            )
    metrics = _binary_metrics(y_true, y_pred)
    n_abs_true = sum(1 for y in y_true if y == LABEL_ABSTAIN)
    n_abs_pred = sum(1 for y in y_pred if y == LABEL_ABSTAIN)
    metrics["n"] = float(len(rows))
    metrics["n_abstain_true"] = float(n_abs_true)
    metrics["n_abstain_pred"] = float(n_abs_pred)
    metrics["abstain_rate_pred"] = round(
        n_abs_pred / (len(rows) or 1), 6
    )
    return {
        "metrics": metrics,
        "rows": details,
        "threshold": float(config.threshold),
        "positive_class": "abstain",
    }


def run_heldout_eval(
    dataset: PathLike,
    *,
    weights: Optional[PathLike] = None,
    train_out: Optional[PathLike] = None,
    holdout_frac: float = 0.2,
    seed: int = 42,
    threshold: float = 0.7,
    idk: str = "I don't know.",
    hidden_dim: Optional[int] = None,
    steps: int = 200,
    split_dir: Optional[PathLike] = None,
    out: Optional[PathLike] = None,
) -> dict[str, Any]:
    """Train (unless weights) on train fold; score held-out.

    Metrics are **fixture / synthetic / host-backbone** only — not
    production SOTA. When ``weights`` is supplied, the head is not
    retrained; if those weights were fit on the full corpus, held-out
    scores can leak (stamped in the result).
    """
    rows = load_corpus(dataset)
    train_rows, held_rows = split_train_heldout(
        rows, holdout_frac=holdout_frac, seed=seed
    )
    if split_dir is not None:
        sd = Path(split_dir)
        write_corpus(train_rows, sd / "train.jsonl")
        write_corpus(held_rows, sd / "heldout.jsonl")

    leakage_risk = False
    trained: Optional[dict[str, Any]] = None
    if weights is not None:
        head = load_head(weights)
        wpath = Path(weights)
        leakage_risk = True
        quality = "weights_provided_possible_leakage"
    else:
        # Persist train fold, fit head, then score held-out.
        fold_dir = Path(split_dir or "out/heads-eval")
        fold_dir.mkdir(parents=True, exist_ok=True)
        tmp_train = fold_dir / "train_fold.jsonl"
        write_corpus(train_rows, tmp_train)
        w_out = Path(
            train_out
            if train_out is not None
            else fold_dir / "abstain_heldout.pt"
        )
        trained = train_abstain_head(
            tmp_train,
            w_out,
            kind="internal",
            hidden_dim=hidden_dim,
            steps=steps,
            seed=seed,
        )
        head = load_head(w_out)
        wpath = w_out
        quality = "heldout_eval_retrained"
        leakage_risk = False

    cfg = GateConfig(threshold=float(threshold), idk=str(idk))
    scored = score_heldout(head, held_rows, cfg)
    result: dict[str, Any] = {
        "op": "head_eval",
        "mode": "live",
        "dataset": str(dataset),
        "weights": str(wpath),
        "n_total": len(rows),
        "n_train": len(train_rows),
        "n_heldout": len(held_rows),
        "holdout_frac": float(holdout_frac),
        "seed": int(seed),
        "hidden_dim": int(head.hidden_dim),
        "threshold": float(threshold),
        "metrics": scored["metrics"],
        "positive_class": "abstain",
        "quality": quality,
        "leakage_risk": leakage_risk,
        "note": (
            "held-out fixture/synthetic/host metrics only — "
            "not production SOTA; do not market as LM accuracy"
        ),
        "state": "succeeded",
    }
    if trained is not None:
        result["train"] = {
            "out": trained.get("out"),
            "loss": trained.get("loss"),
            "n": trained.get("n"),
            "feature_source": trained.get("feature_source"),
            "quality": trained.get("quality"),
        }
    if split_dir is not None:
        result["split_dir"] = str(split_dir)
    # Compact row dump optional via env (keep default small).
    if os.environ.get("SPARK_ABSTAIN_EVAL_ROWS", "") == "1":
        result["rows"] = scored["rows"]
    else:
        wrong = [r for r in scored["rows"] if not r["correct"]]
        result["n_errors"] = len(wrong)
        result["errors_sample"] = wrong[:10]

    if out is not None:
        op = Path(out)
        op.parent.mkdir(parents=True, exist_ok=True)
        op.write_text(
            json.dumps(result, indent=2) + "\n",
            encoding="utf-8",
        )
        result["out"] = str(op)
    return result
