"""CLI: ``python -m sparklang [--live] <file.spark|source>``."""

from __future__ import annotations

import argparse
import sys

from sparklang import SparkBinNotFound, run


def main(argv: list[str] | None = None) -> int:
    """Parse argv and run a Spark program; return exit code."""
    ap = argparse.ArgumentParser(
        prog="python -m sparklang",
        description=(
            "Host embed: run a .spark file or inline source "
            "(dry-run default)."
        ),
    )
    ap.add_argument(
        "program",
        help="Path to .spark, or inline source string",
    )
    ap.add_argument(
        "--live",
        action="store_true",
        help="Use ./spark --live (opt-in network/gateway)",
    )
    ap.add_argument(
        "--spark-bin",
        default=None,
        help="Path to spark ELF (else SPARK_BIN / discovery)",
    )
    args = ap.parse_args(argv)

    try:
        result = run(
            args.program,
            dry=not args.live,
            live=args.live,
            spark_bin=args.spark_bin,
        )
    except (SparkBinNotFound, FileNotFoundError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
