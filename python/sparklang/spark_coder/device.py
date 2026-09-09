"""Device pick for spark-coder — 5090 preferred, never 6000.

Owner grant (M-lane): train/serve on RTX 5090 when it helps.
RTX PRO 6000 is voice-only — hard refuse. Fall back to CPU.
"""

from __future__ import annotations

from typing import Any

# Live SoapBox map (2026-09-09): index 0 = PRO 6000, index 1 = 5090.
# Match by name substring so index swaps cannot route to voice GPU.
_FORBIDDEN_SUBSTR = (
    "6000",
    "PRO 6000",
    "RTX PRO 6000",
)
_PREFERRED_SUBSTR = ("5090",)


def _name_forbidden(name: str) -> bool:
    """True if this GPU is the voice 6000 (never train here)."""
    upper = name.upper()
    return any(s.upper() in upper for s in _FORBIDDEN_SUBSTR)


def _name_preferred(name: str) -> bool:
    """True if this GPU is the coding 5090."""
    upper = name.upper()
    return any(s.upper() in upper for s in _PREFERRED_SUBSTR)


def pick_device(
    *,
    prefer_gpu: bool = True,
    force: str | None = None,
) -> dict[str, Any]:
    """Pick train device: 5090 CUDA if free, else CPU. Never 6000.

    force: 'cpu' | '5090' | None (auto).
    """
    if force == "cpu" or not prefer_gpu:
        return {
            "device": "cpu",
            "torch_device": None,
            "reason": "cpu requested or prefer_gpu=false",
            "never": "rtx-pro-6000",
        }
    try:
        import torch
    except ImportError:
        return {
            "device": "cpu",
            "torch_device": None,
            "reason": "torch not installed",
            "never": "rtx-pro-6000",
        }
    if not torch.cuda.is_available():
        return {
            "device": "cpu",
            "torch_device": None,
            "reason": "cuda unavailable",
            "never": "rtx-pro-6000",
        }
    n = int(torch.cuda.device_count())
    candidates: list[int] = []
    refused: list[dict[str, Any]] = []
    for i in range(n):
        name = str(torch.cuda.get_device_name(i))
        if _name_forbidden(name):
            refused.append({"index": i, "name": name, "why": "6000"})
            continue
        if force == "5090" and not _name_preferred(name):
            continue
        if _name_preferred(name) or force is None:
            # Busy heuristic: >28 GiB used → treat as busy for tiny job
            try:
                free, total = torch.cuda.mem_get_info(i)
                used = total - free
                if used > 28 * (1024**3) and force != "5090":
                    refused.append(
                        {
                            "index": i,
                            "name": name,
                            "why": "busy",
                            "used_gi": round(used / (1024**3), 2),
                        }
                    )
                    continue
            except Exception:
                pass
            if _name_preferred(name):
                candidates.insert(0, i)
            else:
                candidates.append(i)
    if not candidates:
        return {
            "device": "cpu",
            "torch_device": None,
            "reason": "5090 busy or unavailable",
            "refused": refused,
            "never": "rtx-pro-6000",
        }
    idx = int(candidates[0])
    name = str(torch.cuda.get_device_name(idx))
    if _name_forbidden(name):
        raise RuntimeError(
            "refused 6000 train route (index=%d name=%s)"
            % (idx, name)
        )
    return {
        "device": "cuda",
        "torch_device": "cuda:%d" % idx,
        "index": idx,
        "name": name,
        "reason": "5090 preferred",
        "never": "rtx-pro-6000",
        "refused": refused,
    }
