"""Spark project-loop analyze — local analysis folders from SPARK_BC.

Compile → dump → optional serve → report stub. No third-party upload.
Never RTX PRO 6000. Does not claim beat Claude.
"""

from spark_analyze.analyze import run_analyze

__all__ = ["run_analyze"]
