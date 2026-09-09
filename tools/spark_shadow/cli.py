"""CLI re-export — prefer python -m spark_shadow."""

from __future__ import annotations

from spark_shadow.__main__ import main

if __name__ == "__main__":
    raise SystemExit(main())
