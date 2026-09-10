#!/usr/bin/env python3
"""Scrub operator leaks from public CHANGELOG.md historical notes.

Removes SoapBox / owner jargon that leaked into release notes
("Not beat Claude", "Never 6000", RTX PRO 6000 / GPU-1 asides,
owner citations). Leaves the 0.6.59 scrub announcement intact
(it documents what was scrubbed). Adds 0.6.60 when missing.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

KEEP_INTACT = frozenset({"0.6.59", "0.6.61"})

REPLACEMENTS: list[tuple[re.Pattern[str], str]] = [

    # Spaced / residual variants
    (re.compile(r"(?i)Does\s+\*\*not\*\*\s+beat Claude"),
     "Measurement only — not a marketing win"),
    (re.compile(r"(?i)Never\s+beat Claude"), "Measurement only"),
    (re.compile(r"(?i)aims to beat Claude"),
     "aims to improve measured probes"),
    (re.compile(r"(?i)\*\*Not beat\s+Claude\.\*\*"),
     "**Measurement only.**"),
    (re.compile(r"(?i)Not beat\s+Claude\.?"), "Measurement only."),
    (re.compile(r"(?i)\*\*Never\*\*\s+6000"),
     "**dedicated voice GPU only when configured**"),
    (re.compile(r"(?i)Never\s+6000"),
     "dedicated voice GPU only when configured"),
    (re.compile(r"(?i)\bNo 6000\b"), "No voice-GPU hardcode"),
    (re.compile(r"(?i)hard-refuse\s+\*\*6000\*\*"),
     "hard-refuse mis-placed voice GPU"),
    (re.compile(r"(?i)\*\*never\*\*\s+RTX PRO 6000"),
     "optional discrete GPU only"),
    (re.compile(r"(?i)RTX PRO 6000"), "dedicated voice GPU"),
    (re.compile(r"(?i)only PRO \*\*6000\*\*"),
     "only the voice GPU"),
    (re.compile(r"(?i)\bSoapBox\b"), "local workstation"),

    (re.compile(r"(?i)owner citations"), "citations"),
    (re.compile(r"\(owner addendum\)"), ""),
    (re.compile(r"(?i)\bOWNER-CONFIRM\b"), "confirm"),
    (re.compile(r"(?i)SoapBox-local"), "local"),
    (re.compile(r"(?i)\s*/\s*GPU-1"), ""),
    (
        re.compile(
            r"(?i)\(optional \*\*RTX 5090\*\* torch path; "
            r"\*\*never\*\* RTX PRO 6000\)"
        ),
        "(optional **RTX 5090** torch path)",
    ),
    (
        re.compile(
            r"(?i)Prefer \*\*RTX 5090\*\*; hard-refuse \*\*6000\*\*\."
        ),
        "Prefer **RTX 5090**.",
    ),
    (
        re.compile(
            r"(?i)prefer \*\*RTX 5090\*\*, ~2 GiB hint; "
            r"\*\*fail closed\*\* if only PRO \*\*6000\*\* visible "
            r"unless `--device cpu`"
        ),
        "prefer **RTX 5090**, ~2 GiB hint",
    ),
    (
        re.compile(
            r"(?i)`make weight-gallery-xl` prefers \*\*5090\*\*, "
            r"\*\*never\*\* 6000\."
        ),
        "`make weight-gallery-xl` prefers **5090**.",
    ),
    (
        re.compile(
            r"(?i)CPU by default; \*\*RTX 5090 OK\*\*; \*\*NEVER\*\* "
            r"RTX PRO\s+6000\."
        ),
        "CPU by default; **RTX 5090 OK**.",
    ),
    (re.compile(r"(?i)Later train aims to beat Claude\."), ""),
    (re.compile(r"(?i)later stages aim to beat Claude;?\s*"), ""),
    (
        re.compile(r"(?i)\*\*Never\*\* perfect SPARK_BC LLM claim\.\s*"),
        "No perfect SPARK_BC LLM claim. ",
    ),
    (
        re.compile(
            r"(?i)Does \*\*not\*\* beat Claude or these models/products\."
        ),
        "Does not claim parity with these models/products.",
    ),
    (re.compile(r"(?i)Still \*\*not\*\* beat Claude;\s*"), ""),
    (re.compile(r"(?i);\s*does \*\*not\*\* beat Claude"), ""),
    (re.compile(r"(?i)\.\s*Does \*\*not\*\* beat Claude"), ""),
    (re.compile(r"(?i)\.\s*\*\*Not beat Claude\.\*\*"), ""),
    (re.compile(r"(?i)\s*\*\*Not beat Claude\.\*\*"), ""),
    (re.compile(r"(?i);\s*not beat Claude"), ""),
    (
        re.compile(
            r"(?i)not beat Claude; no OpenBin/phone clone"
        ),
        "no OpenBin/phone clone",
    ),
    (
        re.compile(
            r"(?i)Does \*\*not\*\* beat Claude; not an OpenBin clone"
        ),
        "Not an OpenBin clone",
    ),
    (
        re.compile(
            r"(?i)Never invents keys\. Never claims beat Claude\."
        ),
        "Never invents keys.",
    ),
    (re.compile(r"(?i)`beats_claude` always \*\*false\*\*\.\s*"), ""),
    (re.compile(r"(?i)\*\*Never\*\* 6000\.\s*"), ""),
    (re.compile(r"(?i)\*\*never\*\* 6000\.\s*"), ""),
    (re.compile(r"(?i)No 6000 / GPU-1\.?\s*"), ""),
    (
        re.compile(
            r"(?i)attention decode still partial; \*\*not\*\* beat Claude"
        ),
        "attention decode still partial",
    ),
    (
        re.compile(
            r"(?i)third-party clone; does not beat Claude"
        ),
        "third-party clone",
    ),
    # Generic trailing spam (after specific fixes)
    (re.compile(r"(?i)\s+does not beat Claude\.?"), ""),
    (re.compile(r"(?i)\s+Never beat Claude\.?"), ""),
    (re.compile(r"(?i)\s+does \*\*not\*\* beat Claude\.?"), ""),
    (re.compile(r"(?i)\s+\*\*Not beat Claude\.\*\*"), ""),
    (re.compile(r"(?i)\s+\*\*not beat Claude\*\*\.?"), ""),
]


def clean_body(body: str) -> str:
    """Apply phrase replacements and tidy punctuation debris."""
    cleaned = body
    for rx, repl in REPLACEMENTS:
        cleaned = rx.sub(repl, cleaned)
    cleaned = re.sub(r"  +", " ", cleaned)
    cleaned = re.sub(r" \.", ".", cleaned)
    cleaned = re.sub(r"\.\s*\.", ".", cleaned)
    cleaned = re.sub(r";\s*;", ";", cleaned)
    cleaned = re.sub(r",\s*,", ",", cleaned)
    cleaned = re.sub(r"\(\s*\)", "", cleaned)
    cleaned = re.sub(r"[;,](\s*\n)", r"\1", cleaned)
    cleaned = re.sub(r"\s+\.\s+", ". ", cleaned)
    return cleaned


ENTRY_060 = """## 0.6.60 — 2026-09-09

- **Changelog operator-leak scrub:** strip remaining SoapBox / owner
  jargon from historical release notes ("Not beat Claude", "Never 6000",
  RTX PRO 6000 / GPU-1 policy asides, "owner citations"). Keep product
  honesty where it belongs (eval measurement, no OpenBin clone). Mirror
  `website/CHANGELOG.html`.

"""


def scrub(text: str) -> str:
    """Return CHANGELOG text with operator leaks removed."""
    parts = re.split(r"(?m)^(## \d+\.\d+\.\d+ — .+)$", text)
    out: list[str] = [parts[0]]
    for i in range(1, len(parts), 2):
        header = parts[i]
        body = parts[i + 1] if i + 1 < len(parts) else ""
        match = re.match(r"## (\d+\.\d+\.\d+)", header)
        ver = match.group(1) if match else ""
        if ver in KEEP_INTACT:
            out.append(header + "\n" + body)
            continue
        out.append(header + "\n" + clean_body(body))
    new_text = "".join(out)
    if "## 0.6.60 —" not in new_text:
        needle = "`website/downloads/manifest.json`.\n\n\n"
        if needle not in new_text:
            needle = "`website/downloads/manifest.json`.\n\n"
        new_text = new_text.replace(needle, needle + ENTRY_060, 1)
    return new_text


def remaining_leaks(text: str) -> list[tuple[str, str]]:
    """List (version, snippet) leaks outside scrub announcement notes."""
    allow = frozenset({"0.6.59", "0.6.61"})
    patterns = [
        re.compile(r"(?i)beat claude"),
        re.compile(r"6000"),
        re.compile(r"(?i)owner cite"),
        re.compile(r"(?i)SoapBox"),
        re.compile(r"GPU-1"),
        re.compile(r"OWNER-CONFIRM"),
    ]
    found: list[tuple[str, str]] = []
    for rx in patterns:
        for match in rx.finditer(text):
            before = text[: match.start()]
            secs = re.findall(r"## (\d+\.\d+\.\d+)", before)
            ver = secs[-1] if secs else "pre"
            if ver in allow:
                continue
            snip = text[max(0, match.start() - 24) : match.end() + 24]
            found.append((ver, snip.replace("\n", " ")))
    return found


def main() -> int:
    """Scrub CHANGELOG.md in-place and print remaining leak count."""
    path = Path("CHANGELOG.md")
    if not path.is_file():
        print("CHANGELOG.md missing", file=sys.stderr)
        return 2
    original = path.read_text(encoding="utf-8")
    updated = scrub(original)
    path.write_text(updated, encoding="utf-8")
    leaks = remaining_leaks(updated)
    print(f"wrote {path}; remaining leaks outside scrub notes: {len(leaks)}")
    for ver, snip in leaks[:20]:
        print(f"  {ver}: {snip!r}")
    return 0 if len(leaks) == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
