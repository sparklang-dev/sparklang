#!/usr/bin/env python3
"""Render docs/*.md into website/docs/*.html using the public doc shell.

Does not invent content — markdown body only, plus the fixed nav/footer.
"""
from __future__ import annotations

import argparse
import html
import re
from pathlib import Path

import markdown

ROOT = Path(__file__).resolve().parents[1]
CSS_V = "knowledge0909"

DOC_NAV = """\
      <nav class="doc__nav" aria-label="Docs">
        <a href="/learn/">Learn</a>
        <a href="/docs/knowledge.html"{kh}>Knowledge hive</a>
        <a href="/docs/factory.html"{fy}>Factory hub</a>
        <a href="/docs/model-aspects.html"{ma}>Model aspects</a>
        <a href="/docs/voice.html"{vo}>Voice</a>
        <a href="/docs/voice-ask.html"{va}>Voice ask</a>
        <a href="/docs/voice-easy.html"{ve}>Voice easy</a>
        <a href="/docs/diagrams.html"{dg}>Diagrams</a>
        <a href="/docs/spark-builder.html"{bc}>Builder</a>
        <a href="/docs/compile.html"{cp}>Compile</a>
        <a href="/docs/decompile.html"{dc}>Decompile</a>
        <a href="/docs/decompile-compete.html"{dcc}>Compete</a>
        <a href="/docs/llm-decompile.html"{rd}>LLM research</a>
        <a href="/docs/spark-bc.html"{isa}>Opcodes / ISA</a>
        <a href="/docs/build-models.html"{bm}>Build models</a>
        <a href="/docs/train-loop.html"{tl}>Train loop</a>
        <a href="/docs/spark-coder.html"{sc}>Spark coder</a>
        <a href="/docs/weight-gallery.html"{wg}>Weight gallery</a>
        <a href="/docs/architecture.html"{ar}>Architecture</a>
        <a href="/docs/tokenizer.html"{tk}>Tokenizer</a>
        <a href="/docs/serve.html"{sv}>Serve</a>
        <a href="/docs/eval.html"{ev}>Eval</a>
        <a href="/docs/sparkbc-make.html"{mk}>Make targets</a>
        <a href="/docs/tools-helpers.html"{th}>Tools & helpers</a>
        <a href="/docs/methods-openbin.html"{mo}>Methods vs OpenBin</a>
        <a href="/docs/ci-pages.html"{ci}>CI / Pages</a>
        <a href="/docs/adoption-bar.html"{ab}>Adoption bar</a>
        <a href="/docs/language.html">Language</a>
        <a href="/docs/programming-guide.html">Programming guide</a>
        <a href="/downloads.html">Downloads</a>
      </nav>"""

HEADER = """\
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{title} — Spark</title>
    <meta name="description" content="{description}" />
    <link rel="icon" href="/favicon.svg" type="image/svg+xml" />
    <link rel="shortcut icon" href="/favicon.svg" />
    <link rel="stylesheet" href="/css/tokens.css?v={css_v}" />
    <link rel="stylesheet" href="/css/site.css?v={css_v}" />
  </head>
  <body class="doc-page">
    <header class="site-header">
      <div class="shell header-inner">
        <a class="site-brand" href="/" aria-label="Spark home">
          <svg class="mark" viewBox="0 0 32 32" aria-hidden="true">
            <path d="M18.2 4.5 9.5 17.2h5.1l-1.4 10.3 9.4-14.2h-5.4L18.2 4.5Z" fill="currentColor" />
          </svg>
          Spark
        </a>
        <button class="nav-toggle" type="button" aria-expanded="false" aria-controls="site-nav" aria-label="Open menu">
          <span class="nav-toggle__bar"></span>
          <span class="nav-toggle__bar"></span>
          <span class="nav-toggle__bar"></span>
        </button>
        <div class="header-nav-wrap">
          <nav class="site-nav" id="site-nav" aria-label="Primary">
            <ul class="nav-primary">
              <li><a href="/workflow.html">Loop</a></li>
              <li><a href="/learn/">Learn</a></li>
              <li><a href="/docs/knowledge.html">Knowledge</a></li>
              <li><a href="/docs/language.html">Docs</a></li>
              <li><a href="/docs/factory.html">Factory</a></li>
              <li><a href="/downloads.html">Download</a></li>
              <li class="nav-more">
                <button type="button" class="nav-more__toggle" aria-expanded="false" aria-haspopup="true">Hive</button>
                <ul class="nav-more__menu" hidden>
                  <li><a href="/docs/knowledge.html">Knowledge hub</a></li>
                  <li><a href="/docs/knowledge-llm.html">LLMs & transformers</a></li>
                  <li><a href="/docs/knowledge-training.html">Training</a></li>
                  <li><a href="/docs/knowledge-inference.html">Inference</a></li>
                  <li><a href="/docs/knowledge-multimodal.html">Multimodal</a></li>
                  <li><a href="/docs/knowledge-agents.html">Agents & tools</a></li>
                  <li><a href="/docs/knowledge-eval.html">Eval honesty</a></li>
                  <li><a href="/docs/knowledge-decompile.html">Decompile + RE</a></li>
                  <li><a href="/docs/knowledge-safety.html">Safety & limits</a></li>
                  <li><a href="/docs/llm-decompile.html">LLM decompile research</a></li>
                </ul>
              </li>
              <li class="nav-more">
                <button type="button" class="nav-more__toggle" aria-expanded="false" aria-haspopup="true">Forge</button>
                <ul class="nav-more__menu" hidden>
                  <li><a href="/docs/model-aspects.html">Model aspects</a></li>
                  <li><a href="/docs/diagrams.html">Diagrams</a></li>
                  <li><a href="/docs/spark-builder.html">Builder</a></li>
                  <li><a href="/docs/build-models.html">Build models</a></li>
                  <li><a href="/docs/model-training.html">Model training</a></li>
                  <li><a href="/docs/train-loop.html">Train loop</a></li>
                  <li><a href="/docs/spark-coder.html">Spark coder</a></li>
                  <li><a href="/docs/weight-gallery.html">Weight gallery</a></li>
                  <li><a href="/docs/ai-models.html">AI models</a></li>
                  <li><a href="/docs/voice.html">Voice / STT / TTS</a></li>
                  <li><a href="/docs/voice-ask.html">Voice ask</a></li>
                </ul>
              </li>
              <li class="nav-more">
                <button type="button" class="nav-more__toggle" aria-expanded="false" aria-haspopup="true">Bench</button>
                <ul class="nav-more__menu" hidden>
                  <li><a href="/docs/compile.html">Compile</a></li>
                  <li><a href="/docs/decompile.html">Decompile</a></li>
                  <li><a href="/docs/decompile-compete.html">Decompile compete</a></li>
                  <li><a href="/docs/programming-guide.html">Programming guide</a></li>
                  <li><a href="/docs/ide.html">IDE</a></li>
                  <li><a href="/ide-web.html">IDE web shell</a></li>
                  <li><a href="/docs/native-network-web.html">Network + web</a></li>
                  <li><a href="/docs/serve.html">Serve</a></li>
                  <li><a href="/docs/tools-helpers.html">Tools & helpers</a></li>
                  <li><a href="/about.html">About</a></li>
                </ul>
              </li>
            </ul>
            <a href="/playground.html" class="nav-cta">Try</a>
          </nav>
        </div>
      </div>
    </header>

    <div class="shell doc-layout">
      <aside class="doc-sidebar" aria-label="Table of contents">
        <p class="doc-sidebar__title">On this page</p>
        <nav id="doc-toc-list"></nav>
      </aside>
      <main class="doc-main">
"""

FOOTER = """\
      </main>
    </div>

    <footer class="site-footer">
      <div class="shell footer-inner">
        <span>Spark programming language</span>
        <nav class="footer-nav" aria-label="Footer">
          <a href="/workflow.html">Loop</a>
          <a href="/learn/">Learn</a>
          <a href="/docs/knowledge.html">Knowledge</a>
          <a href="/docs/language.html">Reference</a>
          <a href="/downloads.html">Downloads</a>
          <a href="/playground.html">Playground</a>
        </nav>
      </div>
    </footer>
    <script src="/js/site.js"></script>
  </body>
</html>
"""

SELF_HOST_CALLOUT = """\
        <div class="doc__callout" role="note">
          <p><strong>For contributors</strong> — you don't need this page to use Spark.
          Install from <a href="/downloads.html">Downloads</a> and start with
          <a href="/learn/getting-started.html">Getting started</a>.</p>
        </div>
"""

MD_LINK_MAP = {
    "LANGUAGE.md": "/docs/language.html",
    "ADOPTION_BAR.md": "/docs/adoption-bar.html",
    "ROADMAP.md": "/docs/roadmap.html",
    "RELEASE.md": "/docs/release.html",
    "AI_MODELS.md": "/docs/ai-models.html",
    "ASK_LIVE.md": "/docs/ai-models.html#live-gateway-integration-wired-today",
    "MODEL_ANALYSIS.md": "/docs/ai-models.html",
    "MODEL_TRAINING.md": "/docs/model-training.html",
    "AI_PLAYBOOKS.md": "/learn/build-model.html",
    "ENCRYPT_GATEWAY.md": "/docs/ai-models.html",
    "IDE.md": "/docs/ide.html",
    "VOICE.md": "/docs/voice.html",
    "VOICE_ASK.md": "/docs/voice-ask.html",
    "VOICE_EASY.md": "/docs/voice-easy.html",
    "MODEL_ASPECTS.md": "/docs/model-aspects.html",
    "SELF_HOST.md": "/docs/self-host.html",
    "SPARK_BC.md": "/docs/spark-bc.html",
    "SPARK_BUILDER.md": "/docs/spark-builder.html",
    "NATIVE_NETWORK_WEB.md": "/docs/native-network-web.html",
    "TOKENIZER.md": "/docs/tokenizer.html",
    "FACTORY.md": "/docs/factory.html",
    "DIAGRAMS.md": "/docs/diagrams.html",
    "COMPILE.md": "/docs/compile.html",
    "DECOMPILE.md": "/docs/decompile.html",
    "DECOMPILE_COMPETE.md": "/docs/decompile-compete.html",
    "LLM_DECOMPILE.md": "/docs/llm-decompile.html",
    "BUILD_MODELS.md": "/docs/build-models.html",
    "TRAIN_LOOP.md": "/docs/train-loop.html",
    "SPARK_CODER.md": "/docs/spark-coder.html",
    "WEIGHT_GALLERY.md": "/docs/weight-gallery.html",
    "ARCHITECTURE.md": "/docs/architecture.html",
    "ATTENTION_FORWARD.md": "/docs/attention-forward.html",
    "SERVE.md": "/docs/serve.html",
    "EVAL.md": "/docs/eval.html",
    "SPARKBC_MAKE.md": "/docs/sparkbc-make.html",
    "TOOLS_HELPERS.md": "/docs/tools-helpers.html",
    "METHODS_OPENBIN.md": "/docs/methods-openbin.html",
    "CI_PAGES.md": "/docs/ci-pages.html",
    "MODEL_LAB.md": "/docs/model-training.html",
    "ABSTAIN_HEADS.md": "/docs/abstain-heads.html",
    "KNOWLEDGE.md": "/docs/knowledge.html",
    "LLM_TRANSFORMERS.md": "/docs/knowledge-llm.html",
    "TRAINING.md": "/docs/knowledge-training.html",
    "INFERENCE.md": "/docs/knowledge-inference.html",
    "MULTIMODAL.md": "/docs/knowledge-multimodal.html",
    "AGENTS_TOOLS.md": "/docs/knowledge-agents.html",
    "EVAL_HONESTY.md": "/docs/knowledge-eval.html",
    "DECOMPILE_RE.md": "/docs/knowledge-decompile.html",
    "SAFETY_LIMITS.md": "/docs/knowledge-safety.html",
}

# (current_key, md_name, html_name, title, description)
DOC_PAGES = [
    ("fy", "FACTORY.md", "factory.html", "Factory documentation hub",
     "Map of SparkLang SPARK_BC factory docs — compile through "
     "eval, serve, CI/Pages. Does not beat Claude."),
    ("kh", "KNOWLEDGE.md", "knowledge.html", "AI knowledge hive",
     "Engineer-grade AI knowledge hub — transformers, training, "
     "inference, agents, eval honesty. Does not beat Claude."),
    ("kh", "knowledge/LLM_TRANSFORMERS.md", "knowledge-llm.html",
     "LLMs & transformers",
     "Tokens, embeddings, attention, transformers — Spark-framed."),
    ("kh", "knowledge/TRAINING.md", "knowledge-training.html",
     "Training stack",
     "Pretrain, SFT, RLHF/RLAIF, LoRA/QLoRA, SGD/Adam — citations."),
    ("kh", "knowledge/INFERENCE.md", "knowledge-inference.html",
     "Inference",
     "Sampling, KV cache, quantization — GPTQ/AWQ/NF4."),
    ("kh", "knowledge/MULTIMODAL.md", "knowledge-multimodal.html",
     "Multimodal STT/TTS/vision",
     "Speech and vision I/O with honest Spark status."),
    ("kh", "knowledge/AGENTS_TOOLS.md", "knowledge-agents.html",
     "Agents and tools",
     "Tool loops, ReAct-style patterns, failure modes."),
    ("kh", "knowledge/EVAL_HONESTY.md", "knowledge-eval.html",
     "Eval honesty",
     "Benchmarks as instruments — never beat Claude."),
    ("kh", "knowledge/DECOMPILE_RE.md", "knowledge-decompile.html",
     "Decompile + LLM RE",
     "Recompile ≠ semantics; links llm-decompile research."),
    ("kh", "knowledge/SAFETY_LIMITS.md", "knowledge-safety.html",
     "Safety and limits",
     "Hallucination, abstain, Spark printed guardrails."),
    ("ma", "MODEL_ASPECTS.md", "model-aspects.html",
     "AI model aspects",
     "Behaviors, ears/STT, eyes/vision, speaking/TTS, thinking, "
     "memory, tools, train, eval, serve — honest status table."),
    ("vo", "VOICE.md", "voice.html", "Voice — STT / TTS / PSTN",
     "Spark listen/speak companions, dry stubs, gated live STT/TTS "
     "and PSTN. Not production telephony."),
    ("va", "VOICE_ASK.md", "voice-ask.html",
     "Voice ask — dump / binary Q&A",
     "STT → SPARK_BC dump context → TinyCoder → TTS. "
     "No OpenBin login. Tiny; does not beat Claude."),
("ve", "VOICE_EASY.md", "voice-easy.html",
     "Voice easy — train STT / TTS",
     "Piece-of-cake owned voice heads (tiny CI + large opt-in). "
     "Prefer 5090; never 6000. Not ElevenLabs overnight."),
    ("dg", "DIAGRAMS.md", "diagrams.html", "Factory diagrams",
     "How Spark tools and LLM assist relate — compile, decompile, "
     "train, serve, shadows. Deterministic SoT; never beat Claude."),
    ("ab", "ADOPTION_BAR.md", "adoption-bar.html", "Adoption bar",
     "SparkLang adoption checklist — done, next, won't."),
    ("", "ROADMAP.md", "roadmap.html", "Roadmap",
     "SparkLang roadmap — done, next, won't."),
    ("", "RELEASE.md", "release.html", "Release process",
     "How SparkLang versions and GitHub Releases are cut."),
    ("ide", "IDE.md", "ide.html", "IDE — language ops + GUI",
     "Spark language ide ops, tkinter Spark IDE GUI "
     "(browse/compile/ask/weights), and web shell demo."),
    ("", "CI_PAGES.md", "ci-pages.html", "CI + Cloudflare Pages",
     "Contributor CI gates and production Pages deploy how-to."),
    ("ai", "AI_MODELS.md", "ai-models.html", "AI models",
     "What SparkLang means for model train, analyze, compare, "
     "improve, plan, live ask, and embed/retrieve."),
    ("ai", "MODEL_TRAINING.md", "model-training.html", "Model training",
     "SparkLang model train / build — real jobs, dry fixtures, "
     "HTTP and local-yield backends."),
    ("bc", "SPARK_BUILDER.md", "spark-builder.html",
     "Builder — SPARK_BC factory",
     "Spark compiles Spark to SPARK_BC (TRAIN 0x26 / "
     "TRAIN_STATUS 0x27) and emits init weights. "
     "Emitting TRAIN is not a trained model."),
    ("cp", "COMPILE.md", "compile.html", "Compile — SPARK_BC",
     "Compile Spark to SPARK_BC via bootstrap, GAS wrappers, "
     "and sparkasm — engineer makefile map."),
    ("dc", "DECOMPILE.md", "decompile.html",
     "Decompile / inspect SPARK_BC",
     "Dump, inspect, and disassemble SPARK_BC and related "
     "binaries — hex mnemonics, not source recovery."),
    ("dcc", "DECOMPILE_COMPETE.md", "decompile-compete.html",
     "Decompile compete — measured scoreboard",
     "SPARK_BC parity matrix and measured scoreboard vs "
     "OpenBin / classic RE / LLM4Decompile — no fake beats-all."),
    ("rd", "research/LLM_DECOMPILE.md", "llm-decompile.html",
     "LLM decompile research",
     "Survey of LLM decompile tools vs Spark SPARK_BC "
     "deterministic dump — citations, limits, no beat Claude."),
    ("bm", "BUILD_MODELS.md", "build-models.html",
     "Build models — TRAIN / STEP",
     "TRAIN, STEP, ARTIFACT, weights, and checkpoints on CPU "
     "fixtures. Does not beat Claude."),
    ("tl", "TRAIN_LOOP.md", "train-loop.html",
     "Train loop — outer / inner SGD",
     "Multi-outer CPU SGD, fixtures, checkpoints, loss curves."),
    ("sc", "SPARK_CODER.md", "spark-coder.html",
     "Spark coder — owned TinyCoder",
     "In-repo TinyCoder layers + SGD on coding fixtures. "
     "Not HF/Claude. Never 6000; 5090 OK. Does not beat Claude."),
    ("wg", "WEIGHT_GALLERY.md", "weight-gallery.html",
     "Weight gallery — view / play / understand",
     "Catalog tiny through xl Spark stub weights; inspect, "
     "diff, play forward. Opt-in 5090 XL; never 6000."),
    ("ar", "ARCHITECTURE.md", "architecture.html",
     "Architecture pieces",
     "Embed, RMSNorm, lm_head, MLP/SwiGLU, attention honesty."),
    ("af", "ATTENTION_FORWARD.md", "attention-forward.html",
     "Attention / MLP / serve",
     "Honest status: init attn tensors, MLP0 serve forward, "
     "attention math planned — not beat Claude."),
    ("tk", "TOKENIZER.md", "tokenizer.html", "Tokenizer — BPE seed vocab",
     "From-nothing byte-level BPE seed vocab for Spark."),
    ("sv", "SERVE.md", "serve.html", "Serve forward + HTTP",
     "Tiny CPU SERVE forward; HTTP/API when G-lane merges."),
    ("ev", "EVAL.md", "eval.html", "Eval harness",
     "Frozen spark-eval probes + optional Claude baseline. "
     "Never claims beat Claude."),
    ("mk", "SPARKBC_MAKE.md", "sparkbc-make.html",
     "SPARK_BC makefile targets",
     "test-sparkbc, sparkbc-e2e, spark-sgd-proof, spark-eval, "
     "helpers, tools-test, sdk-pack, and related factory gates."),
    ("th", "TOOLS_HELPERS.md", "tools-helpers.html",
     "Tools & helpers",
     "K-lane helpers, shadows, and spark_kit — compile/run/inspect, "
     "shadow build, opcode sheet. Never beat Claude."),
("mo", "METHODS_OPENBIN.md", "methods-openbin.html",
     "Methods vs OpenBin",
     "What Spark adopted vs rejected from public OpenBin "
     "methods — local analyze loop, no clone. Never beat Claude."),
    ("isa", "SPARK_BC.md", "spark-bc.html", "SPARK_BC ISA",
     "Spark bytecode ISA — opcodes, pools, dry-run contracts."),
    ("", "LANGUAGE.md", "language.html", "Language reference",
     "SparkLang statement reference — ask, classify, embed, "
     "retrieve, shell, voice, pipeline, and more."),
    ("", "PROGRAMMING_GUIDE.md", "programming-guide.html",
     "Programming guide",
     "How to write and run SparkLang programs — dry-run, "
     "live flags, host embed, and first programs."),
    ("sh", "SELF_HOST.md", "self-host.html", "Contributor internals",
     "Spark self-host path: A + B bootstrap + C assembler, "
     "SPARK_BC stages, and evidence gates."),
    ("nn", "NATIVE_NETWORK_WEB.md", "native-network-web.html",
     "Native network + web",
     "Network/web ops — de-emphasized vs http get/post roadmap."),
]


def slugify(text: str) -> str:
    text = re.sub(r"<[^>]+>", "", text)
    text = html.unescape(text).strip().lower()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_]+", "-", text)
    return text.strip("-")


def rewrite_md_links(src: str) -> str:
    def repl(m: re.Match[str]) -> str:
        label, target = m.group(1), m.group(2)
        base = target.split("#", 1)[0]
        frag = ""
        if "#" in target:
            frag = "#" + target.split("#", 1)[1]
        name = Path(base).name if base else ""
        mapped = MD_LINK_MAP.get(name)
        if mapped:
            return f"[{label}]({mapped}{frag})"
        if base.startswith("http") or base.startswith("/"):
            return m.group(0)
        # Keep repo-relative paths as inline code (not published as MD).
        if name.endswith(".md") or "/" in base:
            return f"`{target}`"
        return m.group(0)

    return re.sub(r"\[([^\]]+)\]\(([^)]+)\)", repl, src)


def decorate_html(body: str) -> str:
    body = body.replace("<table>", '<div class="doc__table-wrap"><table class="doc__table">')
    body = body.replace("</table>", "</table></div>")
    body = body.replace("<ul>", '<ul class="doc__ul">')
    body = body.replace("<ol>", '<ol class="doc__ol">')
    body = body.replace("<hr />", '<hr class="doc__hr" />')
    body = body.replace("<hr>", '<hr class="doc__hr" />')
    body = body.replace("<img ", '<img class="doc__img" ')
    def fence(m: re.Match[str]) -> str:
        lang = m.group(1) or ""
        if lang:
            return f'<pre class="doc__pre"><code class="language-{lang}">'
        return '<pre class="doc__pre"><code>'

    body = re.sub(r"<pre><code(?: class=\"language-([^\"]+)\")?>", fence, body)

    def mermaid_block(m: re.Match[str]) -> str:
        """Turn mermaid fences into renderable <pre class=mermaid>."""
        raw = html.unescape(m.group(1)).strip("\n")
        return f'<pre class="mermaid">{raw}</pre>'

    body = re.sub(
        r'<pre class="doc__pre"><code class="language-mermaid">'
        r"(.*?)</code></pre>",
        mermaid_block,
        body,
        flags=re.S,
    )
    body = re.sub(r"<code>([^<]*)</code>", r'<code class="inline-code">\1</code>', body)

    def heading(m: re.Match[str]) -> str:
        level, attrs, inner = m.group(1), m.group(2) or "", m.group(3)
        if 'id="' in attrs:
            return m.group(0)
        sid = slugify(inner)
        return f'<h{level} id="{sid}"{attrs}>{inner}</h{level}>'

    body = re.sub(r"<h([1-6])([^>]*)>(.*?)</h\1>", heading, body, flags=re.S)
    # Indent article children for readability.
    indented = "\n".join(
        ("        " + line if line.strip() else line) for line in body.strip().splitlines()
    )
    return indented


def render(md_path: Path, out_path: Path, title: str, description: str, current: str) -> None:
    raw = md_path.read_text(encoding="utf-8")
    raw = rewrite_md_links(raw)
    body = markdown.markdown(
        raw,
        extensions=["tables", "fenced_code", "sane_lists"],
    )
    body = decorate_html(body)
    keys = (
        "ab", "ai", "nn", "ide", "sh", "bc", "cp", "dc", "dcc", "rd",
        "bm", "af", "mk", "th", "mo", "isa", "fy", "kh", "dg", "tl",
        "sc", "wg", "ar", "tk", "sv", "ev", "ci", "ma", "vo", "va",
        "ve",
    )
    nav_kwargs = {
        k: (' aria-current="page"' if current == k else "") for k in keys
    }
    nav = DOC_NAV.format(**nav_kwargs)
    prefix = ""
    if current == "sh":
        prefix = SELF_HOST_CALLOUT
    page = (
        HEADER.format(
            title=html.escape(title),
            description=html.escape(description),
            css_v=CSS_V,
        )
        + nav
        + '      <article class="doc__body">\n'
        + prefix
        + indented_or(body)
        + "\n      </article>\n"
        + FOOTER
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(page, encoding="utf-8")
    print(f"wrote {out_path.relative_to(ROOT)}")


def indented_or(body: str) -> str:
    return body


def expected_html_paths() -> list[Path]:
    """Website HTML paths produced by --all-stale."""
    out = ROOT / "website" / "docs"
    return [out / html_name for _, _, html_name, _, _ in DOC_PAGES]


def check_docs_links() -> int:
    """Fail if expected docs HTML or nav href targets are missing."""
    missing: list[str] = []
    for path in expected_html_paths():
        if not path.is_file():
            missing.append(str(path.relative_to(ROOT)))
    nav_hrefs = re.findall(r'href="(/docs/[^"]+\.html)"', DOC_NAV)
    more_hrefs = re.findall(r'href="(/docs/[^"]+\.html)"', HEADER)
    for href in sorted(set(nav_hrefs + more_hrefs)):
        disk = ROOT / "website" / href.lstrip("/")
        if not disk.is_file():
            missing.append(href)
    if missing:
        print("docs link-check FAILED:")
        for m in missing:
            print(f"  missing {m}")
        return 1
    print(
        "docs link-check OK "
        f"({len(expected_html_paths())} pages, "
        f"{len(set(nav_hrefs + more_hrefs))} nav hrefs)"
    )
    return 0


def main() -> int:
    """Regenerate website docs HTML and/or check nav targets."""
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--all-stale",
        action="store_true",
        help="Regenerate docs HTML including builder / SPARK_BC dump",
    )
    ap.add_argument(
        "--check",
        action="store_true",
        help="Verify expected website/docs HTML paths exist",
    )
    args = ap.parse_args()
    docs = ROOT / "docs"
    out = ROOT / "website" / "docs"
    if args.all_stale:
        for current, md_name, html_name, title, description in DOC_PAGES:
            render(
                docs / md_name,
                out / html_name,
                title,
                description,
                current,
            )
    if args.check:
        return check_docs_links()
    if not args.all_stale and not args.check:
        ap.print_help()
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
