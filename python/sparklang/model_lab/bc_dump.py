"""Decode SPARK_BC (docs/SPARK_BC.md). Not neural weights.

Reads a real .sparkbc file. Does not invent opcodes or hex.
"""

from __future__ import annotations

import hashlib
import struct
from pathlib import Path
from typing import Any

MAGIC = b"SPBC"
VERSION = 1

# Operand count = number of u16 const indices (HALT / PIPELINE / VOICE
# / WITH_END have none). From SPARK_BC.md + bootstrap/bc_opcodes.h.
OP_ARITY: dict[int, int] = {
    0x00: 0,  # HALT
    0x01: 1,  # MODEL
    0x02: 2,  # ASK
    0x03: 1,  # PRINT
    0x04: 2,  # LET
    0x05: 2,  # CLASSIFY
    0x06: 3,  # EXTRACT
    0x07: 0,  # PIPELINE
    0x09: 1,  # LISTEN
    0x0A: 1,  # SPEAK
    0x0D: 0,  # VOICE
    0x0E: 2,  # ENGINE_FETCH
    0x0F: 2,  # ENGINE_FETCH_PARSE
    0x10: 2,  # ENGINE_PARSE
    0x11: 1,  # ENGINE_CSS
    0x12: 1,  # ENGINE_LAYOUT
    0x13: 1,  # ENGINE_PAINT_BOXES
    0x14: 1,  # ENGINE_PAINT_FIXTURE
    0x15: 2,  # ENGINE_SHOW
    0x16: 1,  # ENGINE_RENDER
    0x17: 2,  # IDE_OPEN
    0x18: 1,  # IDE_RUN
    0x19: 1,  # IDE_ASK
    0x1A: 2,  # IDE_SHOW
    0x1B: 2,  # REVIEW_PATH
    0x1C: 2,  # REVIEW_TEXT
    0x1D: 2,  # BROWSER_RUN
    0x1E: 2,  # BROWSER_GOTO
    0x1F: 1,  # MITM_ENABLE
    0x20: 1,  # TOOL
    0x21: 1,  # WITH
    0x22: 0,  # WITH_END
    0x23: 2,  # EMBED
    0x24: 2,  # RETRIEVE
    0x25: 3,  # EXPECT
    0x26: 5,  # TRAIN
    0x27: 2,  # TRAIN_STATUS
    0x28: 2,  # STEP
}

OP_NAME: dict[int, str] = {
    0x00: "HALT",
    0x01: "MODEL",
    0x02: "ASK",
    0x03: "PRINT",
    0x04: "LET",
    0x05: "CLASSIFY",
    0x06: "EXTRACT",
    0x07: "PIPELINE",
    0x09: "LISTEN",
    0x0A: "SPEAK",
    0x0D: "VOICE",
    0x0E: "ENGINE_FETCH",
    0x0F: "ENGINE_FETCH_PARSE",
    0x10: "ENGINE_PARSE",
    0x11: "ENGINE_CSS",
    0x12: "ENGINE_LAYOUT",
    0x13: "ENGINE_PAINT_BOXES",
    0x14: "ENGINE_PAINT_FIXTURE",
    0x15: "ENGINE_SHOW",
    0x16: "ENGINE_RENDER",
    0x17: "IDE_OPEN",
    0x18: "IDE_RUN",
    0x19: "IDE_ASK",
    0x1A: "IDE_SHOW",
    0x1B: "REVIEW_PATH",
    0x1C: "REVIEW_TEXT",
    0x1D: "BROWSER_RUN",
    0x1E: "BROWSER_GOTO",
    0x1F: "MITM_ENABLE",
    0x20: "TOOL",
    0x21: "WITH",
    0x22: "WITH_END",
    0x23: "EMBED",
    0x24: "RETRIEVE",
    0x25: "EXPECT",
    0x26: "TRAIN",
    0x27: "TRAIN_STATUS",
    0x28: "STEP",
}


def _u16(data: bytes, off: int) -> tuple[int, int]:
    if off + 2 > len(data):
        raise ValueError("truncated u16 at offset %d" % off)
    return struct.unpack_from("<H", data, off)[0], off + 2


def _u32(data: bytes, off: int) -> tuple[int, int]:
    if off + 4 > len(data):
        raise ValueError("truncated u32 at offset %d" % off)
    return struct.unpack_from("<I", data, off)[0], off + 4


def load_sparkbc(path: str | Path) -> dict[str, Any]:
    """Load and decode a real SPARK_BC file. Fail loud on bad magic."""
    raw = Path(path).read_bytes()
    if len(raw) < 7:
        raise ValueError("file too short for SPARK_BC header")
    if raw[:4] != MAGIC:
        raise ValueError("bad magic %r (want SPBC)" % raw[:4])
    version = raw[4]
    if version != VERSION:
        raise ValueError("version %d (want 1)" % version)
    off = 5
    nstrs, off = _u16(raw, off)
    strings: list[bytes] = []
    for _ in range(nstrs):
        nbytes, off = _u16(raw, off)
        if off + nbytes > len(raw):
            raise ValueError("truncated string pool")
        strings.append(raw[off : off + nbytes])
        off += nbytes
    nconsts, off = _u16(raw, off)
    consts: list[dict[str, int]] = []
    for _ in range(nconsts):
        if off + 3 > len(raw):
            raise ValueError("truncated const pool")
        kind = raw[off]
        payload = struct.unpack_from("<H", raw, off + 1)[0]
        off += 3
        consts.append({"kind": kind, "payload": payload})
    ncode, off = _u32(raw, off)
    if off + ncode > len(raw):
        raise ValueError("truncated code section")
    if off + ncode != len(raw):
        raise ValueError("trailing bytes after code")
    code = raw[off : off + ncode]
    return {
        "path": str(path),
        "raw": raw,
        "size": len(raw),
        "sha256": hashlib.sha256(raw).hexdigest(),
        "magic": "SPBC",
        "version": version,
        "strings": strings,
        "consts": consts,
        "code": code,
        "code_off": off,
        "ncode": ncode,
    }


def _const_text(bc: dict[str, Any], idx: int) -> str:
    if idx >= len(bc["consts"]):
        return "const%d(OOB)" % idx
    c = bc["consts"][idx]
    if c["kind"] != 0:
        return "const%d(kind=%d)" % (idx, c["kind"])
    si = c["payload"]
    if si >= len(bc["strings"]):
        return "const%d->str%d(OOB)" % (idx, si)
    text = bc["strings"][si].decode("utf-8", errors="replace")
    return 'const%d "%s"' % (idx, text)


def decode_ops(bc: dict[str, Any]) -> list[dict[str, Any]]:
    """Walk the code section; fail loud on unknown / truncated ops."""
    code: bytes = bc["code"]
    ip = 0
    ops: list[dict[str, Any]] = []
    while ip < len(code):
        op = code[ip]
        name = OP_NAME.get(op)
        if name is None:
            raise ValueError("unknown opcode 0x%02x at code+%d" % (op, ip))
        arity = OP_ARITY[op]
        need = 1 + 2 * arity
        if ip + need > len(code):
            raise ValueError("truncated %s at code+%d" % (name, ip))
        operands: list[int] = []
        pos = ip + 1
        for _ in range(arity):
            operands.append(struct.unpack_from("<H", code, pos)[0])
            pos += 2
        hex_bytes = " ".join("%02x" % b for b in code[ip:pos])
        ops.append(
            {
                "ip": ip,
                "op": op,
                "name": name,
                "operands": operands,
                "hex": hex_bytes,
            }
        )
        ip = pos
        if name == "HALT":
            break
    if ip != len(code):
        raise ValueError("code bytes remain after HALT")
    return ops


def hex_preview(raw: bytes, n: int = 32) -> str:
    """Space-separated hex of the first n bytes."""
    return " ".join("%02x" % b for b in raw[:n])


def format_xxd(raw: bytes, width: int = 16) -> str:
    """Hex+ASCII dump of the whole file (xxd-style)."""
    lines: list[str] = []
    for i in range(0, len(raw), width):
        chunk = raw[i : i + width]
        hx = " ".join("%02x" % b for b in chunk)
        hx = hx.ljust(width * 3 - 1)
        ascii_part = "".join(
            chr(b) if 32 <= b < 127 else "." for b in chunk
        )
        lines.append("%08x: %s  %s" % (i, hx, ascii_part))
    return "\n".join(lines)


def symbol_table(bc: dict[str, Any]) -> list[dict[str, Any]]:
    """String-pool symbols (SPARK_BC has no ELF dynsym)."""
    out: list[dict[str, Any]] = []
    for i, raw in enumerate(bc["strings"]):
        text = raw.decode("utf-8", errors="replace")
        out.append(
            {
                "id": "str%d" % i,
                "kind": "string",
                "index": i,
                "bytes": len(raw),
                "text": text,
            }
        )
    return out


def build_xrefs(bc: dict[str, Any]) -> dict[str, Any]:
    """Const↔string and opcode→const cross-refs (SPARK_BC-native)."""
    ops = decode_ops(bc)
    const_to_ops: dict[str, list[dict[str, Any]]] = {}
    str_to_consts: dict[str, list[int]] = {}
    for i, c in enumerate(bc["consts"]):
        if c["kind"] == 0:
            key = "str%d" % c["payload"]
            str_to_consts.setdefault(key, []).append(i)
    for op in ops:
        for a in op["operands"]:
            key = "const%d" % a
            const_to_ops.setdefault(key, []).append(
                {
                    "ip": op["ip"],
                    "name": op["name"],
                    "op": op["op"],
                }
            )
    return {
        "const_to_ops": const_to_ops,
        "str_to_consts": str_to_consts,
        "n_ops": len(ops),
        "n_const_refs": sum(len(v) for v in const_to_ops.values()),
    }


def structured_sections(bc: dict[str, Any]) -> list[dict[str, Any]]:
    """Byte-range sections of a SPARK_BC file."""
    raw: bytes = bc["raw"]
    # Walk layout to compute pool bounds (same as load_sparkbc).
    off = 5
    nstrs, off = _u16(raw, off)
    str_start = off
    for _ in range(nstrs):
        nbytes, off = _u16(raw, off)
        off += nbytes
    str_end = off
    nconsts, off = _u16(raw, off)
    const_start = off
    off += 3 * nconsts
    const_end = off
    _ncode, off = _u32(raw, off)
    code_start = off
    return [
        {"name": "magic", "off": 0, "size": 4, "note": "SPBC"},
        {"name": "version", "off": 4, "size": 1, "note": "u8"},
        {
            "name": "string_pool",
            "off": str_start,
            "size": str_end - str_start,
            "note": "nstrings=%d" % nstrs,
        },
        {
            "name": "const_pool",
            "off": const_start,
            "size": const_end - const_start,
            "note": "nconsts=%d" % nconsts,
        },
        {
            "name": "code",
            "off": code_start,
            "size": bc["ncode"],
            "note": "ncode=%d" % bc["ncode"],
        },
    ]


def analyze_bc(bc: dict[str, Any]) -> dict[str, Any]:
    """Structured analysis dict for JSON/HTML/project export."""
    ops = decode_ops(bc)
    return {
        "format": "SPARK_BC",
        "path": bc["path"],
        "sha256": bc["sha256"],
        "size": bc["size"],
        "magic": bc["magic"],
        "version": bc["version"],
        "nstrings": len(bc["strings"]),
        "nconsts": len(bc["consts"]),
        "ncode": bc["ncode"],
        "code_off": bc["code_off"],
        "first32_hex": hex_preview(bc["raw"], 32),
        "sections": structured_sections(bc),
        "symbols": symbol_table(bc),
        "xrefs": build_xrefs(bc),
        "ops": [
            {
                "ip": o["ip"],
                "op": o["op"],
                "name": o["name"],
                "operands": o["operands"],
                "hex": o["hex"],
                "args_text": [
                    _const_text(bc, a) for a in o["operands"]
                ],
            }
            for o in ops
        ],
        "privacy": "local-only",
        "note": (
            "Deterministic SPARK_BC inspect — not ELF/PE decompile, "
            "not lossless .spark source recovery."
        ),
    }


def format_dump(
    bc: dict[str, Any],
    *,
    source: str,
    command: str,
    label: str,
) -> str:
    """Human dump: command, sha256, sections, symbols, xrefs, ops."""
    analysis = analyze_bc(bc)
    ops = analysis["ops"]
    lines = [
        "# %s" % label,
        "# SPARK_BC is orchestration bytecode — not neural weights.",
        "# Not HuggingFace. Not imported tensors. Spark's own binary.",
        "#",
        "# Source: %s" % source,
        "# Command: %s" % command,
        "# sha256: %s" % bc["sha256"],
        "# size: %d bytes" % bc["size"],
        "#",
        "# First 32 hex bytes:",
        "# %s" % hex_preview(bc["raw"], 32),
        "#",
        "# File layout (little-endian, docs/SPARK_BC.md):",
        "#   offset 0  magic 'S''P''B''C'",
        "#   offset 4  version 0x01",
        "#   then u16 nstrings, string pool, u16 nconsts,",
        "#   const pool (u8 kind + u16 payload), u32 ncode, code",
        "",
        "## xxd",
        format_xxd(bc["raw"]),
        "",
        "## Header",
        "magic: %s" % bc["magic"],
        "version: %d" % bc["version"],
        "nstrings: %d" % len(bc["strings"]),
        "nconsts: %d" % len(bc["consts"]),
        "ncode: %d" % bc["ncode"],
        "code_off: %d" % bc["code_off"],
        "",
        "## Sections",
    ]
    for sec in analysis["sections"]:
        lines.append(
            "%s  off=%d size=%d  %s"
            % (sec["name"], sec["off"], sec["size"], sec["note"])
        )
    lines.extend(["", "## Symbols (string pool)"])
    for sym in analysis["symbols"]:
        lines.append(
            "%s  %r (%d bytes)"
            % (sym["id"], sym["text"], sym["bytes"])
        )
    lines.extend(["", "## String pool"])
    for i, s in enumerate(bc["strings"]):
        text = s.decode("utf-8", errors="replace")
        lines.append("%d: %r (%d bytes)" % (i, text, len(s)))
    lines.extend(["", "## Constant pool (kind 0 = STR → string index)"])
    for i, c in enumerate(bc["consts"]):
        extra = ""
        if c["kind"] == 0 and c["payload"] < len(bc["strings"]):
            extra = " → %r" % bc["strings"][c["payload"]].decode(
                "utf-8", errors="replace"
            )
        lines.append(
            "%d: kind=%d payload=%d%s"
            % (i, c["kind"], c["payload"], extra)
        )
    xrefs = analysis["xrefs"]
    lines.extend(
        [
            "",
            "## Xrefs (const → ops; str → consts)",
            "n_ops: %d" % xrefs["n_ops"],
            "n_const_refs: %d" % xrefs["n_const_refs"],
        ]
    )
    for ckey, refs in sorted(xrefs["const_to_ops"].items()):
        ips = ", ".join(
            "%s@%d" % (r["name"], r["ip"]) for r in refs
        )
        lines.append("%s → %s" % (ckey, ips))
    for skey, cidxs in sorted(xrefs["str_to_consts"].items()):
        lines.append(
            "%s ← consts %s"
            % (skey, ", ".join(str(i) for i in cidxs))
        )
    lines.extend(["", "## Code (opcode + u16le const indices)"])
    for op in ops:
        args = " ".join(op["args_text"])
        lines.append(
            "code+%d  %s  %s (0x%02x) %s"
            % (op["ip"], op["hex"], op["name"], op["op"], args)
        )
    lines.append("")
    return "\n".join(lines)


def format_dump_json(
    bc: dict[str, Any],
    *,
    source: str,
    command: str,
    label: str,
) -> dict[str, Any]:
    """JSON export of structured SPARK_BC analysis."""
    payload = analyze_bc(bc)
    payload["label"] = label
    payload["source"] = source
    payload["command"] = command
    return payload


def _html_esc(s: Any) -> str:
    """Escape text for local HTML report bodies."""
    return (
        str(s)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def format_dump_html(
    bc: dict[str, Any],
    *,
    source: str,
    command: str,
    label: str,
) -> str:
    """Minimal self-contained HTML report (local file, no CDN)."""
    a = analyze_bc(bc)
    esc = _html_esc
    rows = []
    for op in a["ops"]:
        rows.append(
            "<tr><td>%d</td><td>%s</td><td>%s</td><td>%s</td></tr>"
            % (
                op["ip"],
                esc(op["hex"]),
                esc(op["name"]),
                esc(" ".join(op["args_text"])),
            )
        )
    sec_rows = []
    for sec in a["sections"]:
        sec_rows.append(
            "<tr><td>%s</td><td>%d</td><td>%d</td><td>%s</td></tr>"
            % (
                esc(sec["name"]),
                sec["off"],
                sec["size"],
                esc(sec["note"]),
            )
        )
    sym_rows = []
    for sym in a["symbols"]:
        sym_rows.append(
            "<tr><td>%s</td><td>%s</td><td>%d</td></tr>"
            % (esc(sym["id"]), esc(repr(sym["text"])), sym["bytes"])
        )
    return "\n".join(
        [
            "<!DOCTYPE html>",
            '<html lang="en"><head><meta charset="utf-8"/>',
            "<title>%s</title>" % esc(label),
            "<style>",
            "body{font:14px/1.45 ui-monospace,monospace;",
            "margin:1.5rem;background:#0f1419;color:#e7ecf3}",
            "h1,h2{font-family:system-ui,sans-serif}",
            "table{border-collapse:collapse;width:100%;",
            "margin:.75rem 0}",
            "th,td{border:1px solid #2a3544;padding:.35rem .5rem;",
            "text-align:left}",
            "th{background:#1a2330}",
            "code{color:#9ecbff}",
            "</style></head><body>",
            "<h1>%s</h1>" % esc(label),
            "<p>Source: <code>%s</code><br/>Command: <code>%s</code>"
            "<br/>sha256: <code>%s</code> · %d bytes · local-only</p>"
            % (esc(source), esc(command), esc(a["sha256"]), a["size"]),
            "<h2>Sections</h2><table><thead><tr>",
            "<th>name</th><th>off</th><th>size</th><th>note</th>",
            "</tr></thead><tbody>",
            *sec_rows,
            "</tbody></table>",
            "<h2>Symbols</h2><table><thead><tr>",
            "<th>id</th><th>text</th><th>bytes</th>",
            "</tr></thead><tbody>",
            *sym_rows,
            "</tbody></table>",
            "<h2>Code</h2><table><thead><tr>",
            "<th>ip</th><th>hex</th><th>op</th><th>args</th>",
            "</tr></thead><tbody>",
            *rows,
            "</tbody></table>",
            "<p><em>SPARK_BC inspect — not ELF/PE decompile; "
            "not lossless source recovery. No frontier-parity claim."
            "</em></p>",
            "</body></html>",
            "",
        ]
    )
