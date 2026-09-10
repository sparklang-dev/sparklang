#!/usr/bin/env python3
"""LLM-assist decompile for SPARK_BC dumps — grounded, offline-first.

Offline structural explainer (default): deterministic explanation
computed from a real .sparkbc dump — sections, opcode histogram,
string-pool summary, xref narrative. No network, no LLM; output
tracks the input bytes.

--llm accelerator: sends the dump JSON to the on-box Bifrost gateway
(AI_GATEWAY_URL, default http://127.0.0.1:4000) using the `code`
alias — never a hardcoded vendor model string. If the gateway wants
a virtual key, SPARK_GATEWAY_KEY is read from the environment
(never from code). 401/402/429/unreachable are normal states:
degrade to the offline explainer.

Grounding validator (always on): every opcode mnemonic or symbol
reference the assist output mentions must exist in the actual dump,
recomputed from the real bytes. Fabricated content = loud nonzero
exit (rc 3). This is the measurable grounding probe.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT / "python") not in sys.path:
    sys.path.insert(0, str(ROOT / "python"))

from sparklang.model_lab.bc_dump import (  # noqa: E402
    OP_NAME,
    analyze_bc,
    load_sparkbc,
)

DEFAULT_GATEWAY = "http://127.0.0.1:4000"
DEFAULT_ALIAS = "code"

# Uppercase prose words that are not opcode claims.
_PROSE_WORDS = {
    "ASCII", "API", "BC", "CLI", "CPU", "ELF", "GPU", "GUI", "HEX",
    "HTTP", "HTTPS", "IDK", "JSON", "LLM", "NOTE", "OK", "PE",
    "RPC", "SHA", "SPARK", "SPBC", "SQL", "URL", "UTF", "XREF",
    "XREFS",
}

_CAPS_TOKEN = re.compile(r"\b[A-Z][A-Z0-9_]{2,}\b")
_STR_REF = re.compile(r"\bstr(\d+)\b")
_CONST_REF = re.compile(r"\bconst(\d+)\b")
_BACKTICK_CAPS = re.compile(r"`([A-Z][A-Z0-9_]{2,})`")
_OPCODE_CLAIM = re.compile(r"\bopcode\s+`?([A-Z][A-Z0-9_]{2,})`?")


def load_analysis(path: str | Path) -> dict:
    """Load a real .sparkbc file into the structured analysis dict."""
    return analyze_bc(load_sparkbc(path))


def opcode_histogram(analysis: dict) -> dict[str, list[int]]:
    """Map opcode mnemonic → sorted ip list (deterministic)."""
    hist: dict[str, list[int]] = {}
    for op in analysis["ops"]:
        hist.setdefault(op["name"], []).append(op["ip"])
    return dict(
        sorted(hist.items(), key=lambda kv: (-len(kv[1]), kv[0]))
    )


def offline_explain(analysis: dict) -> str:
    """Deterministic structural explainer computed from the dump."""
    lines = [
        "# SPARK_BC decompile assist (offline structural explainer)",
        "source: %s" % analysis["path"],
        "sha256: %s" % analysis["sha256"],
        "size: %d bytes · version %d · strings %d · consts %d · "
        "code %d bytes" % (
            analysis["size"],
            analysis["version"],
            analysis["nstrings"],
            analysis["nconsts"],
            analysis["ncode"],
        ),
        "",
        "## Sections",
    ]
    for sec in analysis["sections"]:
        lines.append(
            "- %s off=%d size=%d (%s)"
            % (sec["name"], sec["off"], sec["size"], sec["note"])
        )
    hist = opcode_histogram(analysis)
    lines.append("")
    lines.append("## Opcode histogram (%d ops)" % len(analysis["ops"]))
    for name, ips in hist.items():
        at = ", ".join("code+%d" % ip for ip in ips)
        lines.append("- %s ×%d (%s)" % (name, len(ips), at))
    symbols = analysis["symbols"]
    total = sum(s["bytes"] for s in symbols)
    lines.append("")
    lines.append(
        "## String pool (%d strings, %d bytes)" % (len(symbols), total)
    )
    str_to_consts = analysis["xrefs"]["str_to_consts"]
    const_to_ops = analysis["xrefs"]["const_to_ops"]
    for sym in symbols:
        sid = sym["id"]
        consts = str_to_consts.get(sid, [])
        users: list[str] = []
        for ci in consts:
            for ref in const_to_ops.get("const%d" % ci, []):
                users.append("%s@%d" % (ref["name"], ref["ip"]))
        used = (" ← " + ", ".join(users)) if users else " (unused)"
        lines.append(
            "- %s %r (%d bytes)%s"
            % (sid, sym["text"], sym["bytes"], used)
        )
    lines.append("")
    lines.append("## Xref narrative")
    lines.append(
        "- %d ops, %d const→op references"
        % (analysis["xrefs"]["n_ops"],
           analysis["xrefs"]["n_const_refs"])
    )
    for ckey, refs in sorted(const_to_ops.items()):
        at = ", ".join("%s@%d" % (r["name"], r["ip"]) for r in refs)
        lines.append("- %s referenced by %s" % (ckey, at))
    ops = analysis["ops"]
    if ops:
        lines.append("")
        lines.append("## Flow")
        lines.append(
            "- entry: %s@code+%d · exit: %s@code+%d"
            % (ops[0]["name"], ops[0]["ip"], ops[-1]["name"],
               ops[-1]["ip"])
        )
    lines.append("")
    return "\n".join(lines)


def grounding_violations(text: str, analysis: dict) -> list[str]:
    """List grounding violations in assist output (empty = grounded).

    Every known SPARK_BC mnemonic mentioned must occur in the dump;
    backticked / "opcode X" claims must be real dump mnemonics;
    strN / constN symbol references must be in range.
    """
    present = {op["name"] for op in analysis["ops"]}
    known = set(OP_NAME.values())
    errors: list[str] = []
    for token in set(_CAPS_TOKEN.findall(text)):
        if token in known:
            if token not in present:
                errors.append(
                    "opcode %s mentioned but not present in dump"
                    % token
                )
        elif token in _PROSE_WORDS:
            continue
        elif token in set(_BACKTICK_CAPS.findall(text)):
            errors.append(
                "unknown opcode-like token `%s` (not in SPARK_BC "
                "opcode table)" % token
            )
    for token in set(_OPCODE_CLAIM.findall(text)):
        if token not in known:
            errors.append(
                "unknown opcode claim %r (not in SPARK_BC opcode "
                "table)" % token
            )
        elif token not in present:
            errors.append(
                "opcode %s claimed but not present in dump" % token
            )
    for m in set(_STR_REF.findall(text)):
        if int(m) >= analysis["nstrings"]:
            errors.append(
                "symbol str%s out of range (nstrings=%d)"
                % (m, analysis["nstrings"])
            )
    for m in set(_CONST_REF.findall(text)):
        if int(m) >= analysis["nconsts"]:
            errors.append(
                "symbol const%s out of range (nconsts=%d)"
                % (m, analysis["nconsts"])
            )
    return sorted(errors)


def _llm_prompt(analysis: dict) -> list[dict[str, str]]:
    """Build the chat messages for the LLM aid layer."""
    present = sorted({op["name"] for op in analysis["ops"]})
    symbols = analysis["symbols"][:64]
    ops = analysis["ops"][:200]
    dump_view = {
        "format": analysis["format"],
        "sha256": analysis["sha256"],
        "size": analysis["size"],
        "sections": analysis["sections"],
        "opcodes_present": present,
        "ops": [
            {"ip": o["ip"], "name": o["name"], "args": o["args_text"]}
            for o in ops
        ],
        "symbols": [
            {"id": s["id"], "text": s["text"]} for s in symbols
        ],
    }
    system = (
        "You are a SPARK_BC decompile aid. Explain what this "
        "bytecode program does, in 4-8 sentences. Ground rules: "
        "mention ONLY opcodes from opcodes_present; reference "
        "strings as strN and consts as constN; never invent "
        "opcodes, symbols, strings, or capabilities. If unsure, "
        "say what is structurally known instead."
    )
    user = (
        "SPARK_BC dump JSON:\n"
        + json.dumps(dump_view, indent=1)
        + "\nExplain the program's behavior."
    )
    return [
        {"role": "system", "content": system},
        {"role": "user", "content": user},
    ]


def llm_explain(
    analysis: dict,
    *,
    base_url: str,
    model: str,
    timeout_s: float = 30.0,
) -> str | None:
    """POST the dump to the local gateway; None = degrade offline.

    402 (budget) and 429 (rate limit) are normal states, as is an
    unreachable gateway — the caller degrades to offline mode.
    """
    url = base_url.rstrip("/") + "/v1/chat/completions"
    body = {
        "model": model,
        "messages": _llm_prompt(analysis),
        "temperature": 0,
        "max_tokens": 512,
    }
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    # Bifrost virtual key via env only (repo convention) — never in
    # code. Absent key on a key-gated gateway → 401 → degrade.
    key = os.environ.get("SPARK_GATEWAY_KEY")
    if key:
        req.add_header("Authorization", "Bearer %s" % key)
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        if exc.code in (402, 429):
            return None
        return None
    except (urllib.error.URLError, TimeoutError, OSError, ValueError):
        return None
    try:
        return str(payload["choices"][0]["message"]["content"]).strip()
    except (KeyError, IndexError, TypeError):
        return None


def run_assist(
    path: str | Path,
    *,
    use_llm: bool,
    base_url: str,
    model: str,
) -> tuple[str, dict]:
    """Run the assist; return (text, meta). Raises on grounding fail."""
    analysis = load_analysis(path)
    offline = offline_explain(analysis)
    parts = [offline]
    meta = {
        "mode": "offline",
        "llm": "not_requested",
        "grounding": "pending",
    }
    if use_llm:
        aid = llm_explain(analysis, base_url=base_url, model=model)
        if aid is None:
            meta["llm"] = "degraded_offline"
        else:
            meta["llm"] = "ok"
            meta["mode"] = "offline+llm"
            parts.append("## LLM aid layer (advisory, grounded)\n")
            parts.append(aid)
            parts.append("")
    text = "\n".join(parts)
    violations = grounding_violations(text, analysis)
    if violations:
        meta["grounding"] = "fail"
        raise GroundingError(violations, meta)
    meta["grounding"] = "pass"
    meta["sha256"] = analysis["sha256"]
    meta["n_ops"] = len(analysis["ops"])
    return text, meta


class GroundingError(Exception):
    """Assist output mentioned opcodes/symbols absent from the dump."""

    def __init__(self, violations: list[str], meta: dict) -> None:
        super().__init__("; ".join(violations))
        self.violations = violations
        self.meta = meta


def main(argv: list[str] | None = None) -> int:
    """CLI: offline explainer default; --llm adds the aid layer."""
    ap = argparse.ArgumentParser(prog="decompile-assist")
    ap.add_argument("sparkbc", help="path to a real .sparkbc file")
    ap.add_argument(
        "--llm",
        action="store_true",
        help="add LLM aid layer via local gateway (alias `code`)",
    )
    ap.add_argument("--json", action="store_true", help="JSON output")
    ap.add_argument(
        "--gateway",
        default=os.environ.get("AI_GATEWAY_URL", DEFAULT_GATEWAY),
        help="OpenAI-compatible gateway base URL",
    )
    ap.add_argument(
        "--model",
        default=os.environ.get("SPARK_DECOMPILE_ALIAS", DEFAULT_ALIAS),
        help="gateway alias (never a vendor model string)",
    )
    args = ap.parse_args(argv)
    try:
        text, meta = run_assist(
            args.sparkbc,
            use_llm=args.llm,
            base_url=args.gateway,
            model=args.model,
        )
    except GroundingError as exc:
        for v in exc.violations:
            print("grounding violation: %s" % v, file=sys.stderr)
        print("assist output rejected (fabricated content)", file=sys.stderr)
        return 3
    except (OSError, ValueError) as exc:
        print("decompile-assist: %s" % exc, file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps({"ok": True, "meta": meta, "text": text}))
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
