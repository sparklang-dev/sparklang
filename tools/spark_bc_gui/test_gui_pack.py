#!/usr/bin/env python3
"""Smoke tests for SDK pack manifest + GUI core (headless)."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))
if str(ROOT / "python") not in sys.path:
    sys.path.insert(0, str(ROOT / "python"))


class TestGuiCore(unittest.TestCase):
    """Headless compile + decompile via real code paths."""

    @classmethod
    def setUpClass(cls) -> None:
        """Ensure bootstrap exists for compile smoke."""
        boot = ROOT / "spark-bootstrap"
        if not boot.is_file():
            subprocess.run(
                ["make", "spark-bootstrap"],
                cwd=str(ROOT),
                check=True,
            )

    def test_decompile_published_builder(self) -> None:
        """Decompile a committed ``.sparkbc`` example."""
        from spark_bc_gui import core

        bc = ROOT / "docs/examples/spark-builder.sparkbc"
        self.assertTrue(bc.is_file(), "missing published sparkbc")
        text = core.decompile_sparkbc(bc, root=ROOT)
        self.assertIn("SPBC", text)
        self.assertIn("sha256:", text)
        self.assertIn("## Header", text)

    def test_compile_sample_roundtrip(self) -> None:
        """Compile sample source then decompile the bytes."""
        from spark_bc_gui import core

        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "sample.sparkbc"
            result = core.compile_source_text(
                core.sample_source(),
                out=out,
                root=ROOT,
            )
            self.assertTrue(Path(result["out"]).is_file())
            self.assertGreater(result["size"], 7)
            dump = core.decompile_sparkbc(
                result["out"],
                source=result["source"],
                command=result["command"],
                root=ROOT,
            )
            self.assertIn("magic: SPBC", dump)

    def test_browse_opcodes_and_sync(self) -> None:
        """Browse opcode list + source↔dump sync map."""
        from spark_bc_gui import core

        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "browse.sparkbc"
            result = core.compile_source_text(
                core.sample_source(),
                out=out,
                root=ROOT,
            )
            rows = core.browse_opcodes(result["out"], root=ROOT)
            self.assertGreater(len(rows), 0)
            self.assertIn("dump_needle", rows[0])
            sync = core.sync_map(
                core.sample_source(),
                result["out"],
                root=ROOT,
            )
            self.assertEqual(len(sync), len(rows))
            linked = [m for m in sync if m.get("source_line")]
            self.assertGreater(len(linked), 0)

    def test_ask_factual_and_report(self) -> None:
        """Factual Ask + markdown report export (headless)."""
        from spark_bc_gui import core

        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "ask.sparkbc"
            result = core.compile_source_text(
                core.sample_source(),
                out=out,
                root=ROOT,
            )
            dump = core.decompile_sparkbc(result["out"], root=ROOT)
            ops = core.browse_opcodes(result["out"], root=ROOT)
            ans = core.ask_over_dump(
                "list opcodes",
                dump_text=dump,
                ops=ops,
                sha256=result["sha256"],
                sparkbc=result["out"],
                root=ROOT,
            )
            self.assertEqual(ans["engine"], "factual")
            self.assertIn("Opcodes", ans["answer"])
            self.assertNotIn("beats_claude", ans)
            md = core.export_report_markdown(
                dump_text=dump,
                ops=ops,
                sha256=result["sha256"],
                sparkbc_path=result["out"],
                ask_notes="Q: list opcodes\nA: ok",
            )
            self.assertIn("# Spark IDE analysis", md)
            self.assertIn(result["sha256"], md)
            self.assertNotIn("beats_claude", md)

    def test_weights_list_and_play(self) -> None:
        """List safetensors and play one tensor on CPU."""
        from spark_bc_gui import core

        files = core.list_weight_files(ROOT)
        self.assertGreater(len(files), 0)
        path = files[0]["path"]
        summary = core.summarize_weights(path, root=ROOT)
        self.assertGreater(summary["count"], 0)
        name = summary["tensors"][0]["name"]
        play = core.play_tensor(path, name, root=ROOT)
        self.assertEqual(play["name"], name)
        self.assertEqual(play["device"], "cpu")
        self.assertIn("never RTX PRO 6000", play["note"])

    def test_helper_opcodes_sheet(self) -> None:
        """One-click helper: opcode sheet runs headless."""
        from spark_bc_gui import core

        helpers = core.list_helpers(ROOT)
        self.assertTrue(any(h["key"] == "opcodes" for h in helpers))
        result = core.run_helper("opcodes", root=ROOT)
        self.assertTrue(result["ok"])
        self.assertIn("HALT", result["stdout"])


class TestSdkPack(unittest.TestCase):
    """``make sdk-pack`` layout + MANIFEST required paths."""

    @classmethod
    def setUpClass(cls) -> None:
        """Build the pack once for this test class."""
        env = os.environ.copy()
        subprocess.run(
            ["bash", str(TOOLS / "package_sdk_ide.sh")],
            cwd=str(ROOT),
            check=True,
            env=env,
        )
        cls.manifest = ROOT / "out/sdk-pack/MANIFEST.json"
        if not cls.manifest.is_file():
            raise RuntimeError("sdk-pack did not write MANIFEST.json")

    def test_manifest_lists_required_paths(self) -> None:
        """MANIFEST.json exists and lists expected pack paths."""
        path = ROOT / "out/sdk-pack/MANIFEST.json"
        self.assertTrue(path.is_file(), "run package_sdk_ide.sh first")
        data = json.loads(path.read_text(encoding="utf-8"))
        self.assertIn("required_paths", data)
        self.assertIn("sha256", data)
        self.assertIn("tarball", data)
        self.assertIn("bin/spark-bc-gui", data["required_paths"])
        self.assertIn("ide/spark-ide-extension/package.json", data["required_paths"])
        self.assertIn(
            "gui/spark_bc_gui/app.py", data["required_paths"]
        )
        tarball = ROOT / "out/sdk-pack" / data["tarball"]
        self.assertTrue(tarball.is_file())
        self.assertGreater(data["size_bytes"], 1000)

    def test_tarball_contains_required(self) -> None:
        """Extracted tarball includes runtime, SDK, IDE, GUI."""
        import tarfile

        path = ROOT / "out/sdk-pack/MANIFEST.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        tarball = ROOT / "out/sdk-pack" / data["tarball"]
        with tarfile.open(tarball, "r:gz") as tar:
            names = set(tar.getnames())
        prefix = data["name"]
        for rel in data["required_paths"]:
            full = "%s/%s" % (prefix, rel)
            self.assertIn(
                full,
                names,
                "tarball missing %s" % full,
            )

    def test_gui_module_import(self) -> None:
        """GUI package imports without opening a display."""
        import spark_bc_gui
        import spark_bc_gui.core as core

        self.assertTrue(hasattr(core, "compile_spark"))
        self.assertTrue(hasattr(core, "decompile_sparkbc"))
        self.assertIn("SparkLang", spark_bc_gui.__doc__ or "SparkLang")

    def test_helpers_and_shadows_in_pack(self) -> None:
        """Pack ships helpers + shadows scripts."""
        path = ROOT / "out/sdk-pack/MANIFEST.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        req = set(data["required_paths"])
        self.assertIn("helpers/compile.sh", req)
        self.assertIn("shadows/shadow_copy.sh", req)
        self.assertIn("bin/spark-helper-opcodes", req)
        self.assertIn("bin/spark-shadow-verify", req)

    def test_opcode_sheet_and_fixture_lint(self) -> None:
        """Helper tools run headless against real tables/fixtures."""
        sheet = subprocess.run(
            [
                sys.executable,
                str(TOOLS / "spark_helpers/opcode_sheet.py"),
            ],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertIn("0x", sheet.stdout)
        self.assertIn("HALT", sheet.stdout)
        fixture = (
            ROOT / "examples/fixtures/train/dataset.jsonl"
        )
        if fixture.is_file():
            lint = subprocess.run(
                [
                    sys.executable,
                    str(TOOLS / "spark_helpers/fixture_lint.py"),
                    str(fixture),
                ],
                cwd=str(ROOT),
                capture_output=True,
                text=True,
                check=True,
            )
            self.assertIn("OK", lint.stdout)


if __name__ == "__main__":
    raise SystemExit(unittest.main(verbosity=2))
