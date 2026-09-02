#!/usr/bin/env python3
"""Generate website playbook catalog + IDE snippets from repo SoT only.

Sources (no invented playbooks):
  - lib/playbooks.spark  (# @playbook <name>)
  - bootstrap/fixtures/playbooks/*.spark

Writes:
  - website/data/playbooks-catalog.json
  - tools/spark-ide-extension/snippets/playbooks.json
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLAYBOOKS_LIB = ROOT / "lib" / "playbooks.spark"
FIXTURES_DIR = ROOT / "bootstrap" / "fixtures" / "playbooks"
OUT_JSON = ROOT / "website" / "data" / "playbooks-catalog.json"
OUT_SNIPPETS = (
    ROOT / "tools" / "spark-ide-extension" / "snippets" / "playbooks.json"
)

PLAYBOOK_TAG_RE = re.compile(
    r"^#\s*@playbook\s+(\w+)\s*$",
    re.MULTILINE,
)


def load_catalog_names() -> list[str]:
    """Return @playbook names from lib/playbooks.spark in file order."""
    text = PLAYBOOKS_LIB.read_text(encoding="utf-8")
    names = PLAYBOOK_TAG_RE.findall(text)
    if not names:
        raise SystemExit(f"no @playbook tags in {PLAYBOOKS_LIB}")
    return names


def fixture_path(name: str) -> Path:
    return FIXTURES_DIR / f"{name}.spark"


def load_fixture_source(name: str) -> str:
    path = fixture_path(name)
    if not path.is_file():
        raise SystemExit(f"missing fixture for playbook {name}: {path}")
    return path.read_text(encoding="utf-8").rstrip() + "\n"


def extra_fixture_names(catalog: list[str]) -> list[str]:
    """Fixture-only goldens not listed as @playbook."""
    known = set(catalog)
    extras: list[str] = []
    for path in sorted(FIXTURES_DIR.glob("*.spark")):
        name = path.stem
        if name not in known:
            extras.append(name)
    return extras


def build_entries() -> list[dict]:
    catalog = load_catalog_names()
    entries: list[dict] = []
    for name in catalog:
        source = load_fixture_source(name)
        entries.append(
            {
                "id": name,
                "name": name,
                "label": name.replace("_", " "),
                "source": source,
                "fixture": f"bootstrap/fixtures/playbooks/{name}.spark",
                "libRef": "lib/playbooks.spark",
                "kind": "playbook",
                "runtime": "bootstrap",
                "siteRun": "download-required",
            }
        )
    for name in extra_fixture_names(catalog):
        source = load_fixture_source(name)
        entries.append(
            {
                "id": name,
                "name": name,
                "label": name.replace("_", " "),
                "source": source,
                "fixture": f"bootstrap/fixtures/playbooks/{name}.spark",
                "libRef": None,
                "kind": "fixture-golden",
                "runtime": "bootstrap",
                "siteRun": "download-required",
            }
        )
    return entries


def build_snippets(entries: list[dict]) -> dict:
    snippets: dict = {}
    for entry in entries:
        if entry["kind"] != "playbook":
            continue
        name = entry["name"]
        body = entry["source"].rstrip("\n").split("\n")
        snippets[f"Spark playbook: {name}"] = {
            "prefix": f"spark-playbook-{name}",
            "description": (
                f"AI coding playbook from lib/playbooks.spark ({name})"
            ),
            "body": body,
        }
    return snippets


def main() -> int:
    """Write playbooks-catalog.json and IDE snippet file."""
    if not PLAYBOOKS_LIB.is_file():
        print(f"missing {PLAYBOOKS_LIB}", file=sys.stderr)
        return 1
    if not FIXTURES_DIR.is_dir():
        print(f"missing {FIXTURES_DIR}", file=sys.stderr)
        return 1

    entries = build_entries()
    catalog_names = [e["name"] for e in entries if e["kind"] == "playbook"]
    payload = {
        "generatedBy": "tools/gen_playbooks_catalog.py",
        "libFile": "lib/playbooks.spark",
        "fixturesDir": "bootstrap/fixtures/playbooks",
        "playbookCount": len(catalog_names),
        "entryCount": len(entries),
        "note": (
            "Browser has no Spark WASM runtime. Loading a playbook only "
            "fills the editor; Run dry-run fails loud with a download link."
        ),
        "downloadUrl": "/downloads.html",
        "localDryRun": "./spark-bootstrap --dry-run <file.spark>",
        "entries": entries,
    }

    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    OUT_SNIPPETS.parent.mkdir(parents=True, exist_ok=True)
    snippets = build_snippets(entries)
    OUT_SNIPPETS.write_text(
        json.dumps(snippets, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    print(
        f"wrote {OUT_JSON.relative_to(ROOT)} "
        f"({payload['playbookCount']} playbooks, "
        f"{payload['entryCount']} entries)"
    )
    print(
        f"wrote {OUT_SNIPPETS.relative_to(ROOT)} "
        f"({len(snippets)} snippets)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
