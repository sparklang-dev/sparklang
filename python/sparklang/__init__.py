"""SparkLang host embed — run ``.spark`` from Python.

Dry-run is the default (fixtures, no network). Opt into live with
``live=True`` / ``./spark --live``. JS and C FFI remain ``[next]``.
"""

from __future__ import annotations

from sparklang._runner import (
    RunResult,
    SparkBinNotFound,
    SparkRunError,
    find_spark,
    run,
)

__all__ = [
    "RunResult",
    "SparkBinNotFound",
    "SparkRunError",
    "find_spark",
    "run",
]

__version__ = "0.6.11"
