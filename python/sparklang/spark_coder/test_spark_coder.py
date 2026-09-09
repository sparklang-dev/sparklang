"""Unit + integration tests for owned spark-coder (M-lane)."""

from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
import sys

sys.path.insert(0, str(ROOT / "python"))

from sparklang.spark_coder.arch import PROFILE, default_arch
from sparklang.spark_coder.device import (
    _name_forbidden,
    _name_preferred,
    pick_device,
)
from sparklang.spark_coder.layers import encode_text, forward_hidden
from sparklang.spark_coder.model import TinyCoder
from sparklang.spark_coder.tools_loop import (
    compile_spark,
    find_bootstrap,
    tool_loop_complete,
)
from sparklang.spark_coder.train import (
    prove_coding,
    train_spark_coder,
)

BC = ROOT / "docs/examples/spark-train-step.sparkbc"
DATA = ROOT / "examples/fixtures/coder/dataset.jsonl"
PROVE = ROOT / "examples/fixtures/coder/prove.json"
CAND_A = ROOT / "examples/coder/print_hello.spark"
CAND_B = ROOT / "examples/coder/train_step_slice.spark"


class TestSparkCoder(unittest.TestCase):
    """Owned TinyCoder train + prove + tool loop."""

    @classmethod
    def setUpClass(cls) -> None:
        """Train once into a temp models dir."""
        if not BC.is_file():
            raise unittest.SkipTest("missing spark-train-step.sparkbc")
        if not DATA.is_file():
            raise unittest.SkipTest("missing coder dataset")
        cls.tmp = Path(tempfile.mkdtemp(prefix="spark-coder-"))
        cls.out = cls.tmp / "models"
        cls.train = train_spark_coder(
            sparkbc=BC,
            dataset=DATA,
            out_dir=cls.out,
            outer=8,
            inner=8,
            lr=0.2,
            max_pos=24,
            also_factory_step=True,
            device="auto",
        )
        cls.weights = Path(cls.train["path"])

    @classmethod
    def tearDownClass(cls) -> None:
        """Remove temp train dir."""
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_arch_owned(self) -> None:
        """Arch profile is spark-coder, not a vendor base."""
        arch = default_arch()
        self.assertEqual(arch["profile"], PROFILE)
        self.assertEqual(arch["brain"], "owned-weights")
        self.assertFalse(arch["beats_claude"])
        self.assertEqual(arch["never"], "rtx-pro-6000")

    def test_device_never_6000(self) -> None:
        """6000 is forbidden; 5090 is preferred."""
        self.assertTrue(
            _name_forbidden(
                "NVIDIA RTX PRO 6000 Blackwell "
                "Workstation Edition"
            )
        )
        self.assertTrue(_name_preferred("NVIDIA GeForce RTX 5090"))
        cpu = pick_device(prefer_gpu=False)
        self.assertEqual(cpu["device"], "cpu")
        auto = pick_device(prefer_gpu=True, force="5090")
        if auto["device"] == "cuda":
            self.assertIn("5090", str(auto.get("name", "")))
            self.assertNotIn("6000", str(auto.get("name", "")))

    def test_train_loss_drops(self) -> None:
        """Owned SGD must drop loss and stamp trained."""
        self.assertTrue(self.train["trained"])
        self.assertLess(
            self.train["loss_after"], self.train["loss_before"]
        )
        model = TinyCoder.from_weights(self.weights)
        self.assertEqual(
            str(model.meta.get("trained")).lower(), "true"
        )
        self.assertEqual(
            str(model.meta.get("brain")), "owned-weights"
        )

    def test_forward_path(self) -> None:
        """Forward uses owned embed→mlp→norm path."""
        model = TinyCoder.from_weights(self.weights)
        ids = encode_text("spark")
        h = forward_hidden(model.tensors, ids)
        self.assertIn("embed_last_token", h["path"])
        self.assertTrue(h["path"].endswith("rms_norm"))
        pred = model.predict_next(ids)
        self.assertIn("next_token", pred)
        self.assertEqual(pred["profile"], PROFILE)

    def test_prove_fixtures(self) -> None:
        """≥50% next-byte accuracy on authored coding fixtures."""
        fixtures = json.loads(PROVE.read_text(encoding="utf-8"))
        result = prove_coding(self.weights, fixtures)
        self.assertGreaterEqual(result["accuracy"], 0.5)
        self.assertGreaterEqual(result["hits"], 2)

    def test_generate_runs(self) -> None:
        """Greedy generate returns text from owned weights."""
        model = TinyCoder.from_weights(self.weights)
        out = model.generate("Say exactly: spark", max_new=8)
        self.assertIn("completion", out)
        self.assertEqual(out["path"], "owned-greedy")
        self.assertFalse(out["beats_claude"])

    def test_tool_loop_compile(self) -> None:
        """Tool loop ranks candidates and compiles with bootstrap."""
        boot = find_bootstrap(ROOT)
        if boot is None:
            self.skipTest("spark-bootstrap not built")
        model = TinyCoder.from_weights(self.weights)
        work = self.tmp / "tool-loop"
        result = tool_loop_complete(
            model,
            task="print hello spark",
            candidate_sources=[CAND_A, CAND_B],
            work_dir=work,
            bootstrap=boot,
        )
        self.assertTrue(
            result["compile"]["ok"],
            msg=result.get("compile"),
        )
        self.assertTrue(Path(result["compile"]["out"]).is_file())
        # Direct compile proof for both fixtures.
        for cand in (CAND_A, CAND_B):
            out_bc = work / (cand.stem + "-direct.sparkbc")
            info = compile_spark(cand, out_bc, bootstrap=boot)
            self.assertTrue(info["ok"], msg=info.get("stderr"))


if __name__ == "__main__":
    unittest.main()
