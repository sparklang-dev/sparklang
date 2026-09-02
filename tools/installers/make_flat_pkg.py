#!/usr/bin/env python3
"""Build a macOS flat .pkg (xar) from a staged filesystem root.

Uses only stdlib + system cpio/gzip. Suitable for Linux build hosts.
"""
from __future__ import annotations

import gzip
import hashlib
import io
import os
import struct
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zlib
from pathlib import Path


def _walk(root: Path) -> list[str]:
    paths: list[str] = []
    for dirpath, dirnames, filenames in os.walk(root):
        rel = Path(dirpath).relative_to(root)
        if rel != Path("."):
            paths.append(f"./{rel.as_posix()}")
        for name in sorted(dirnames):
            p = (Path(dirpath) / name).relative_to(root)
            paths.append(f"./{p.as_posix()}/")
        for name in sorted(filenames):
            p = (Path(dirpath) / name).relative_to(root)
            paths.append(f"./{p.as_posix()}")
    return paths


def _cpio_odc(root: Path) -> bytes:
    listing = "\n".join(_walk(root)) + "\n"
    proc = subprocess.run(
        ["cpio", "-o", "--format", "odc", "--quiet"],
        input=listing.encode(),
        cwd=root,
        capture_output=True,
        check=True,
    )
    return proc.stdout


def _xar_checksum(data: bytes) -> str:
    return hashlib.sha1(data).hexdigest()


def _build_toc(entries: list[tuple[str, bytes, str]]) -> bytes:
    """entries: (name, data, type) where type is file|directory."""
    pkg = ET.Element(
        "pkg",
        {
            "xmlns": "http://www.google.com/sh/schemas/gdata/pkg",
        },
    )
    toc = ET.SubElement(pkg, "toc")
    for name, data, kind in entries:
        node = ET.SubElement(toc, kind, {"name": name})
        ET.SubElement(node, "data", {"length": str(len(data))})
        ET.SubElement(node, "offset", {"length": "0"})
        csum = ET.SubElement(node, "checksum", {"style": "sha1"})
        csum.text = _xar_checksum(data)
        if kind == "file":
            ET.SubElement(node, "type").text = "file"
            ET.SubElement(node, "mode").text = "0644"
            ET.SubElement(node, "user").text = "root"
            ET.SubElement(node, "group").text = "wheel"
    xml_bytes = ET.tostring(pkg, encoding="utf-8", xml_declaration=True)
    return zlib.compress(xml_bytes)


def _write_xar(out_path: Path, files: dict[str, bytes]) -> None:
    heap = io.BytesIO()
    toc_entries: list[tuple[str, bytes, str]] = []
    for name in sorted(files):
        data = files[name]
        toc_entries.append((name, data, "file"))
        heap.write(data)
    heap_bytes = heap.getvalue()
    toc_compressed = _build_toc(toc_entries)

    header = struct.pack(
        ">IHHQQ",
        0x21726178,  # xar!
        20,
        1,
        len(toc_compressed),
        20 + len(toc_compressed),
    )
    with out_path.open("wb") as fh:
        fh.write(header)
        fh.write(toc_compressed)
        fh.write(heap_bytes)


def _load_resources(resources_dir: Path | None) -> dict[str, bytes]:
    """Load Installer.app welcome/conclusion pages for the flat pkg."""
    out: dict[str, bytes] = {}
    if resources_dir is None or not resources_dir.is_dir():
        return out
    for name in ("welcome.html", "conclusion.html"):
        path = resources_dir / "en.lproj" / name
        if path.is_file():
            key = f"Resources/en.lproj/{name}"
            out[key] = path.read_bytes()
    return out


def make_flat_pkg(
    payload_root: Path,
    out_pkg: Path,
    identifier: str,
    version: str,
    postinstall: str | None = None,
    resources_dir: Path | None = None,
) -> None:
    payload_cpio = _cpio_odc(payload_root)
    payload_gz = gzip.compress(payload_cpio)

    scripts_block = ""
    if postinstall:
        scripts_block = """
  <scripts>
    <postinstall file="./postinstall"/>
  </scripts>"""

    pkg_info = f"""<?xml version="1.0" encoding="utf-8"?>
<pkg-info format-version="2" identifier="{identifier}" version="{version}"
  install-location="/" auth="root">
  <payload installKBytes="{max(1, len(payload_gz) // 1024)}" numFiles="1"/>{scripts_block}
</pkg-info>
"""

    files: dict[str, bytes] = {
        "PackageInfo": pkg_info.encode(),
        "Payload": payload_gz,
    }
    if postinstall:
        files["Scripts/postinstall"] = postinstall.encode()
    files.update(_load_resources(resources_dir))

    _write_xar(out_pkg, files)


def main() -> int:
    if len(sys.argv) not in (6, 7):
        print(
            "usage: make_flat_pkg.py PAYLOAD_ROOT OUT.pkg IDENTIFIER VERSION "
            "POSTINSTALL.sh [RESOURCES_DIR]",
            file=sys.stderr,
        )
        return 2
    payload_root = Path(sys.argv[1])
    out_pkg = Path(sys.argv[2])
    identifier = sys.argv[3]
    version = sys.argv[4]
    postinstall_path = Path(sys.argv[5])
    resources_dir = Path(sys.argv[6]) if len(sys.argv) == 7 else None
    postinstall = postinstall_path.read_text() if postinstall_path.is_file() else None
    make_flat_pkg(
        payload_root, out_pkg, identifier, version, postinstall, resources_dir
    )
    print(f"Built {out_pkg} ({out_pkg.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
