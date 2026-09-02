#!/usr/bin/env python3
"""Generate Spark function catalog from LANGUAGE.md, lib/*.spark, and examples/."""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANG_MD = ROOT / "docs" / "LANGUAGE.md"
LIB_DIR = ROOT / "lib"
EXAMPLES_DIR = ROOT / "examples"
OUT_JSON = ROOT / "website" / "data" / "function-catalog.json"
OUT_MANIFEST = ROOT / "website" / "data" / "stdlib-manifest.json"

HELPER_RE = re.compile(r"^#\s*@helper\s+(\w+):\s*(.+)$", re.MULTILINE)

# LANGUAGE.md section → catalog category
SECTION_CATEGORIES: dict[str, str] = {
    "ask": "AI",
    "generate": "AI",
    "extract": "AI",
    "classify": "AI",
    "listen": "Voice",
    "speak": "Voice",
    "voice": "Voice",
    "pipeline": "AI",
    "include": "Stdlib",
    "tool": "AI",
    "with tools": "AI",
    "let": "Data",
    "print": "Data",
    "set": "Data",
    "review": "Review",
    "builder": "Review",
    "implement": "Review",
    "ide": "IDE",
    "ide keys": "IDE",
    "ide key": "IDE",
    "binary": "Binary",
    "network": "Network",
    "browser": "Browser",
    "mitm": "Browser",
    "engine": "Browser",
    "js": "Browser",
    "crypto": "Crypto",
    "encrypt": "Crypto",
    "gateway": "Crypto",
    "cuda": "CUDA",
    "pcie": "CUDA",
    "memory pin": "CUDA",
    "os": "OS",
    "model analyze": "Model",
    "model compare": "Model",
    "model improve": "Model",
    "model build": "Model",
}

MODE_HINTS: dict[str, str] = {
    "dry-run": "dry-run",
    "live": "live",
    "bootstrap": "bootstrap-only",
    "GAS": "gas-only",
    "asm": "gas-only",
}

EXAMPLE_MAP: dict[str, str] = {}


@dataclass
class CatalogEntry:
    id: str
    name: str
    category: str
    description: str
    syntax: str
    mode: str = "dry-run"
    source: str = "language"
    example: str | None = None
    lib_file: str | None = None
    popular: bool = False

    def to_dict(self) -> dict:
        d = {
            "id": self.id,
            "name": self.name,
            "category": self.category,
            "description": self.description,
            "syntax": self.syntax,
            "mode": self.mode,
            "source": self.source,
        }
        if self.example:
            d["example"] = self.example
        if self.lib_file:
            d["libFile"] = self.lib_file
        if self.popular:
            d["popular"] = True
        return d


def slug(name: str) -> str:
    s = re.sub(r"[^a-zA-Z0-9]+", "-", name.strip().lower()).strip("-")
    return s or "fn"


def infer_mode(text: str, default: str = "dry-run") -> str:
    lower = text.lower()
    if "bootstrap only" in lower or "bootstrap vm only" in lower:
        return "bootstrap-only"
    if "gas `./spark`" in lower or "not implemented in gas" in lower:
        return "gas-only"
    if "--live" in lower or "**live**" in lower:
        if "dry-run" in lower[:200]:
            return "dry-run"
        return "live"
    if "dry-run" in lower:
        return "dry-run"
    return default


def build_example_map() -> None:
    if not EXAMPLES_DIR.is_dir():
        return
    keywords = {
        "classify_intent": "classify_intent.spark",
        "extract_person": "extract_person.spark",
        "pipeline_translate": "pipeline_translate.spark",
        "voice_turn": "voice_turn.spark",
        "model_improve": "model_improve.spark",
        "review_builder": "review_builder.spark",
        "ask_live": "ask_live.spark",
        "ask_probe": "ask_probe.spark",
        "gateway_probe": "gateway_probe.spark",
        "hello": "hello.spark",
        "browser_main": "browser_main.spark",
        "network_analyze": "network_analyze.spark",
        "binary_any": "binary_any.spark",
        "cuda_mem": "cuda_mem.spark",
        "cuda_pcie": "cuda_pcie.spark",
        "encrypt_gateway": "encrypt_gateway.spark",
        "ide_hello": "ide_hello.spark",
        "os_agentos": "os_agentos.spark",
        "voice_live": "voice_live.spark",
        "tool_agent": "tool_agent.spark",
    }
    for key, fname in keywords.items():
        if (EXAMPLES_DIR / fname).is_file():
            EXAMPLE_MAP[key] = f"examples/{fname}"


def parse_lib_helpers() -> list[CatalogEntry]:
    entries: list[CatalogEntry] = []
    category_from_file = {
        "ask.spark": "AI",
        "classify.spark": "AI",
        "extract.spark": "AI",
        "voice.spark": "Voice",
        "model.spark": "Model",
        "review.spark": "Review",
        "data.spark": "Data",
        "http.spark": "Network",
        "pipeline.spark": "AI",
        "ai.spark": "AI",
    }
    for path in sorted(LIB_DIR.glob("*.spark")):
        text = path.read_text(encoding="utf-8")
        category = category_from_file.get(path.name, "Stdlib")
        for match in HELPER_RE.finditer(text):
            name = match.group(1)
            desc = match.group(2).strip()
            after = text[match.end() :]
            syntax_lines: list[str] = []
            for line in after.splitlines():
                stripped = line.strip()
                if stripped.startswith("# @helper"):
                    break
                if stripped.startswith("# ") and not stripped.startswith("# @"):
                    body = stripped[2:].strip()
                    if body:
                        syntax_lines.append(body)
                    if len(syntax_lines) >= 6:
                        break
                    continue
                if stripped and not stripped.startswith("#"):
                    break
            syntax = "\n".join(syntax_lines) if syntax_lines else desc
            mode = infer_mode(text[max(0, match.start() - 200) : match.end() + 400])
            example = None
            for key, ex in EXAMPLE_MAP.items():
                if key.replace("_", "") in name.replace("_", ""):
                    example = ex
                    break
            popular = name in {
                "ask_summarize",
                "classify_intent_support_sales",
                "extract_person",
                "voice_turn_basic",
                "model_workflow_full",
                "review_path_js",
                "let_print_hello",
                "http_ask_probe",
            }
            entries.append(
                CatalogEntry(
                    id=f"lib-{slug(name)}",
                    name=name,
                    category=category,
                    description=desc,
                    syntax=syntax,
                    mode=mode,
                    source="stdlib",
                    example=example,
                    lib_file=f"lib/{path.name}",
                    popular=popular,
                )
            )
    return entries


def parse_language_ops() -> list[CatalogEntry]:
    text = LANG_MD.read_text(encoding="utf-8")
    entries: list[CatalogEntry] = []
    seen: set[str] = set()

    # ### `op` headers
    for m in re.finditer(r"^###\s+`([^`]+)`", text, re.MULTILINE):
        op_raw = m.group(1).strip()
        op_key = op_raw.split("/")[0].split()[0].lower()
        category = "Core"
        for prefix, cat in SECTION_CATEGORIES.items():
            if op_raw.lower().startswith(prefix) or op_key.startswith(
                prefix.split()[0]
            ):
                category = cat
                break
        section = text[m.start() : m.start() + 2500]
        mode = infer_mode(section)
        desc_m = re.search(r"^###[^\n]+\n\n(.+?)(?:\n\n|\n```)", section, re.DOTALL)
        desc = (
            desc_m.group(1).strip().split("\n")[0][:160]
            if desc_m
            else f"Spark `{op_raw}` statement"
        )
        code_m = re.search(r"```\n(.+?)```", section, re.DOTALL)
        syntax = code_m.group(1).strip() if code_m else op_raw
        entry_id = f"lang-{slug(op_raw)}"
        if entry_id in seen:
            continue
        seen.add(entry_id)
        example = None
        ex_m = re.search(r"examples/[\w./_-]+\.spark", section)
        if ex_m:
            example = ex_m.group(0)
        entries.append(
            CatalogEntry(
                id=entry_id,
                name=op_raw,
                category=category,
                description=desc,
                syntax=syntax[:500],
                mode=mode,
                source="language",
                example=example,
                popular=op_key
                in {
                    "ask",
                    "classify",
                    "extract",
                    "pipeline",
                    "voice",
                    "model",
                    "review",
                    "listen",
                    "speak",
                },
            )
        )

    # Table rows | `op` |
    for m in re.finditer(r"^\|\s+`([^`]+)`\s+\|", text, re.MULTILINE):
        op = m.group(1).strip()
        entry_id = f"lang-{slug(op)}"
        if entry_id in seen:
            continue
        seen.add(entry_id)
        category = "Browser"
        if op.startswith("ide"):
            category = "IDE"
        elif op.startswith("engine") or op.startswith("browser"):
            category = "Browser"
        entries.append(
            CatalogEntry(
                id=entry_id,
                name=op,
                category=category,
                description=f"Spark `{op}` operation",
                syntax=op,
                mode="dry-run",
                source="language",
            )
        )

    # Backtick ops in prose blocks (browser mitm, cuda, etc.)
    op_patterns = [
        (r"(browser \w+(?: \w+)*)", "Browser"),
        (r"(mitm [\w_]+(?: [\w]+)*)", "Browser"),
        (r"(engine [\w ]+)", "Browser"),
        (r"(network \w+(?: \w+)*)", "Network"),
        (r"(binary \w+(?: \w+)*)", "Binary"),
        (r"(cuda \w+(?: \w+)*)", "CUDA"),
        (r"(pcie \w+(?: \w+)*)", "CUDA"),
        (r"(memory pin[^\n`]*)", "CUDA"),
        (r"(crypto \w+)", "Crypto"),
        (r"(encrypt \w+(?: \w+)*)", "Crypto"),
        (r"(gateway \w+(?: \w+)*)", "Crypto"),
        (r"(os \w+(?: \w+)*)", "OS"),
        (r"(ide \w+(?: \w+)*)", "IDE"),
        (r"(review \w+)", "Review"),
        (r"(builder \w+)", "Review"),
        (r"(implement \w+)", "Review"),
        (r"(voice \w+(?: \w+)*)", "Voice"),
    ]
    for pattern, category in op_patterns:
        for m in re.finditer(r"`(" + pattern + r")`", text):
            op = m.group(1).strip()
            entry_id = f"lang-{slug(op)}"
            if entry_id in seen:
                continue
            seen.add(entry_id)
            ctx = text[max(0, m.start() - 100) : m.end() + 200]
            entries.append(
                CatalogEntry(
                    id=entry_id,
                    name=op,
                    category=category,
                    description=f"Spark `{op}` operation",
                    syntax=op,
                    mode=infer_mode(ctx),
                    source="language",
                )
            )

    return entries


def link_examples(entries: list[CatalogEntry]) -> None:
    if not EXAMPLES_DIR.is_dir():
        return
    by_stem: dict[str, str] = {}
    for p in EXAMPLES_DIR.glob("*.spark"):
        by_stem[p.stem.lower()] = f"examples/{p.name}"
    for e in entries:
        if e.example:
            continue
        name_lower = e.name.lower().replace(" ", "_")
        for stem, path in by_stem.items():
            if stem in name_lower or name_lower in stem:
                e.example = path
                break


def main() -> int:
    build_example_map()
    lib_entries = parse_lib_helpers()
    lang_entries = parse_language_ops()
    all_entries = lang_entries + lib_entries
    # Dedupe by id prefer stdlib detail
    by_id: dict[str, CatalogEntry] = {}
    for e in all_entries:
        if e.id not in by_id or e.source == "stdlib":
            by_id[e.id] = e
    entries = sorted(by_id.values(), key=lambda x: (x.category, x.name))
    link_examples(entries)

    categories = sorted({e.category for e in entries})
    helper_count = sum(1 for e in entries if e.source == "stdlib")
    popular = [e.to_dict() for e in entries if e.popular][:20]

    catalog = {
        "generated": True,
        "version": 1,
        "helperCount": helper_count,
        "totalEntries": len(entries),
        "categoryCount": len(categories),
        "categories": categories,
        "entries": [e.to_dict() for e in entries],
        "popularPresets": popular,
    }
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")

    manifest = {
        "helperCount": helper_count,
        "totalEntries": len(entries),
        "categoryCount": len(categories),
        "libFiles": sorted(p.name for p in LIB_DIR.glob("*.spark")),
        "helpersByFile": {},
    }
    for path in sorted(LIB_DIR.glob("*.spark")):
        text = path.read_text(encoding="utf-8")
        count = len(HELPER_RE.findall(text))
        manifest["helpersByFile"][path.name] = count

    OUT_MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    print(f"Wrote {OUT_JSON} ({len(entries)} entries, {helper_count} stdlib helpers)")
    print(f"Categories: {len(categories)}")
    for fname, cnt in manifest["helpersByFile"].items():
        print(f"  {fname}: {cnt} helpers")
    return 0


if __name__ == "__main__":
    sys.exit(main())
