#!/usr/bin/env python3
"""spark-weights — catalog / view / play Spark stub weights.

Supports tiny through xl profiles. Opt-in 5090 for XL generate;
never the voice 6000. No frontier-parity claim.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT / "python") not in sys.path:
    sys.path.insert(0, str(ROOT / "python"))

from sparklang.model_lab import weight_gallery as wg


def _print(payload: object) -> None:
    json.dump(payload, sys.stdout, indent=2)
    sys.stdout.write("\n")


def main(argv: list[str] | None = None) -> int:
    """CLI entry for weight gallery."""
    p = argparse.ArgumentParser(prog="spark-weights")
    sub = p.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("catalog", help="list kinds + on-disk files")
    c.add_argument("--root", default=None)

    i = sub.add_parser("inspect", help="list tensors in a file")
    i.add_argument("weights")

    s = sub.add_parser("stats", help="CPU histogram / norms")
    s.add_argument("weights")
    s.add_argument("--name", default=None, help="one tensor")
    s.add_argument("--bins", type=int, default=16)

    d = sub.add_parser("diff", help="compare two weight files")
    d.add_argument("a")
    d.add_argument("b")

    pl = sub.add_parser("play", help="tiny CPU forward/predict")
    pl.add_argument("weights")
    pl.add_argument("--prompt", default="hi")

    g = sub.add_parser(
        "generate",
        help="emit init weights for a size profile",
    )
    g.add_argument(
        "profile",
        choices=sorted(wg.PROFILES.keys()),
        help="tiny|scale|large|xl",
    )
    g.add_argument(
        "--out",
        default=None,
        help="dest safetensors (default out/gallery/<profile>/)",
    )
    g.add_argument(
        "--sparkbc",
        default="docs/examples/spark-train-step.sparkbc",
    )
    g.add_argument(
        "--5090",
        dest="prefer_5090",
        action="store_true",
        help="prefer RTX 5090 (never 6000); default for xl",
    )
    g.add_argument(
        "--cpu",
        action="store_true",
        help="force CPU even for xl",
    )

    w = sub.add_parser(
        "write-catalog-json",
        help="write website gallery catalog JSON",
    )
    w.add_argument(
        "--out",
        default="website/docs/examples/weight-gallery-catalog.json",
    )

    e = sub.add_parser("explain", help="plain-English role notes")
    e.add_argument(
        "role",
        nargs="?",
        default=None,
        help="embed|lm_head|norm|attn|mlp|other",
    )

    args = p.parse_args(argv)

    if args.cmd == "catalog":
        _print(wg.catalog(args.root))
        return 0
    if args.cmd == "inspect":
        _print(wg.inspect_weights(args.weights))
        return 0
    if args.cmd == "stats":
        _print(
            wg.tensor_stats(
                args.weights,
                name=args.name,
                bins=args.bins,
            )
        )
        return 0
    if args.cmd == "diff":
        _print(wg.compare_weights(args.a, args.b))
        return 0
    if args.cmd == "play":
        _print(wg.play_forward(args.weights, prompt=args.prompt))
        return 0
    if args.cmd == "generate":
        dest = args.out
        if not dest:
            dest = "out/gallery/%s/weights.safetensors" % args.profile
        prefer = None
        if args.cpu:
            prefer = False
        elif args.prefer_5090:
            prefer = True
        _print(
            wg.generate_profile(
                args.profile,
                dest,
                sparkbc=args.sparkbc,
                prefer_5090=prefer,
            )
        )
        return 0
    if args.cmd == "write-catalog-json":
        path = wg.write_catalog_json(args.out)
        _print({"wrote": str(path)})
        return 0
    if args.cmd == "explain":
        if args.role:
            text = wg.ROLE_EXPLAINERS.get(args.role)
            if not text:
                print("unknown role", args.role, file=sys.stderr)
                return 2
            _print({args.role: text})
        else:
            _print(wg.ROLE_EXPLAINERS)
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
