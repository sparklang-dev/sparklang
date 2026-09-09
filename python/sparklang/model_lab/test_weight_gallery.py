"""Unit tests for weight gallery (tiny + large profiles)."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from sparklang.model_lab import weight_gallery as wg
from sparklang.model_lab.weights import emit_init_weights

ROOT = Path(__file__).resolve().parents[3]
BC = ROOT / "docs" / "examples" / "spark-train-step.sparkbc"
INIT = ROOT / "docs" / "examples" / "spark-self.init.safetensors"


class TestWeightGallery(unittest.TestCase):
    """Catalog / inspect / play / compare / generate."""

    def test_profiles_include_large_and_xl(self) -> None:
        """Gallery ships tiny through xl size profiles."""
        self.assertIn("tiny", wg.PROFILES)
        self.assertIn("scale", wg.PROFILES)
        self.assertIn("large", wg.PROFILES)
        self.assertIn("xl", wg.PROFILES)
        self.assertGreaterEqual(wg.PROFILES["large"]["dim"], 128)
        self.assertGreaterEqual(wg.PROFILES["large"]["n_layer"], 8)
        self.assertGreaterEqual(wg.PROFILES["xl"]["dim"], 256)
        self.assertTrue(wg.PROFILES["xl"]["prefer_5090"])

    def test_role_for_name(self) -> None:
        """Tensor names map to role buckets."""
        self.assertEqual(
            wg.role_for_name("spark.embed.weight"), "embed"
        )
        self.assertEqual(
            wg.role_for_name("spark.lm_head.weight"), "lm_head"
        )
        self.assertEqual(
            wg.role_for_name("spark.layers.0.q.weight"), "attn"
        )
        self.assertEqual(
            wg.role_for_name("spark.layers.0.mlp_up.weight"),
            "mlp",
        )

    def test_inspect_init(self) -> None:
        """Checked-in init safetensors lists F32 tensors + roles."""
        self.assertTrue(INIT.is_file())
        info = wg.inspect_weights(INIT)
        self.assertGreaterEqual(info["n_tensors"], 10)
        self.assertEqual(info["tensors"][0]["dtype"], "F32")
        self.assertIn("sha256", info["tensors"][0])
        self.assertIn(
            info["size_class"],
            ("tiny", "scale", "large", "xl"),
        )

    def test_catalog_lists_kinds_and_files(self) -> None:
        """Catalog includes kind specs and discovers init file."""
        cat = wg.catalog(ROOT)
        ids = {k["id"] for k in cat["kinds"]}
        self.assertIn("init", ids)
        self.assertIn("scale", ids)
        self.assertIn("spark-coder-large", ids)
        paths = [f.get("path", "") for f in cat["files"]]
        self.assertTrue(
            any("spark-self.init.safetensors" in p for p in paths)
        )

    def test_play_forward_cpu(self) -> None:
        """Play runs tiny CPU forward on init weights."""
        out = wg.play_forward(INIT, prompt="ab")
        self.assertIn("forward", out)
        self.assertIn("argmax", out["forward"])
        self.assertEqual(out["device"], "cpu")
        self.assertEqual(out["never"], "rtx-pro-6000")
        self.assertIs(out["beats_claude"], False)

    def test_compare_identical(self) -> None:
        """Diff of same file reports identical."""
        d = wg.compare_weights(INIT, INIT)
        self.assertTrue(d["identical_files"])
        self.assertTrue(all(
            r.get("same") is True
            for r in d["tensors"]
            if r.get("status") == "ok"
        ))

    def test_generate_scale_and_large(self) -> None:
        """Emit scale + large init; inspect size_class."""
        self.assertTrue(BC.is_file())
        with tempfile.TemporaryDirectory() as tmp:
            scale = Path(tmp) / "scale.safetensors"
            large = Path(tmp) / "large.safetensors"
            rs = wg.generate_profile(
                "scale",
                scale,
                sparkbc=BC,
                prefer_5090=False,
                root=ROOT,
            )
            rl = wg.generate_profile(
                "large",
                large,
                sparkbc=BC,
                prefer_5090=False,
                root=ROOT,
            )
            self.assertEqual(rs["profile"], "scale")
            self.assertEqual(rl["profile"], "large")
            self.assertEqual(rs["never"], "rtx-pro-6000")
            si = wg.inspect_weights(scale)
            li = wg.inspect_weights(large)
            self.assertEqual(si["size_class"], "scale")
            self.assertEqual(li["size_class"], "large")
            self.assertGreaterEqual(li["arch"]["n_layer"], 8)
            # multi-layer attn tensors present
            names = {t["name"] for t in li["tensors"]}
            self.assertIn("spark.layers.7.q.weight", names)
            play = wg.play_forward(large, prompt="x")
            self.assertIn("argmax", play["forward"])

    def test_stats_histogram(self) -> None:
        """Stats returns hist + norms on CPU."""
        st = wg.tensor_stats(INIT, name="spark.embed.weight", bins=8)
        self.assertEqual(st["device"], "cpu")
        row = st["tensors"][0]
        self.assertEqual(len(row["hist"]), 8)
        self.assertIn("l2", row)

    def test_size_class_helpers(self) -> None:
        """Arch → size_class mapping covers large/xl."""
        self.assertEqual(
            wg.size_class_from_arch({"dim": 32, "n_layer": 2}),
            "tiny",
        )
        self.assertEqual(
            wg.size_class_from_arch({"dim": 64, "n_layer": 4}),
            "scale",
        )
        self.assertEqual(
            wg.size_class_from_arch({"dim": 128, "n_layer": 8}),
            "large",
        )
        self.assertEqual(
            wg.size_class_from_arch({"dim": 256, "n_layer": 8}),
            "xl",
        )


class TestSparkWeightsCli(unittest.TestCase):
    """CLI smoke via tools/spark-weights/cli.py."""

    def test_cli_catalog(self) -> None:
        """catalog subcommand exits 0."""
        import importlib.util
        import io
        from contextlib import redirect_stdout

        path = ROOT / "tools" / "spark-weights" / "cli.py"
        spec = importlib.util.spec_from_file_location(
            "spark_weights_cli", path
        )
        assert spec and spec.loader
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = mod.main(["catalog", "--root", str(ROOT)])
        self.assertEqual(code, 0)
        self.assertIn("profiles", buf.getvalue())


if __name__ == "__main__":
    unittest.main()
