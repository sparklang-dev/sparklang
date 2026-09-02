"""Small linear / MLP abstain head on a hidden vector."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Optional, Union

PathLike = Union[str, Path]

# Keep CUDA off for head train/infer unless user opts in.
import os

os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")

import torch
from torch import nn


class AbstainHead(nn.Module):
    """Maps last-token hidden → abstain logit.

    kind=internal|external is metadata only — same math.
    """

    def __init__(
        self,
        hidden_dim: int,
        *,
        mlp: bool = False,
        mid: int = 64,
    ) -> None:
        super().__init__()
        self.hidden_dim = int(hidden_dim)
        self.mlp = bool(mlp)
        if mlp:
            self.net = nn.Sequential(
                nn.Linear(self.hidden_dim, mid),
                nn.ReLU(),
                nn.Linear(mid, 1),
            )
        else:
            self.net = nn.Linear(self.hidden_dim, 1)

    def forward(self, h: torch.Tensor) -> torch.Tensor:
        """h: (B, H) or (H,) → abstain logit (B,) or scalar."""
        if h.dim() == 1:
            h = h.unsqueeze(0)
            return self.net(h).squeeze(-1).squeeze(0)
        return self.net(h).squeeze(-1)

    def p_abstain(self, h: torch.Tensor) -> torch.Tensor:
        """Sigmoid probability of abstain."""
        return torch.sigmoid(self.forward(h))


def head_from_state(
    state: dict[str, Any],
    map_location: str = "cpu",
) -> AbstainHead:
    """Rebuild head from a saved state dict envelope."""
    meta = state.get("meta") or {}
    hidden = int(meta.get("hidden_dim") or state.get("hidden_dim") or 64)
    mlp = bool(meta.get("mlp") or False)
    mid = int(meta.get("mid") or 64)
    head = AbstainHead(hidden, mlp=mlp, mid=mid)
    weights = state.get("state_dict") or state
    # Drop non-tensor meta keys if raw state_dict was top-level.
    sd = {
        k: v
        for k, v in weights.items()
        if isinstance(v, torch.Tensor)
    }
    if not sd and "net.weight" in state:
        sd = {
            k: v
            for k, v in state.items()
            if isinstance(v, torch.Tensor)
        }
    head.load_state_dict(sd)
    head.eval()
    return head


def save_head(
    head: AbstainHead,
    path: PathLike,
    *,
    kind: str = "internal",
    extra: Optional[dict[str, Any]] = None,
) -> Path:
    """Write abstain_head.pt (real weights, not a stub marker)."""
    out = Path(path)
    out.parent.mkdir(parents=True, exist_ok=True)
    payload: dict[str, Any] = {
        "meta": {
            "kind": kind,
            "hidden_dim": head.hidden_dim,
            "mlp": head.mlp,
            "spark": "abstain_head",
            "version": 1,
        },
        "state_dict": head.state_dict(),
    }
    if extra:
        payload["meta"].update(extra)
    torch.save(payload, out)
    # Sidecar JSON for tools that must not unpickle.
    meta_path = out.with_suffix(".meta.json")
    meta_path.write_text(
        json.dumps(payload["meta"], indent=2) + "\n",
        encoding="utf-8",
    )
    return out


def load_head(path: PathLike) -> AbstainHead:
    """Load head weights from disk (CPU)."""
    state = torch.load(Path(path), map_location="cpu", weights_only=False)
    if not isinstance(state, dict):
        raise ValueError(f"bad head file: {path}")
    return head_from_state(state)
