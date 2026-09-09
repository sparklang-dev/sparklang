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


def format_dump(
    bc: dict[str, Any],
    *,
    source: str,
    command: str,
    label: str,
) -> str:
    """Human dump: command, sha256, first 32 hex, header, ops."""
    ops = decode_ops(bc)
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
        "## String pool",
    ]
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
            "%d: kind=%d payload=%d%s" % (i, c["kind"], c["payload"], extra)
        )
    lines.extend(["", "## Code (opcode + u16le const indices)"])
    for op in ops:
        args = " ".join(_const_text(bc, a) for a in op["operands"])
        lines.append(
            "code+%d  %s  %s (0x%02x) %s"
            % (op["ip"], op["hex"], op["name"], op["op"], args)
        )
    lines.append("")
    return "\n".join(lines)
