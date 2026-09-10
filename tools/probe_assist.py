#!/usr/bin/env python3
"""Measured probe: grounded LLM-assist decompile capability.

Runs tools/decompile_assist.py for real on two published .sparkbc
fixtures: offline explainer must track input bytes (sensitivity),
the grounding validator must pass real output and reject injected
fabrications, and the --llm accelerator is tried against the local
gateway (degrade-to-offline is a normal, recorded state — never
faked). Emits website/data/probes/llm_assist_decompile.json.
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "python"))

import decompile_assist as da  # noqa: E402
from sparklang.model_lab.bc_dump import OP_NAME  # noqa: E402

OUT = ROOT / "website/data/probes/llm_assist_decompile.json"
INPUTS = [
    ROOT / "docs/examples/spark-train-step.sparkbc",
    ROOT / "docs/examples/spark-self.sparkbc",
]


def _sha(path: Path) -> str:
    """Hash an input fixture."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    """Run the measured assist probe and write probe JSON."""
    details: dict = {"inputs": []}
    texts: list[str] = []
    grounding_pass = 0
    for path in INPUTS:
        text, meta = da.run_assist(
            path, use_llm=False, base_url="", model="code"
        )
        texts.append(text)
        grounding_pass += int(meta["grounding"] == "pass")
        details["inputs"].append(
            {
                "path": str(path.relative_to(ROOT)),
                "sha256": _sha(path),
                "n_ops": meta["n_ops"],
                "grounding": meta["grounding"],
            }
        )
    sensitivity = texts[0] != texts[1]

    # Negative: injected fabrication must be rejected (real bytes).
    analysis = da.load_analysis(INPUTS[0])
    present = {op["name"] for op in analysis["ops"]}
    missing = sorted(set(OP_NAME.values()) - present)
    fake = texts[0] + "\nIt runs %s on str999.\n" % missing[0]
    injection_rejected = bool(da.grounding_violations(fake, analysis))

    # --llm accelerator against the local gateway (honest record).
    gateway = os.environ.get("AI_GATEWAY_URL", da.DEFAULT_GATEWAY)
    llm_meta: dict = {"gateway": gateway, "alias": "code"}
    try:
        text_llm, meta_llm = da.run_assist(
            INPUTS[0], use_llm=True, base_url=gateway, model="code"
        )
        llm_meta["state"] = meta_llm["llm"]
        llm_meta["grounding"] = meta_llm["grounding"]
        if meta_llm["llm"] == "ok":
            llm_meta["aid_bytes"] = len(text_llm) - len(texts[0])
    except da.GroundingError as exc:
        llm_meta["state"] = "grounding_rejected"
        llm_meta["violations"] = exc.violations
    details["offline_grounding_pass"] = grounding_pass
    details["sensitivity_distinct_outputs"] = sensitivity
    details["injection_rejected"] = injection_rejected
    details["llm"] = llm_meta
    ok = (
        grounding_pass == len(INPUTS)
        and sensitivity
        and injection_rejected
        and llm_meta.get("state") != "grounding_rejected"
    )
    payload = {
        "capability": "llm_assist_decompile",
        "probe": "tools/probe_assist.py",
        "input_sha256": details["inputs"][0]["sha256"],
        "measured": True,
        "ok": ok,
        "details": details,
        "ts": datetime.now(timezone.utc).isoformat(),
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, indent=2) + "\n")
    print(json.dumps(payload, indent=2))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
