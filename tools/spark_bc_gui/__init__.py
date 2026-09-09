"""SparkLang SPARK_BC / IDE graphical shell (real tool paths)."""

from .core import (
    ask_over_dump,
    browse_opcodes,
    compile_spark,
    decompile_sparkbc,
    export_report_markdown,
    find_bootstrap,
    list_weight_files,
    play_tensor,
    run_helper,
    summarize_weights,
)

__all__ = [
    "ask_over_dump",
    "browse_opcodes",
    "compile_spark",
    "decompile_sparkbc",
    "export_report_markdown",
    "find_bootstrap",
    "list_weight_files",
    "play_tensor",
    "run_helper",
    "summarize_weights",
]
