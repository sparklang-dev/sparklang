#!/usr/bin/env python3
"""Measured probe: multi-format PE32/PE32+ parsing capability.

Runs the real ./spark-binary-probe --pe on the pinned real PE
fixtures, diffs entry/sections/imports against `objdump -x` ground
truth, checks loud failure on truncated/corrupt copies, and emits
measured JSON to website/data/probes/pe_multiformat.json for the
scoreboard badge pass. Never mocks; never declares unmeasured wins.
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE_BIN = ROOT / "spark-binary-probe"
FIXTURES = ROOT / "examples/fixtures/binary"
OUT = ROOT / "website/data/probes/pe_multiformat.json"

PE_FIXTURES = [
    (
        FIXTURES / "winver-pe32plus.exe",
        "7f1c587ac7140864a6c1c20f3cb1ea8b20cd6da6a07ed7cd37f27f51386c49cd",
        "pe32plus",
    ),
    (
        FIXTURES / "csc-pe32.exe",
        "1f1c14c8f7bff93bbe433290963885a3ae3b13da6fdd24decb74c03d692fb6cb",
        "pe32",
    ),
]


def _run_probe_json(*args: str) -> tuple[int, dict | None]:
    """Run the probe binary; return (rc, parsed JSON or None)."""
    proc = subprocess.run(
        [str(PROBE_BIN), *args],
        capture_output=True,
        text=True,
        check=False,
    )
    try:
        return proc.returncode, json.loads(proc.stdout)
    except ValueError:
        return proc.returncode, None


def _objdump_truth(path: Path) -> dict:
    """Parse `objdump -x` ground truth for entry/sections/imports."""
    out = subprocess.run(
        ["objdump", "-x", str(path)],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    m = re.search(r"^start address (0x[0-9a-f]+)$", out, re.M)
    sec_re = re.compile(
        r"^\s*\d+ (\S+)\s+([0-9a-f]+)\s+([0-9a-f]+)\s+[0-9a-f]+\s+"
        r"[0-9a-f]+\s+2\*\*\d+$",
        re.M,
    )
    sections = {
        name: (int(size, 16), int(vma, 16))
        for name, size, vma in sec_re.findall(out)
    }
    dlls = {
        d.lower()
        for d in re.findall(r"^\tDLL Name: (\S+)$", out, re.M)
    }
    functions: set[str] = set()
    in_imports = False
    for line in out.splitlines():
        if "The Import Tables" in line:
            in_imports = True
        elif in_imports and line.startswith("PE File Base Relocations"):
            break
        elif in_imports:
            fm = re.match(r"^\s+[0-9a-f]+\s+\d+\s+(\S+)\s*$", line)
            if fm:
                functions.add(fm.group(1))
    return {
        "start": int(m.group(1), 16) if m else 0,
        "sections": sections,
        "dlls": dlls,
        "functions": functions,
    }


def _measure_fixture(path: Path, want_sha: str, want_fmt: str) -> dict:
    """Measure probe-vs-objdump parity on one real PE fixture."""
    sha = hashlib.sha256(path.read_bytes()).hexdigest()
    entry: dict = {
        "path": str(path.relative_to(ROOT)),
        "sha256": sha,
        "sha256_pinned": sha == want_sha,
    }
    rc, got = _run_probe_json("--pe", str(path))
    if rc != 0 or not got or not got.get("ok"):
        entry["ok"] = False
        entry["error"] = "probe failed rc=%d" % rc
        return entry
    truth = _objdump_truth(path)
    image_base = int(got["image_base"], 16)
    sec_parity = all(
        s["name"] in truth["sections"]
        and truth["sections"][s["name"]][0] == s["vsize"]
        and truth["sections"][s["name"]][1]
        == int(s["vaddr"], 16) + image_base
        for s in got["sections"]
    ) and len(got["sections"]) == len(truth["sections"])
    probe_dlls = {i["dll"].lower() for i in got["imports"]}
    probe_fns = {f for i in got["imports"] for f in i["functions"]}
    entry.update(
        {
            "format": got["format"],
            "format_ok": got["format"] == want_fmt,
            "entry_va": got["entry_va"],
            "entry_matches_objdump": int(got["entry_va"], 16)
            == truth["start"],
            "section_count": len(got["sections"]),
            "sections_match_objdump": sec_parity,
            "import_dlls": sorted(probe_dlls),
            "imports_match_objdump": probe_dlls == truth["dlls"]
            and probe_fns == truth["functions"],
            "import_function_count": got["import_function_count"],
        }
    )
    entry["ok"] = all(
        entry[k]
        for k in (
            "sha256_pinned",
            "format_ok",
            "entry_matches_objdump",
            "sections_match_objdump",
            "imports_match_objdump",
        )
    )
    return entry


def _measure_negatives() -> dict:
    """Truncated/corrupt copies must fail loud (rc!=0, ok:false)."""
    raw = PE_FIXTURES[0][0].read_bytes()
    rc, got = _run_probe_json("--pe", str(PE_FIXTURES[0][0]))
    idata = next(s for s in got["sections"] if s["name"] == ".idata")
    pe_off = int.from_bytes(raw[0x3C:0x40], "little")
    opt_off = pe_off + 4 + 20
    cases = {
        "tiny": raw[:32],
        "headers_only": raw[:400],
        "mid_imports": raw[: idata["raw_off"] + 300],
        "bad_pe_sig": raw[:pe_off] + b"PX\0\0" + raw[pe_off + 4:],
        "bad_mz": b"NZ" + raw[2:],
        "bad_opt_magic": (
            raw[:opt_off] + b"\x99\x99" + raw[opt_off + 2:]
        ),
    }
    results: dict[str, bool] = {}
    with tempfile.TemporaryDirectory(prefix="spark-pe-probe-") as td:
        for name, blob in cases.items():
            p = Path(td) / name
            p.write_bytes(blob)
            rc, got = _run_probe_json("--pe", str(p))
            results[name] = (
                rc != 0
                and got is not None
                and got.get("ok") is False
                and bool(got.get("error"))
            )
    return {"cases": results, "all_loud": all(results.values())}


def main() -> int:
    """Run the measured PE probe and write probe JSON."""
    if not PROBE_BIN.is_file():
        print("missing %s (run: make spark-binary-probe)" % PROBE_BIN)
        return 2
    fixtures = [_measure_fixture(*f) for f in PE_FIXTURES]
    negatives = _measure_negatives()
    ok = all(f.get("ok") for f in fixtures) and negatives["all_loud"]
    payload = {
        "capability": "multi_format_elf_pe",
        "probe": "tools/probe_pe.py",
        "input_sha256": fixtures[0]["sha256"],
        "measured": True,
        "ok": ok,
        "details": {
            "binary": "spark-binary-probe --pe (auto-detect via "
            "--understand)",
            "fixtures": fixtures,
            "negative_cases": negatives["cases"],
            "ground_truth": "objdump -x",
        },
        "ts": datetime.now(timezone.utc).isoformat(),
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, indent=2) + "\n")
    print(json.dumps(payload, indent=2))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
