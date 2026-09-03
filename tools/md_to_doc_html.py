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
CSS_V = "bb4433f"

DOC_NAV = """\
      <nav class="doc__nav" aria-label="Docs">
        <a href="/learn/">Learn</a>
        <a href="/docs/adoption-bar.html"{ab}>Adoption bar</a>
        <a href="/docs/ai-models.html"{ai}>AI models</a>
        <a href="/docs/model-training.html"{ai}>Model training</a>
        <a href="/docs/native-network-web.html"{nn}>Network + web</a>
        <a href="/docs/programming-guide.html">Programming guide</a>
        <a href="/docs/language.html">Language reference</a>
        <a href="/docs/ide.html"{ide}>IDE</a>
        <a href="/docs/self-host.html"{sh}>Contributor internals</a>
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
              <li><a href="/learn/">Learn</a></li>
              <li><a href="/docs/language.html">Docs</a></li>
              <li><a href="/downloads.html">Download</a></li>
              <li class="nav-more">
                <button type="button" class="nav-more__toggle" aria-expanded="false" aria-haspopup="true">More</button>
                <ul class="nav-more__menu" hidden>
                  <li><a href="/docs/adoption-bar.html">Adoption bar</a></li>
                  <li><a href="/docs/ai-models.html">AI models</a></li>
                  <li><a href="/docs/native-network-web.html">Network + web</a></li>
                  <li><a href="/docs/programming-guide.html">Programming guide</a></li>
                  <li><a href="/docs/ide.html">IDE</a></li>
                  <li><a href="/docs/self-host.html">Contributor internals</a></li>
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
          <a href="/learn/">Learn</a>
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
    "VOICE.md": "/docs/language.html",
    "SELF_HOST.md": "/docs/self-host.html",
    "SPARK_BC.md": "/docs/self-host.html",
    "NATIVE_NETWORK_WEB.md": "/docs/native-network-web.html",
}


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
    def fence(m: re.Match[str]) -> str:
        lang = m.group(1) or ""
        if lang:
            return f'<pre class="doc__pre"><code class="language-{lang}">'
        return '<pre class="doc__pre"><code>'

    body = re.sub(r"<pre><code(?: class=\"language-([^\"]+)\")?>", fence, body)
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
    nav = DOC_NAV.format(
        ab=' aria-current="page"' if current == "ab" else "",
        ai=' aria-current="page"' if current == "ai" else "",
        nn=' aria-current="page"' if current == "nn" else "",
        ide=' aria-current="page"' if current == "ide" else "",
        sh=' aria-current="page"' if current == "sh" else "",
    )
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


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--all-stale",
        action="store_true",
        help="Regenerate ai-models, language, self-host, native-network-web",
    )
    args = ap.parse_args()
    docs = ROOT / "docs"
    out = ROOT / "website" / "docs"
    if args.all_stale:
        render(
            docs / "ADOPTION_BAR.md",
            out / "adoption-bar.html",
            "Adoption bar",
            "SparkLang adoption checklist — done, next, won't.",
            "ab",
        )
        render(
            docs / "ROADMAP.md",
            out / "roadmap.html",
            "Roadmap",
            "SparkLang roadmap — done, next, won't.",
            "",
        )
        render(
            docs / "RELEASE.md",
            out / "release.html",
            "Release process",
            "How SparkLang versions and GitHub Releases are cut.",
            "",
        )
        render(
            docs / "AI_MODELS.md",
            out / "ai-models.html",
            "AI models",
            "What SparkLang means for model train, analyze, compare, "
            "improve, plan, live ask, and embed/retrieve.",
            "ai",
        )
        render(
            docs / "MODEL_TRAINING.md",
            out / "model-training.html",
            "Model training",
            "SparkLang model train / build — real jobs, dry fixtures, "
            "HTTP and local-yield backends.",
            "ai",
        )
        render(
            docs / "LANGUAGE.md",
            out / "language.html",
            "Language reference",
            "SparkLang statement reference — ask, classify, embed, "
            "retrieve, shell, voice, pipeline, and more.",
            "",
        )
        render(
            docs / "PROGRAMMING_GUIDE.md",
            out / "programming-guide.html",
            "Programming guide",
            "How to write and run SparkLang programs — dry-run, "
            "live flags, host embed, and first programs.",
            "",
        )
        render(
            docs / "SELF_HOST.md",
            out / "self-host.html",
            "Contributor internals",
            "Spark self-host path: A + B bootstrap + C assembler, "
            "SPARK_BC stages, and evidence gates.",
            "sh",
        )
        render(
            docs / "NATIVE_NETWORK_WEB.md",
            out / "native-network-web.html",
            "Native network + web",
            "Network/web ops — de-emphasized vs http get/post roadmap.",
            "nn",
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
