#!/usr/bin/env python3
"""Shared Spark primary-nav tree (Hive / Forge / Bench subcategories).

Single SoT for marketing HTML + docs generator. Nesting is
category → subcategory → page links. Never RTX PRO 6000.
"""
from __future__ import annotations

from typing import Iterable

# (href, label) — relative site paths
NavLink = tuple[str, str]
# (subcategory_label, links)
NavSub = tuple[str, tuple[NavLink, ...]]
# (menu_label, hub_link_or_None, subgroups)
NavMenu = tuple[str, NavLink | None, tuple[NavSub, ...]]

TOP_LINKS: tuple[NavLink, ...] = (
    ("/workflow.html", "Loop"),
    ("/learn/", "Learn"),
    ("/docs/knowledge.html", "Knowledge"),
    ("/docs/language.html", "Docs"),
    ("/docs/factory.html", "Factory"),
    ("/downloads.html", "Download"),
)

# Hive · Forge · Bench — labeled subgroups
NAV_MENUS: tuple[NavMenu, ...] = (
    (
        "Hive",
        ("/docs/knowledge.html", "Knowledge hub"),
        (
            (
                "Foundations",
                (
                    ("/docs/knowledge-llm.html", "LLMs & transformers"),
                    ("/docs/knowledge-training.html", "Training"),
                    ("/docs/knowledge-inference.html", "Inference"),
                ),
            ),
            (
                "Systems",
                (
                    ("/docs/knowledge-multimodal.html", "Multimodal"),
                    ("/docs/knowledge-agents.html", "Agents & tools"),
                ),
            ),
            (
                "Safety / Eval",
                (
                    ("/docs/knowledge-eval.html", "Evaluation"),
                    ("/docs/knowledge-safety.html", "Safety & limits"),
                ),
            ),
            (
                "RE",
                (
                    ("/docs/knowledge-decompile.html", "Decompile + RE"),
                    ("/docs/llm-decompile.html", "LLM decompile research"),
                ),
            ),
        ),
    ),
    (
        "Forge",
        None,
        (
            (
                "Senses",
                (
                    ("/docs/voice.html", "Voice / STT / TTS"),
                    ("/docs/voice-ask.html", "Voice ask"),
                    ("/docs/voice-easy.html", "Voice easy"),
                ),
            ),
            (
                "Models",
                (
                    ("/docs/model-aspects.html", "Model aspects"),
                    ("/docs/diagrams.html", "Diagrams"),
                    ("/docs/spark-coder.html", "Spark coder"),
                    ("/docs/weight-gallery.html", "Weight gallery"),
                    ("/docs/ai-models.html", "AI models"),
                ),
            ),
            (
                "Train",
                (
                    ("/docs/spark-builder.html", "Builder"),
                    ("/docs/build-models.html", "Build models"),
                    ("/docs/model-training.html", "Model training"),
                    ("/docs/train-loop.html", "Train loop"),
                ),
            ),
        ),
    ),
    (
        "Bench",
        None,
        (
            (
                "Language",
                (
                    ("/docs/compile.html", "Compile"),
                    ("/docs/decompile.html", "Decompile"),
                    ("/docs/decompile-compete.html", "Decompile compete"),
                    ("/docs/spark-bc.html", "Opcodes / ISA"),
                    ("/docs/programming-guide.html", "Programming guide"),
                ),
            ),
            (
                "Runtime",
                (
                    ("/docs/serve.html", "Serve"),
                    ("/docs/ide.html", "IDE"),
                    ("/docs/lsp.html", "LSP / editor"),
                    ("/ide-web.html", "IDE web shell"),
                    ("/docs/native-network-web.html", "Network + web"),
                ),
            ),
            (
                "Ops",
                (
                    ("/docs/tools-helpers.html", "Tools & helpers"),
                    ("/about.html", "About"),
                ),
            ),
        ),
    ),
)

CTA: NavLink = ("/playground.html", "Try")

# HTML comments used by sync_site_nav.py to rewrite marketing pages.
NAV_BEGIN = "<!-- spark-primary-nav:begin -->"
NAV_END = "<!-- spark-primary-nav:end -->"


def iter_menu_hrefs() -> Iterable[str]:
    """Yield every href under Hive / Forge / Bench."""
    for _label, hub, subs in NAV_MENUS:
        if hub:
            yield hub[0]
        for _sub, links in subs:
            for href, _title in links:
                yield href


def render_primary_nav_inner(indent: str = "            ") -> str:
    """Render <ul class=\"nav-primary\">…</ul> + CTA (no outer wrap)."""
    lines: list[str] = [f"{indent}<ul class=\"nav-primary\">"]
    for href, label in TOP_LINKS:
        lines.append(f"{indent}  <li><a href=\"{href}\">{label}</a></li>")
    for menu_label, hub, subs in NAV_MENUS:
        slug = menu_label.lower().replace(" ", "-").replace("/", "-")
        lines.append(f'{indent}  <li class="nav-more">')
        lines.append(
            f'{indent}    <button type="button" class="nav-more__toggle" '
            f'aria-expanded="false" aria-haspopup="true">'
            f"{menu_label}</button>"
        )
        lines.append(
            f'{indent}    <ul class="nav-more__menu" hidden>'
        )
        if hub:
            href, title = hub
            lines.append(
                f'{indent}      <li class="nav-more__hub">'
                f'<a href="{href}">{title}</a></li>'
            )
        for sub_label, links in subs:
            sub_id = f"nav-{slug}-{_slug(sub_label)}"
            lines.append(f'{indent}      <li class="nav-sub">')
            lines.append(
                f'{indent}        <span class="nav-sub__label" id="{sub_id}">'
                f"{sub_label}</span>"
            )
            lines.append(
                f'{indent}        <ul class="nav-sub__list" '
                f'aria-labelledby="{sub_id}">'
            )
            for href, title in links:
                lines.append(
                    f"{indent}          <li>"
                    f'<a href="{href}">{title}</a></li>'
                )
            lines.append(f"{indent}        </ul>")
            lines.append(f"{indent}      </li>")
        lines.append(f"{indent}    </ul>")
        lines.append(f"{indent}  </li>")
    lines.append(f"{indent}</ul>")
    href, label = CTA
    lines.append(
        f'{indent}<a href="{href}" class="nav-cta">{label}</a>'
    )
    return "\n".join(lines)


def render_primary_nav_block(indent: str = "            ") -> str:
    """Nav inner wrapped in begin/end markers for sync."""
    inner = render_primary_nav_inner(indent=indent)
    return f"{indent}{NAV_BEGIN}\n{inner}\n{indent}{NAV_END}"


def _slug(label: str) -> str:
    out = label.lower().replace(" / ", "-").replace("/", "-")
    out = out.replace(" ", "-")
    return "".join(ch for ch in out if ch.isalnum() or ch == "-")


def subcategory_map_markdown() -> str:
    """Owner-facing subcategory map (report / CHANGELOG)."""
    lines = ["| Category | Subcategory | Pages |", "|----------|-------------|-------|"]
    for menu, hub, subs in NAV_MENUS:
        if hub:
            lines.append(
                f"| **{menu}** | *(hub)* | [{hub[1]}]({hub[0]}) |"
            )
        for sub, links in subs:
            pages = ", ".join(f"[{t}]({h})" for h, t in links)
            lines.append(f"| **{menu}** | {sub} | {pages} |")
    return "\n".join(lines)
