#!/usr/bin/env python3
"""PE32/PE32+ probe parity gates vs objdump ground truth.

Runs ./spark-binary-probe --pe on real PE fixtures (sha256 pinned)
and diffs entry/sections/imports against `objdump -x`. Truncated
and corrupt copies must fail loud (nonzero exit, ok:false JSON).
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROBE = ROOT / "spark-binary-probe"
FIXTURES = ROOT / "examples/fixtures/binary"

WINVER = FIXTURES / "winver-pe32plus.exe"
WINVER_SHA256 = (
    "7f1c587ac7140864a6c1c20f3cb1ea8b20cd6da6a07ed7cd37f27f51386c49cd"
)
CSC = FIXTURES / "csc-pe32.exe"
CSC_SHA256 = (
    "1f1c14c8f7bff93bbe433290963885a3ae3b13da6fdd24decb74c03d692fb6cb"
)


def _sha256(path: Path) -> str:
    """Hash a fixture file."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _run_probe(*args: str) -> tuple[int, dict | None]:
    """Run the probe; return (rc, parsed JSON or None)."""
    proc = subprocess.run(
        [str(PROBE), *args],
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
    assert m, "objdump start address missing"
    sections: dict[str, tuple[int, int]] = {}
    sec_re = re.compile(
        r"^\s*\d+ (\S+)\s+([0-9a-f]+)\s+([0-9a-f]+)\s+[0-9a-f]+\s+"
        r"[0-9a-f]+\s+2\*\*\d+$",
        re.M,
    )
    for name, size, vma in sec_re.findall(out):
        sections[name] = (int(size, 16), int(vma, 16))
    assert sections, "objdump sections missing"
    dlls: set[str] = set()
    functions: set[str] = set()
    for dll in re.findall(r"^\tDLL Name: (\S+)$", out, re.M):
        dlls.add(dll.lower())
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
        "start": int(m.group(1), 16),
        "sections": sections,
        "dlls": dlls,
        "functions": functions,
    }


def _check_parity(path: Path, want_sha: str, want_format: str) -> None:
    """Diff probe JSON against objdump truth on one fixture."""
    assert _sha256(path) == want_sha, "fixture sha256 drift: %s" % path
    rc, got = _run_probe("--pe", str(path))
    assert rc == 0 and got and got["ok"] is True, got
    assert got["format"] == want_format, got["format"]
    truth = _objdump_truth(path)
    assert int(got["entry_va"], 16) == truth["start"], (
        "entry mismatch: probe %s objdump %#x"
        % (got["entry_va"], truth["start"])
    )
    image_base = int(got["image_base"], 16)
    assert len(got["sections"]) == len(truth["sections"]), (
        "section count: probe %d objdump %d"
        % (len(got["sections"]), len(truth["sections"]))
    )
    for sec in got["sections"]:
        name = sec["name"]
        assert name in truth["sections"], "extra section %s" % name
        want_size, want_vma = truth["sections"][name]
        assert sec["vsize"] == want_size, (
            "%s vsize: probe %d objdump %d" % (name, sec["vsize"],
                                               want_size)
        )
        assert int(sec["vaddr"], 16) + image_base == want_vma, (
            "%s vma mismatch" % name
        )
    probe_dlls = {i["dll"].lower() for i in got["imports"]}
    assert probe_dlls == truth["dlls"], (
        "dll set: probe %s objdump %s" % (probe_dlls, truth["dlls"])
    )
    probe_fns = {f for i in got["imports"] for f in i["functions"]}
    assert probe_fns == truth["functions"], (
        "functions: probe-only %s objdump-only %s"
        % (probe_fns - truth["functions"],
           truth["functions"] - probe_fns)
    )
    assert got["import_function_count"] == len(probe_fns)


def test_pe32plus_parity() -> None:
    """winver.exe (real PE32+) matches objdump -x exactly."""
    _check_parity(WINVER, WINVER_SHA256, "pe32plus")


def test_pe32_parity() -> None:
    """csc.exe (real PE32) matches objdump -x exactly."""
    _check_parity(CSC, CSC_SHA256, "pe32")


def test_autodetect_understand() -> None:
    """--understand auto-detects MZ magic and walks PE for real."""
    rc, got = _run_probe("--understand", str(CSC))
    assert rc == 0 and got and got["ok"] is True
    assert got["format"] == "pe32"
    assert got["op"] == "pe"


def _expect_loud_fail(path: Path, note: str) -> None:
    """Probe must exit nonzero with ok:false on bad input."""
    rc, got = _run_probe("--pe", str(path))
    assert rc != 0, "%s: rc=%d out=%s" % (note, rc, got)
    assert got and got["ok"] is False and got.get("error"), (
        "%s: expected loud error JSON, got %s" % (note, got)
    )


def test_truncation_and_corruption_fail_loud() -> None:
    """Truncated/corrupt PE copies never produce fabricated output."""
    raw = WINVER.read_bytes()
    rc, got = _run_probe("--pe", str(WINVER))
    assert rc == 0 and got
    idata = next(s for s in got["sections"] if s["name"] == ".idata")
    mid_imports = idata["raw_off"] + 300
    pe_off = int.from_bytes(raw[0x3C:0x40], "little")
    opt_magic_off = pe_off + 4 + 20
    with tempfile.TemporaryDirectory(prefix="spark-pe-neg-") as td:
        tdp = Path(td)
        cases = {
            "tiny.bin": raw[:32],
            "headers-only.exe": raw[:400],
            "mid-imports.exe": raw[:mid_imports],
            "bad-pe-sig.exe": (
                raw[:pe_off] + b"PX\0\0" + raw[pe_off + 4:]
            ),
            "bad-mz.exe": b"NZ" + raw[2:],
            "bad-opt-magic.exe": (
                raw[:opt_magic_off]
                + b"\x99\x99"
                + raw[opt_magic_off + 2:]
            ),
        }
        for name, blob in cases.items():
            p = tdp / name
            p.write_bytes(blob)
            _expect_loud_fail(p, name)


def main() -> int:
    """Run all PE probe gates."""
    if not PROBE.is_file():
        print("missing %s (run: make spark-binary-probe)" % PROBE)
        return 2
    test_pe32plus_parity()
    test_pe32_parity()
    test_autodetect_understand()
    test_truncation_and_corruption_fail_loud()
    print("ok test_pe_probe")
    return 0


if __name__ == "__main__":
    sys.exit(main())
