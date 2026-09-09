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
            "KNOWLEDGE.md",
            "knowledge/LLM_TRANSFORMERS.md",
            "knowledge/TRAINING.md",
            "knowledge/INFERENCE.md",
            "knowledge/MULTIMODAL.md",
            "knowledge/AGENTS_TOOLS.md",
            "knowledge/EVAL_HONESTY.md",
            "knowledge/DECOMPILE_RE.md",
            "knowledge/SAFETY_LIMITS.md",
            "MODEL_ASPECTS.md",
            "VOICE.md",
            "DIAGRAMS.md",
            "COMPILE.md",
            "DECOMPILE.md",
            "DECOMPILE_COMPETE.md",
            "research/LLM_DECOMPILE.md",
            "BUILD_MODELS.md",
            "TRAIN_LOOP.md",
            "ARCHITECTURE.md",
            "WEIGHT_GALLERY.md",
            "ATTENTION_FORWARD.md",
            "SERVE.md",
            "EVAL.md",
            "SPARKBC_MAKE.md",
            "TOOLS_HELPERS.md",
            "CI_PAGES.md",
            "TOKENIZER.md",
            "SPARK_BC.md",
            "SPARK_BUILDER.md",
        ):
            path = ROOT / "docs" / name
            self.assertTrue(path.is_file(), msg=name)

    def test_rewrite_keeps_docs_images(self) -> None:
        """Markdown images under images/ map to /docs/images/."""
        from tools.md_to_doc_html import rewrite_md_links

        out = rewrite_md_links(
            "![Ears](images/diagram-sense-ears.svg)\n"
            "See [VOICE.md](VOICE.md)\n"
        )
        self.assertIn(
            "![Ears](/docs/images/diagram-sense-ears.svg)",
            out,
        )
        self.assertIn("[VOICE.md](/docs/voice.html)", out)
        self.assertNotIn("!`", out)

    def test_model_aspect_svgs_exist(self) -> None:
        """L-lane sensory diagrams are present under docs/images/."""
        for name in (
            "diagram-ears-brain-voice.svg",
            "diagram-behavior-tool-loop.svg",
            "diagram-agentic-sensory-loop.svg",
            "diagram-sense-ears.svg",
            "diagram-sense-eyes.svg",
            "diagram-sense-speaking.svg",
            "diagram-sense-thinking.svg",
            "diagram-sense-behaviors.svg",
            "diagram-spark-vs-external-stacks.svg",
        ):
            path = ROOT / "docs" / "images" / name
            self.assertTrue(path.is_file(), msg=name)

    def test_knowledge_svgs_exist(self) -> None:
        """Knowledge-hive original diagrams under docs/images/."""
        for name in (
            "diagram-knowledge-transformer.svg",
            "diagram-knowledge-train-stack.svg",
            "diagram-knowledge-inference.svg",
            "diagram-knowledge-agents.svg",
            "diagram-knowledge-multimodal.svg",
            "diagram-knowledge-recompile.svg",
        ):
            path = ROOT / "docs" / "images" / name
            self.assertTrue(path.is_file(), msg=name)


    def test_primary_nav_has_subcategories(self) -> None:
        """Hive/Forge/Bench menus expose labeled subgroups."""
        import sys

        tools = str(ROOT / "tools")
        if tools not in sys.path:
            sys.path.insert(0, tools)
        import site_primary_nav as nav

        html = nav.render_primary_nav_inner()
        for label in (
            "Foundations",
            "Systems",
            "Safety / Eval",
            "RE",
            "Senses",
            "Models",
            "Train",
            "Language",
            "Runtime",
            "Ops",
        ):
            self.assertIn(label, html, msg=label)
        self.assertIn('class="nav-sub__label"', html)
        sample = (
            ROOT / "website" / "docs" / "knowledge.html"
        ).read_text(encoding="utf-8")
        self.assertIn("nav-sub__label", sample)
        self.assertIn("Foundations", sample)

    def test_knowledge_hub_grouped(self) -> None:
        """Knowledge markdown uses subcategory section headings."""
        text = (ROOT / "docs" / "KNOWLEDGE.md").read_text(
            encoding="utf-8"
        )
        for heading in (
            "## Foundations",
            "## Systems",
            "## Safety / Eval",
            "## RE",
        ):
            self.assertIn(heading, text, msg=heading)

    def test_safety_has_limit_guardrail_grounding(self) -> None:
        """Safety page nests Model limits / Guardrails / Grounding."""
        text = (
            ROOT / "docs" / "knowledge" / "SAFETY_LIMITS.md"
        ).read_text(encoding="utf-8")
        for heading in (
            "## Model limits",
            "### Hallucination",
            "## Guardrails",
            "## Grounding",
        ):
            self.assertIn(heading, text, msg=heading)


if __name__ == "__main__":
    unittest.main()
