"""Spark-coder — owned tiny coding model (written + trained here).

Not a HuggingFace / Claude / Bifrost wrapper. CPU only. Never the
RTX PRO 6000. Does not beat Claude.
"""

from sparklang.spark_coder.model import TinyCoder
from sparklang.spark_coder.train import train_spark_coder

__all__ = ["TinyCoder", "train_spark_coder"]
