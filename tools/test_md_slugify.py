"""Unit tests for GitHub-compatible slugify() in md_to_doc_html.

Anchor ids on generated docs pages must match the fragments authors
write in docs/*.md, and those fragments follow GitHub's anchor
algorithm (github-slugger): punctuation removed, each whitespace
char becomes one dash, no run-collapsing — "A — b" → "a--b".
"""

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


# Real headings from docs/*.md whose in-page/cross-doc links were
# broken by whitespace-run collapsing (audit 2026-09-10).
GITHUB_PARITY_CASES = {
    # docs/SPARK_BUILDER.md — link #published-files--sha256
    "Published files — sha256": "published-files--sha256",
    # docs/LANGUAGE.md — linked from NATIVE_NETWORK_WEB.md
    "Browser / MITM (language SoT)": "browser--mitm-language-sot",
    # docs/MODEL_ASPECTS.md — in-page TOC links
    "Ears — STT / audio in": "ears--stt--audio-in",
    "Eyes — vision / image in": "eyes--vision--image-in",
    "Speaking — TTS / audio out": "speaking--tts--audio-out",
    "Thinking — LLM forward / generation":
        "thinking--llm-forward--generation",
    "Behaviors — policies, tools, turn-taking":
        "behaviors--policies-tools-turn-taking",
    "System diagram — ears → brain → voice ↔ tools":
        "system-diagram--ears--brain--voice--tools",
    "Status table (honest — engineering aspects)":
        "status-table-honest--engineering-aspects",
}

# Headings whose ids must NOT change under the parity fix.
STABLE_CASES = {
    "Network": "network",
    "Programs": "programs",
    "Implementation tiers": "implementation-tiers",
    "How to lab (15 minutes)": "how-to-lab-15-minutes",
    "Comparison — Spark local SoT vs OpenBin Ask / production "
    "voice stacks":
        "comparison--spark-local-sot-vs-openbin-ask--production-"
        "voice-stacks",
}


class TestSlugifyGithubParity(unittest.TestCase):
    """slugify() matches GitHub's rendered anchor ids."""

    def test_github_parity_cases(self) -> None:
        """Em-dash / slash headings keep GitHub's double dashes."""
        mod = _load_md_to_doc()
        for heading, want in GITHUB_PARITY_CASES.items():
            with self.subTest(heading=heading):
                self.assertEqual(mod.slugify(heading), want)

    def test_stable_cases_unchanged(self) -> None:
        """Plain headings keep their existing single-dash ids."""
        mod = _load_md_to_doc()
        for heading, want in STABLE_CASES.items():
            with self.subTest(heading=heading):
                self.assertEqual(mod.slugify(heading), want)

    def test_strips_html_and_unescapes_entities(self) -> None:
        """Inline markup/entities from rendered headings are removed."""
        mod = _load_md_to_doc()
        inner = "<code>use &lt;id&gt;</code> / <code>model &lt;id&gt;</code>"
        self.assertEqual(mod.slugify(inner), "use-id--model-id")

    def test_underscore_is_word_char(self) -> None:
        """GitHub keeps underscores; they are not folded to dashes."""
        mod = _load_md_to_doc()
        self.assertEqual(mod.slugify("spark_bc isa"), "spark_bc-isa")


if __name__ == "__main__":
    unittest.main()
