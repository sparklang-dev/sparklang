#!/usr/bin/env python3
"""spark-code — CLI for Spark coding assistance.

Product coder: self-hosted Qwen3-Coder-30B served locally by vLLM
(default http://127.0.0.1:8003, override with SPARK_CODER_URL).
Offline / self-hosted — no API keys, no vendor calls. This CLI
never starts or stops services; when the endpoint is down,
commands say so plainly and exit nonzero.

The in-repo TinyCoder weights stay as the reference implementation
for the training pipeline (train / prove / tool-loop, and
``generate --engine reference``). Prefer RTX 5090; never 6000.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))

from sparklang.spark_coder.model import TinyCoder
from sparklang.spark_coder.real_coder import (
    DEFAULT_ENDPOINT,
    ENV_URL,
    generate as real_generate,
    probe_endpoint,
)
from sparklang.spark_coder.tools_loop import (
    find_bootstrap,
    tool_loop_complete,
)
from sparklang.spark_coder.train import (
    prove_coding,
    train_spark_coder,
)

DEFAULT_BC = "docs/examples/spark-train-step.sparkbc"
DEFAULT_DATA = "examples/fixtures/coder/dataset.jsonl"
DEFAULT_OUT = "models/spark-coder"

EXIT_NO_WEIGHTS = 2
EXIT_ENDPOINT_DOWN = 3


def _cmd_train(args: argparse.Namespace) -> int:
    """Train reference TinyCoder weights (pipeline proof)."""
    result = train_spark_coder(
        sparkbc=args.sparkbc,
        dataset=args.dataset,
        out_dir=args.out,
        outer=args.outer,
        inner=args.inner,
        lr=args.lr,
        also_factory_step=not args.skip_factory_step,
        device=args.device,
        scale=args.scale,
    )
    print(json.dumps(result, indent=2))
    return 0 if result.get("trained") else 1


def _cmd_generate(args: argparse.Namespace) -> int:
    """Generate code — self-hosted 30B endpoint by default."""
    if args.engine == "reference":
        return _generate_reference(args)
    out = real_generate(
        args.prompt,
        url=args.url,
        max_tokens=args.max_new,
    )
    print(json.dumps(out, indent=2))
    if not out.get("ok"):
        return EXIT_ENDPOINT_DOWN
    return 0


def _generate_reference(args: argparse.Namespace) -> int:
    """Greedy generate from in-repo reference weights."""
    weights = Path(args.weights)
    if not weights.is_file():
        print(
            json.dumps(
                {
                    "ok": False,
                    "error": "weights missing",
                    "path": str(weights),
                    "hint": "run: spark-code train",
                }
            )
        )
        return EXIT_NO_WEIGHTS
    model = TinyCoder.from_weights(weights)
    out = model.generate(args.prompt, max_new=args.max_new)
    out["engine"] = "reference-tinycoder"
    print(json.dumps(out, indent=2))
    return 0


def _cmd_prove(args: argparse.Namespace) -> int:
    """Prove next-byte coding fixtures (reference pipeline)."""
    fixtures = json.loads(
        Path(args.fixtures).read_text(encoding="utf-8")
    )
    result = prove_coding(args.weights, fixtures)
    print(json.dumps(result, indent=2))
    need = float(args.min_acc)
    ok = (
        result["accuracy"] >= need
        and str(result.get("trained")).lower()
        in ("true", "1", "yes")
    )
    return 0 if ok else 1


def _cmd_tool_loop(args: argparse.Namespace) -> int:
    """Reference model + compile verify on candidate .spark files."""
    weights = Path(args.weights)
    if not weights.is_file():
        print(
            json.dumps(
                {
                    "ok": False,
                    "error": "weights missing",
                    "path": str(weights),
                }
            )
        )
        return EXIT_NO_WEIGHTS
    model = TinyCoder.from_weights(weights)
    cands = [Path(p) for p in args.candidate]
    boot = find_bootstrap(ROOT)
    if args.bootstrap:
        boot = Path(args.bootstrap)
    result = tool_loop_complete(
        model,
        task=args.task,
        candidate_sources=cands,
        work_dir=Path(args.work),
        bootstrap=boot,
    )
    print(json.dumps(result, indent=2))
    return 0 if result.get("ok") else 1


def _cmd_status(args: argparse.Namespace) -> int:
    """Show product coder endpoint + reference weights status."""
    probe = probe_endpoint(args.url)
    weights = Path(args.weights)
    ref: dict[str, object] = {
        "path": str(weights),
        "present": weights.is_file(),
    }
    if weights.is_file():
        model = TinyCoder.from_weights(weights)
        ref["trained"] = model.meta.get("trained")
        ref["arch"] = model.arch_json()
    out = {
        "ok": True,
        "product_coder": {
            "engine": "self-hosted-30b",
            "endpoint": probe.get("endpoint", args.url),
            "serving": bool(probe.get("ok")),
            "model": probe.get("model", ""),
            "error": probe.get("error"),
            "env_override": ENV_URL,
        },
        "reference_trainer": ref,
        "prefer_device": "rtx-5090",
        "never": "rtx-pro-6000",
    }
    print(json.dumps(out, indent=2))
    if not probe.get("ok") and not weights.is_file():
        return EXIT_NO_WEIGHTS
    return 0


def main(argv: list[str] | None = None) -> int:
    """CLI entry for spark-code."""
    ap = argparse.ArgumentParser(
        prog="spark-code",
        description=(
            "Spark coding assistant. Product coder is the "
            "self-hosted Qwen3-Coder-30B endpoint (default "
            f"{DEFAULT_ENDPOINT}, env {ENV_URL}); offline, no API "
            "keys. In-repo TinyCoder is the reference trainer for "
            "the training pipeline. Prefer RTX 5090; never 6000."
        ),
    )
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_tr = sub.add_parser(
        "train",
        help="train reference TinyCoder (pipeline proof)",
    )
    p_tr.add_argument("--sparkbc", default=DEFAULT_BC)
    p_tr.add_argument("--dataset", default=DEFAULT_DATA)
    p_tr.add_argument("--out", default=DEFAULT_OUT)
    p_tr.add_argument("--outer", type=int, default=6)
    p_tr.add_argument("--inner", type=int, default=8)
    p_tr.add_argument("--lr", type=float, default=0.12)
    p_tr.add_argument(
        "--scale",
        default="tiny",
        choices=("tiny", "large"),
        help="reference trainer config: tiny=CI/default dims; "
        "large=opt-in dim64/n_layer4",
    )
    p_tr.add_argument(
        "--device",
        default="auto",
        choices=("auto", "cpu", "5090"),
        help="auto prefers RTX 5090; never 6000",
    )
    p_tr.add_argument(
        "--skip-factory-step",
        action="store_true",
        help="skip apply_sgd_step factory companion",
    )
    p_tr.set_defaults(func=_cmd_train)

    p_gen = sub.add_parser(
        "generate",
        help="generate code (self-hosted 30B endpoint by default)",
    )
    p_gen.add_argument(
        "--engine",
        default="endpoint",
        choices=("endpoint", "reference"),
        help="endpoint=self-hosted 30B (default); "
        "reference=in-repo TinyCoder weights",
    )
    p_gen.add_argument(
        "--url",
        default="",
        help=f"coder endpoint URL (env {ENV_URL}; "
        f"default {DEFAULT_ENDPOINT})",
    )
    p_gen.add_argument(
        "--weights",
        default=str(Path(DEFAULT_OUT) / "weights.safetensors"),
        help="reference engine weights path",
    )
    p_gen.add_argument("--prompt", required=True)
    p_gen.add_argument("--max-new", type=int, default=512)
    p_gen.set_defaults(func=_cmd_generate)

    p_pr = sub.add_parser(
        "prove",
        help="reference fixture next-byte prove",
    )
    p_pr.add_argument(
        "--weights",
        default=str(Path(DEFAULT_OUT) / "weights.safetensors"),
    )
    p_pr.add_argument(
        "--fixtures",
        default="examples/fixtures/coder/prove.json",
    )
    p_pr.add_argument("--min-acc", type=float, default=0.5)
    p_pr.set_defaults(func=_cmd_prove)

    p_tl = sub.add_parser(
        "tool-loop", help="rank candidates + compile"
    )
    p_tl.add_argument(
        "--weights",
        default=str(Path(DEFAULT_OUT) / "weights.safetensors"),
    )
    p_tl.add_argument("--task", required=True)
    p_tl.add_argument(
        "--candidate",
        action="append",
        required=True,
        help="candidate .spark path (repeatable)",
    )
    p_tl.add_argument("--work", default="out/spark-coder/tool-loop")
    p_tl.add_argument("--bootstrap", default="")
    p_tl.set_defaults(func=_cmd_tool_loop)

    p_st = sub.add_parser(
        "status",
        help="product coder endpoint + reference weights status",
    )
    p_st.add_argument(
        "--url",
        default="",
        help=f"coder endpoint URL (env {ENV_URL}; "
        f"default {DEFAULT_ENDPOINT})",
    )
    p_st.add_argument(
        "--weights",
        default=str(Path(DEFAULT_OUT) / "weights.safetensors"),
    )
    p_st.set_defaults(func=_cmd_status)

    args = ap.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
