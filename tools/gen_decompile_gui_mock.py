#!/usr/bin/env python3
"""Annotated GUI mock from real dump.py output + sdk-i chrome labels.

Right pane uses the real dump capture. Interactive Tk GUI ships with
the SDK pack (I-lane). Not vapor bytecode.
"""
from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DUMP = ROOT / "website/docs/examples/spark-train-step-bc-capture.txt"
OUT_WEB = ROOT / "website" / "docs" / "images" / "decompile-gui-sparkbc.png"
OUT_DOCS = ROOT / "docs" / "images"


def _font(size: int, mono: bool = False) -> ImageFont.ImageFont:
    """Load DejaVu, falling back to default."""
    name = (
        "DejaVuSansMono.ttf" if mono else "DejaVuSans.ttf"
    )
    path = f"/usr/share/fonts/truetype/dejavu/{name}"
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


def main() -> int:
    """Write annotated GUI PNG next to CLI captures."""
    dump = DUMP.read_text(encoding="utf-8")
    font = _font(12, mono=True)
    font_ui = _font(13)
    font_sm = _font(11)
    width, height = 980, 640
    img = Image.new("RGB", (width, height), (245, 246, 248))
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, width, 36), fill=(40, 44, 52))
    draw.text(
        (12, 10),
        "SparkLang — SPARK_BC compile / decompile",
        fill=(240, 240, 240),
        font=font_ui,
    )
    draw.rectangle((0, 36, width, 72), fill=(220, 224, 230))
    labels = [
        "Compile → .sparkbc",
        "Decompile .sparkbc",
        "Open source…",
        "Open .sparkbc…",
        "Save dump…",
        "Load sample",
    ]
    for i, label in enumerate(labels):
        x0 = 8 + i * 155
        draw.rectangle(
            (x0, 42, x0 + 148, 66),
            fill=(255, 255, 255),
            outline=(160, 166, 176),
        )
        draw.text((x0 + 6, 46), label, fill=(30, 34, 40), font=font_sm)
    mid = width // 2
    draw.rectangle(
        (8, 88, mid - 6, height - 40),
        fill=(255, 255, 255),
        outline=(180, 184, 190),
    )
    draw.rectangle(
        (mid + 6, 88, width - 8, height - 40),
        fill=(18, 20, 24),
        outline=(180, 184, 190),
    )
    draw.text((14, 94), ".spark source", fill=(40, 44, 52), font=font_ui)
    draw.text(
        (mid + 12, 94),
        "SPARK_BC dump / decompile",
        fill=(200, 210, 220),
        font=font_ui,
    )
    src = (
        "# examples/spark_train_step.spark (sample)\n"
        "model train method spark_distill_cpu \\\n"
        '  dataset "examples/fixtures/train/dataset.jsonl" \\\n'
        '  base "fixture-base" \\\n'
        '  out "out/train/job-dry-001" -> code\n'
        "model step code step 1 -> code\n"
        "model status code -> status\n"
        "print status\n"
    )
    y = 118
    for line in src.splitlines():
        draw.text((16, y), line[:52], fill=(20, 24, 30), font=font)
        y += 16
    y = 118
    for line in dump.splitlines()[:28]:
        shown = line[:54] + ("…" if len(line) > 54 else "")
        draw.text((mid + 12, y), shown, fill=(180, 220, 160), font=font)
        y += 15
    draw.rectangle((0, height - 56, width, height - 36), fill=(255, 244, 200))
    draw.text(
        (12, height - 52),
        "Annotated mock: dump pane = real dump.py output. "
        "Interactive Tk GUI ships with SDK pack (I-lane).",
        fill=(80, 60, 0),
        font=font_sm,
    )
    draw.rectangle((0, height - 36, width, height), fill=(232, 236, 240))
    draw.text(
        (12, height - 26),
        "Status: dump from real bc_dump.format_dump — chrome "
        "matches tools/spark_bc_gui (SDK pack).",
        fill=(40, 44, 52),
        font=font_sm,
    )
    OUT_WEB.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT_WEB)
    print(f"wrote {OUT_WEB} {img.size}")
    OUT_DOCS.mkdir(parents=True, exist_ok=True)
    for path in (ROOT / "website" / "docs" / "images").glob(
        "decompile-*.png"
    ):
        dest = OUT_DOCS / path.name
        shutil.copy2(path, dest)
        print(f"copied {dest.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
