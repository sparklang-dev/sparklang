"""Spark voice/text ask — ears → dump context → TinyCoder → speak.

Local-only. No OpenBin login. Never 6000. No parity claim.
"""

from spark_ask.voice_ask import answer_question, load_context, run_ask

__all__ = ["answer_question", "load_context", "run_ask"]
