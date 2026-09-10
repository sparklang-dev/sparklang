"""Device pick for voice-easy — 5090 prefer, never 6000.

The RTX PRO 6000 is voice-serving only: eval never routes there.
CPU (int8) is the default; the 5090 is an explicit opt-in for the
large eval lane.
"""

from __future__ import annotations

from typing import Any

from sparklang.spark_coder.device import pick_device


class VoiceDeviceError(RuntimeError):
    """Fail-closed device refusal (6000-only / missing 5090)."""


def pick_voice_device(
    *,
    scale: dict[str, Any],
    force: str = "auto",
) -> dict[str, Any]:
    """Pick eval device for the given scale config.

    force: auto | cpu | 5090
    """
    if force not in ("auto", "cpu", "5090"):
        raise ValueError("device must be auto|cpu|5090")

    prefer = bool(scale.get("prefer_gpu")) or force == "5090"
    if force == "cpu":
        prefer = False

    force_arg: str | None = None
    if force == "cpu":
        force_arg = "cpu"
    elif force == "5090":
        force_arg = "5090"

    pick = pick_device(prefer_gpu=prefer, force=force_arg)
    pick = dict(pick)
    pick["scale"] = scale.get("name", "tiny")
    pick["vram_gi_hint"] = float(scale.get("vram_gi_hint") or 0)

    refused = list(pick.get("refused") or [])
    only_6000 = bool(refused) and all(
        str(r.get("why")) == "6000" for r in refused
    )
    need_5090 = bool(scale.get("require_5090")) and force != "cpu"

    if need_5090 and pick.get("device") == "cpu":
        if only_6000 or force == "5090":
            raise VoiceDeviceError(
                "voice-easy large refused: RTX PRO 6000 is "
                "voice-serving only — never eval here. Free the "
                "RTX 5090 (~%.1f GiB hint) or pass --device cpu "
                "explicitly."
                % float(scale.get("vram_gi_hint") or 3.0)
            )

    if force == "5090" and pick.get("device") != "cuda":
        raise VoiceDeviceError(
            "device=5090 requested but no usable 5090 "
            "(never routes to 6000); refused=%s" % refused
        )

    return pick
