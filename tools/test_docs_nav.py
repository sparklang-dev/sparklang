"""Link-check for Spark factory docs HTML + nav hrefs."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _load_md_to_doc():
    path = ROOT / "tools" / "md_to_doc_html.py"
    spec = importlib.util.spec_from_file_location("md_to_doc_html", path)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class TestDocsNav(unittest.TestCase):
    """Factory docs pages must exist and match generator map."""

    def test_expected_pages_on_disk(self) -> None:
        """Every DOC_PAGES HTML file exists after regen."""
        mod = _load_md_to_doc()
        missing = [
            str(p.relative_to(ROOT))
            for p in mod.expected_html_paths()
            if not p.is_file()
        ]
        self.assertEqual(missing, [], msg=f"missing {missing}")

    def test_check_docs_links_ok(self) -> None:
        """Generator --check returns 0 when nav targets exist."""
        mod = _load_md_to_doc()
        self.assertEqual(mod.check_docs_links(), 0)

    def test_factory_md_sources_exist(self) -> None:
        """H-lane markdown sources are present under docs/."""
        for name in (
            "FACTORY.md",
            "DIAGRAMS.md",
            "COMPILE.md",
            "DECOMPILE.md",
            "research/LLM_DECOMPILE.md",
            "BUILD_MODELS.md",
            "TRAIN_LOOP.md",
            "ARCHITECTURE.md",
            "ATTENTION_FORWARD.md",
            "SERVE.md",
            "EVAL.md",
            "SPARKBC_MAKE.md",
            "CI_PAGES.md",
            "TOKENIZER.md",
            "SPARK_BC.md",
            "SPARK_BUILDER.md",
        ):
            path = ROOT / "docs" / name
            self.assertTrue(path.is_file(), msg=name)


if __name__ == "__main__":
    unittest.main()
