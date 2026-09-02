"""Unit tests for SparkLang abstain gate / parse / train / HF hooks."""

from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))

import torch  # noqa: E402

from sparklang.abstain.dry import dry_result  # noqa: E402
from sparklang.abstain.gate import (  # noqa: E402
    GateConfig,
    select_before_sample,
)
from sparklang.abstain.generate import (  # noqa: E402
    gated_from_hidden,
    live_ask,
    load_hidden_tensor,
    require_explicit_model,
    score_hidden,
    try_hf_last_hidden,
    try_hf_select_then_sample,
    try_vllm_last_hidden,
)
from sparklang.abstain.head import AbstainHead, save_head  # noqa: E402
from sparklang.abstain.parse import parse_head_stmt  # noqa: E402
from sparklang.abstain.train import train_abstain_head  # noqa: E402


class GateTests(unittest.TestCase):
    """Threshold / entropy / margin SELECT logic."""

    def test_threshold_abstain(self) -> None:
        d = select_before_sample(0.8, GateConfig(threshold=0.7))
        self.assertTrue(d.abstain)
        self.assertTrue(d.halted)
        self.assertEqual(d.reason, "threshold")
        self.assertEqual(d.text, "I don't know.")

    def test_threshold_continue(self) -> None:
        d = select_before_sample(0.2, GateConfig(threshold=0.7))
        self.assertFalse(d.abstain)
        self.assertFalse(d.halted)
        self.assertEqual(d.reason, "continue")
        self.assertIsNone(d.text)

    def test_entropy_trip(self) -> None:
        cfg = GateConfig(threshold=0.99, entropy_max=1.5)
        d = select_before_sample(0.1, cfg, entropy=2.0)
        self.assertTrue(d.abstain)
        self.assertEqual(d.reason, "entropy")

    def test_margin_trip(self) -> None:
        cfg = GateConfig(threshold=0.99, margin_min=0.2)
        d = select_before_sample(0.1, cfg, margin=0.05)
        self.assertTrue(d.abstain)
        self.assertEqual(d.reason, "margin")


class ParseTests(unittest.TestCase):
    """``.spark`` head statement parsing."""

    def test_abstain_internal(self) -> None:
        f = parse_head_stmt(
            'head abstain internal model "m" '
            'weights "w.pt" threshold 0.7 '
            'idk "I don\'t know." -> gate'
        )
        self.assertEqual(f["op"], "abstain")
        self.assertEqual(f["kind"], "internal")
        self.assertEqual(f["model"], "m")
        self.assertEqual(f["threshold"], 0.7)
        self.assertEqual(f["bind"], "gate")

    def test_ask(self) -> None:
        f = parse_head_stmt(
            'head ask "Who is the mayor?" -> answer'
        )
        self.assertEqual(f["op"], "ask")
        self.assertIn("mayor", f["prompt"])
        self.assertEqual(f["bind"], "answer")

    def test_train(self) -> None:
        f = parse_head_stmt(
            'head train dataset "d.jsonl" kind external '
            'out "o.pt" hidden_dim 64 -> job'
        )
        self.assertEqual(f["op"], "train")
        self.assertEqual(f["kind"], "external")
        self.assertEqual(f["hidden_dim"], 64)


class DryAskTests(unittest.TestCase):
    """Dry ask inventable → abstain."""

    def test_mayor_abstains(self) -> None:
        r = dry_result(
            {
                "op": "ask",
                "prompt": "Who is the mayor of Springfield?",
            }
        )
        self.assertTrue(r["abstain"])
        self.assertTrue(r["halted"])


class TrainTests(unittest.TestCase):
    """CPU train writes a real .pt."""

    def test_train_fixture(self) -> None:
        ds = ROOT / "examples/fixtures/abstain/labels.jsonl"
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "h.pt"
            info = train_abstain_head(
                ds, out, kind="internal", steps=50, hidden_dim=64
            )
            self.assertEqual(info["state"], "succeeded")
            self.assertTrue(out.is_file())
            meta = out.with_suffix(".meta.json")
            self.assertTrue(meta.is_file())
            body = json.loads(meta.read_text(encoding="utf-8"))
            self.assertEqual(body["spark"], "abstain_head")


class AliasRefuseTests(unittest.TestCase):
    """Never treat gateway short names as HF models."""

    def test_refuse_code_alias(self) -> None:
        with self.assertRaises(SystemExit) as ctx:
            require_explicit_model("code")
        self.assertIn("refuse gateway alias", str(ctx.exception))

    def test_allow_hub_id(self) -> None:
        self.assertEqual(
            require_explicit_model("org/tiny-mock"),
            "org/tiny-mock",
        )


class HiddenFileTests(unittest.TestCase):
    """Synthetic fixed hidden for unit tests (no HF download)."""

    def test_load_pt_and_gate(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            td_p = Path(td)
            head = AbstainHead(8)
            # Bias toward abstain for high-norm inputs.
            with torch.no_grad():
                head.net.weight.fill_(1.0)
                head.net.bias.fill_(2.0)
            wpath = td_p / "h.pt"
            save_head(head, wpath, kind="internal")
            hid = torch.ones(8)
            hpath = td_p / "hidden.pt"
            torch.save(hid, hpath)
            loaded = load_hidden_tensor(hpath)
            self.assertEqual(int(loaded.numel()), 8)
            cfg = GateConfig(threshold=0.5)
            r = gated_from_hidden(head, loaded, cfg)
            self.assertTrue(r["abstain"])
            p = score_hidden(head, loaded)
            self.assertGreaterEqual(p, 0.5)

    def test_live_ask_from_hidden_file(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            td_p = Path(td)
            head = AbstainHead(4)
            with torch.no_grad():
                head.net.weight.fill_(0.0)
                head.net.bias.fill_(-5.0)  # low p
            wpath = td_p / "h.pt"
            save_head(head, wpath)
            hpath = td_p / "hidden.pt"
            torch.save(torch.zeros(4), hpath)
            r = live_ask(
                "What is 2+2?",
                weights=str(wpath),
                hidden_path=str(hpath),
            )
            self.assertFalse(r["abstain"])
            self.assertEqual(r["hidden_source"], "file")
            self.assertEqual(r["mode"], "live")


class HfHookMockTests(unittest.TestCase):
    """Mock transformers tensors — no download / no GPU."""

    def test_try_hf_last_hidden_mocked(self) -> None:
        fake_tok = MagicMock()
        fake_tok.pad_token = None
        fake_tok.eos_token = "</s>"
        fake_tok.return_value = {
            "input_ids": torch.tensor([[1, 2, 3]]),
            "attention_mask": torch.tensor([[1, 1, 1]]),
        }

        class _Out:
            def __init__(self) -> None:
                # layers × (B, T, H) — last layer last token = ones
                layer = torch.zeros(1, 3, 5)
                layer[0, -1, :] = 1.0
                self.hidden_states = (layer, layer)

        fake_model = MagicMock()
        fake_model.return_value = _Out()
        fake_model.eval = MagicMock()

        with patch.dict(os.environ, {"SPARK_ABSTAIN_HF": "1"}):
            with patch.dict(
                "sys.modules",
                {
                    "transformers": MagicMock(
                        AutoTokenizer=MagicMock(
                            from_pretrained=MagicMock(
                                return_value=fake_tok
                            )
                        ),
                        AutoModelForCausalLM=MagicMock(
                            from_pretrained=MagicMock(
                                return_value=fake_model
                            )
                        ),
                    )
                },
            ):
                h = try_hf_last_hidden("org/tiny-mock", "hi")
        self.assertIsNotNone(h)
        assert h is not None
        self.assertEqual(int(h.numel()), 5)
        self.assertTrue(torch.allclose(h, torch.ones(5)))

    def test_try_hf_select_abstain_mocked(self) -> None:
        fake_tok = MagicMock()
        fake_tok.pad_token = "</s>"
        fake_tok.eos_token = "</s>"
        fake_tok.pad_token_id = 0
        fake_tok.return_value = {
            "input_ids": torch.tensor([[1, 2]]),
            "attention_mask": torch.tensor([[1, 1]]),
        }
        fake_tok.decode = MagicMock(return_value="should-not-run")

        class _Out:
            def __init__(self) -> None:
                layer = torch.ones(1, 2, 4)
                self.hidden_states = (layer,)

        fake_model = MagicMock()
        fake_model.return_value = _Out()
        fake_model.eval = MagicMock()
        fake_model.generate = MagicMock()

        head = AbstainHead(4)
        with torch.no_grad():
            head.net.weight.fill_(1.0)
            head.net.bias.fill_(5.0)
        cfg = GateConfig(threshold=0.5, idk="IDK.")

        with patch.dict(os.environ, {"SPARK_ABSTAIN_HF": "1"}):
            with patch.dict(
                "sys.modules",
                {
                    "transformers": MagicMock(
                        AutoTokenizer=MagicMock(
                            from_pretrained=MagicMock(
                                return_value=fake_tok
                            )
                        ),
                        AutoModelForCausalLM=MagicMock(
                            from_pretrained=MagicMock(
                                return_value=fake_model
                            )
                        ),
                    )
                },
            ):
                r = try_hf_select_then_sample(
                    "org/tiny-mock",
                    "Who is the mayor?",
                    head,
                    cfg,
                )
        self.assertIsNotNone(r)
        assert r is not None
        self.assertTrue(r["abstain"])
        self.assertEqual(r["text"], "IDK.")
        self.assertEqual(r["mode"], "live-hf")
        fake_model.generate.assert_not_called()

    def test_hf_missing_returns_none(self) -> None:
        # No SPARK_ABSTAIN_HF and non-existent path → None.
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("SPARK_ABSTAIN_HF", None)
            h = try_hf_last_hidden("not-a-real/model-xyz", "x")
        self.assertIsNone(h)

    def test_vllm_best_effort_fail(self) -> None:
        h = try_vllm_last_hidden(
            "http://127.0.0.1:9", "hi", timeout_s=0.05
        )
        self.assertIsNone(h)


class ExportTrainTests(unittest.TestCase):
    """Export toy/backbone hiddens → train dim-matched head."""

    def test_toy_export_then_train(self) -> None:
        from sparklang.abstain.export import (
            export_hiddens,
            toy_backbone_hidden,
        )

        text_ds = ROOT / "examples/fixtures/abstain/labels_text.jsonl"
        with tempfile.TemporaryDirectory() as td:
            td_p = Path(td)
            exported = td_p / "exp.jsonl"
            info = export_hiddens(
                text_ds,
                exported,
                hidden_dim=16,
                seed=42,
            )
            self.assertEqual(info["source"], "toy")
            self.assertEqual(info["hidden_dim"], 16)
            self.assertTrue(exported.is_file())
            out = td_p / "h.pt"
            train = train_abstain_head(
                exported,
                out,
                kind="internal",
                steps=80,
                hidden_dim=16,
            )
            self.assertEqual(train["state"], "succeeded")
            self.assertEqual(train["hidden_dim"], 16)
            # Ask with matching toy hidden for inventable prompt.
            head = AbstainHead(16)
            # Reload trained weights.
            from sparklang.abstain.head import load_head

            head = load_head(out)
            self.assertEqual(head.hidden_dim, 16)
            hid = torch.tensor(
                toy_backbone_hidden(
                    "Who is the mayor of Springfield?",
                    16,
                    seed=42,
                ),
                dtype=torch.float32,
            )
            p = score_hidden(head, hid)
            self.assertGreaterEqual(p, 0.0)
            self.assertLessEqual(p, 1.0)

    def test_shipped_exported_fixture(self) -> None:
        ds = ROOT / "examples/fixtures/abstain/labels_exported.jsonl"
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "h.pt"
            info = train_abstain_head(
                ds, out, kind="internal", steps=50, hidden_dim=16
            )
            self.assertEqual(info["hidden_dim"], 16)
            self.assertTrue(out.is_file())


if __name__ == "__main__":
    unittest.main()
