"""``python3 -m spark_bc_gui`` entry (tools/ on PYTHONPATH)."""

from __future__ import annotations

import sys
from pathlib import Path

# Allow `python3 tools/spark-bc-gui/__main__.py` and pack layout.
_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from spark_bc_gui.app import main  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main())
