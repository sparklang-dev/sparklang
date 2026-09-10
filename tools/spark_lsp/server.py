#!/usr/bin/env python3
"""Minimal SparkLang Language Server (stdio JSON-RPC).

Implements initialize, text sync, hover, completion, diagnostics.
Not a full IDE product — editor language support for .spark files.

Usage:
  python3 tools/spark_lsp/server.py
  python3 tools/spark_lsp/server.py --check PATH.spark
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from analyze import completions, diagnose, hover_for  # noqa: E402

_WORD = re.compile(r"[A-Za-z_][\w-]*")


def _read_message() -> dict | None:
    """Read one LSP message from stdin."""
    headers: dict[str, str] = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        if line in (b"\r\n", b"\n"):
            break
        text = line.decode("utf-8", errors="replace").strip()
        if ":" in text:
            k, v = text.split(":", 1)
            headers[k.strip().lower()] = v.strip()
    length = int(headers.get("content-length", "0"))
    if length <= 0:
        return None
    body = sys.stdin.buffer.read(length)
    return json.loads(body.decode("utf-8"))


def _write_message(payload: dict) -> None:
    """Write one LSP message to stdout."""
    raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    sys.stdout.buffer.write(
        f"Content-Length: {len(raw)}\r\n\r\n".encode("ascii")
    )
    sys.stdout.buffer.write(raw)
    sys.stdout.buffer.flush()


def _sev(name: str) -> int:
    return {"Error": 1, "Warning": 2, "Information": 3, "Hint": 4}.get(
        name, 3
    )


def _publish_diags(uri: str, text: str) -> None:
    items = []
    for d in diagnose(text):
        items.append(
            {
                "range": {
                    "start": {
                        "line": d["line"],
                        "character": d["character"],
                    },
                    "end": {
                        "line": d["line"],
                        "character": d["endCharacter"],
                    },
                },
                "severity": _sev(d["severity"]),
                "source": d.get("source", "spark-lsp"),
                "code": d.get("code"),
                "message": d["message"],
            }
        )
    _write_message(
        {
            "jsonrpc": "2.0",
            "method": "textDocument/publishDiagnostics",
            "params": {"uri": uri, "diagnostics": items},
        }
    )


def _word_at(text: str, line: int, character: int) -> str:
    lines = text.splitlines()
    if line < 0 or line >= len(lines):
        return ""
    row = lines[line]
    if character < 0:
        character = 0
    if character > len(row):
        character = len(row)
    left = character
    while left > 0 and _WORD.match(row[left - 1]):
        left -= 1
    right = character
    while right < len(row) and _WORD.match(row[right]):
        right += 1
    return row[left:right]


class Session:
    """In-memory open documents."""

    def __init__(self) -> None:
        self.docs: dict[str, str] = {}

    def handle(self, msg: dict) -> None:
        """Dispatch one request or notification."""
        method = msg.get("method")
        mid = msg.get("id")
        params = msg.get("params") or {}

        if method == "initialize":
            _write_message(
                {
                    "jsonrpc": "2.0",
                    "id": mid,
                    "result": {
                        "capabilities": {
                            "textDocumentSync": 1,
                            "hoverProvider": True,
                            "completionProvider": {
                                "triggerCharacters": [" ", "."]
                            },
                        },
                        "serverInfo": {
                            "name": "spark-lsp",
                            "version": "0.1.0",
                        },
                    },
                }
            )
            return

        if method == "initialized":
            return

        if method == "shutdown":
            _write_message({"jsonrpc": "2.0", "id": mid, "result": None})
            return

        if method == "exit":
            raise SystemExit(0)

        if method == "textDocument/didOpen":
            doc = params.get("textDocument") or {}
            uri = doc.get("uri", "")
            text = doc.get("text", "")
            self.docs[uri] = text
            _publish_diags(uri, text)
            return

        if method == "textDocument/didChange":
            doc = params.get("textDocument") or {}
            uri = doc.get("uri", "")
            changes = params.get("contentChanges") or []
            if changes and "text" in changes[0]:
                text = changes[0]["text"]
                self.docs[uri] = text
                _publish_diags(uri, text)
            return

        if method == "textDocument/didClose":
            uri = (params.get("textDocument") or {}).get("uri", "")
            self.docs.pop(uri, None)
            return

        if method == "textDocument/hover":
            uri = (params.get("textDocument") or {}).get("uri", "")
            pos = params.get("position") or {}
            text = self.docs.get(uri, "")
            word = _word_at(
                text, int(pos.get("line", 0)), int(pos.get("character", 0))
            )
            md = hover_for(word) if word else None
            result = None
            if md:
                result = {"contents": {"kind": "markdown", "value": md}}
            _write_message(
                {"jsonrpc": "2.0", "id": mid, "result": result}
            )
            return

        if method == "textDocument/completion":
            uri = (params.get("textDocument") or {}).get("uri", "")
            pos = params.get("position") or {}
            text = self.docs.get(uri, "")
            prefix = _word_at(
                text, int(pos.get("line", 0)), int(pos.get("character", 0))
            )
            items = completions(prefix)
            _write_message(
                {"jsonrpc": "2.0", "id": mid, "result": items}
            )
            return

        if mid is not None:
            _write_message(
                {
                    "jsonrpc": "2.0",
                    "id": mid,
                    "error": {
                        "code": -32601,
                        "message": f"Method not found: {method}",
                    },
                }
            )


def check_file(path: Path) -> int:
    """CLI: print diagnostics JSON; exit 1 on Error severity."""
    text = path.read_text(encoding="utf-8")
    diags = diagnose(text)
    print(json.dumps({"path": str(path), "diagnostics": diags}, indent=2))
    if any(d["severity"] == "Error" for d in diags):
        return 1
    return 0


def main() -> int:
    """CLI entry for Spark LSP / --check."""
    ap = argparse.ArgumentParser(description="SparkLang LSP")
    ap.add_argument(
        "--check",
        metavar="PATH",
        help="diagnose a .spark file (no stdio server)",
    )
    args = ap.parse_args()
    if args.check:
        return check_file(Path(args.check))

    session = Session()
    while True:
        msg = _read_message()
        if msg is None:
            break
        session.handle(msg)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
