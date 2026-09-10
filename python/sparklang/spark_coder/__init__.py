"""Spark-coder — reference trainer + self-hosted product coder.

`model.py` / `train.py` are the reference implementation for the
training pipeline (tiny owned weights, CPU/5090). The product code
model is the self-hosted Qwen3-Coder-30B endpoint in
`real_coder.py` — offline, no API keys. Never the RTX PRO 6000.
"""

from sparklang.spark_coder.model import TinyCoder
from sparklang.spark_coder.train import train_spark_coder

__all__ = ["TinyCoder", "train_spark_coder"]
