#!/usr/bin/env python3
"""Unit tests for local reverse (no GPU / no net)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))

from sparklang.model_lab.reverse import reverse_local


def main() -> int:
    root = ROOT / "examples/fixtures/models/tiny-lm"
    payload = reverse_local(root)
    assert payload["architecture"] == "Qwen3ForCausalLM"
    assert payload["hidden_size"] == 64
    assert payload["keep_special_training"] is True
    assert "model.embed_tokens.weight" in payload["tensors"]
    assert payload["op"] == "reverse"
    print(json.dumps({"ok": True, "n_tensors": len(payload["tensors"])}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
