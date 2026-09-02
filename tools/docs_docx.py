#!/usr/bin/env python3
"""Build professional Spark .docx from on-disk markdown (formatting only).

Uses pandoc + a tuned reference.docx, then python-docx for title page,
headers/footers (page X of Y), TOC, and an ops-index appendix extracted
from existing markdown tables (never invents ops).
"""
from __future__ import annotations

import argparse
import datetime as dt
import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

from docx import Document
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor

ROOT = Path(__file__).resolve().parents[1]
DOCX_DIR = ROOT / "docs" / "docx"
REF_PATH = DOCX_DIR / "reference.docx"

CANONICAL = (
    ("docs/PROGRAMMING_GUIDE.md", "PROGRAMMING_GUIDE"),
    ("docs/IDE.md", "IDE"),
    ("docs/LANGUAGE.md", "LANGUAGE"),
    ("docs/ASK_LIVE.md", "ASK_LIVE"),
    ("docs/SELF_HOST.md", "SELF_HOST"),
    ("README.md", "README"),
)

SPARK_BLUE = RGBColor(0x1A, 0x3A, 0x5C)
SPARK_GRAY = RGBColor(0x4A, 0x4A, 0x4A)
HEADER_SHADE = "1A3A5C"
ALT_ROW = "F2F5F8"

# Tables whose headers look like indexes (content still from MD only).
OPS_HEADER_RE = re.compile(
    r"\b(op|ops|command|statement|flag|target|area|mode|"
    r"var|surface|lane|role|path|symptom|situation)\b",
    re.I,
)


def _get_style(doc: Document, name: str):
    """Resolve a style by name (python-docx latent-style quirk)."""
    try:
        return doc.styles[name]
    except KeyError:
        for style in doc.styles:
            if style.name == name:
                return style
        raise KeyError(name) from None


def _clear_paragraph(paragraph) -> None:
    """Remove runs from a paragraph (python-docx has no clear())."""
    element = paragraph._p
    for child in list(element):
        if child.tag in (qn("w:r"), qn("w:hyperlink")):
            element.remove(child)


def _set_run_font(run, name: str, size_pt: float | None = None, bold=None):
    run.font.name = name
    r_el = run._element
    r_pr = r_el.get_or_add_rPr()
    r_fonts = r_pr.get_or_add_rFonts()
    r_fonts.set(qn("w:ascii"), name)
    r_fonts.set(qn("w:hAnsi"), name)
    r_fonts.set(qn("w:cs"), name)
    if size_pt is not None:
        run.font.size = Pt(size_pt)
    if bold is not None:
        run.font.bold = bold


def _set_style_font(style, name: str, size_pt: float, *, bold=False, color=None):
    style.font.name = name
    style.font.size = Pt(size_pt)
    style.font.bold = bold
    if color is not None:
        style.font.color.rgb = color
    r_pr = style.element.get_or_add_rPr()
    r_fonts = r_pr.get_or_add_rFonts()
    r_fonts.set(qn("w:ascii"), name)
    r_fonts.set(qn("w:hAnsi"), name)
    r_fonts.set(qn("w:cs"), name)


def _set_paragraph_spacing(style, before=0, after=8, line=1.15):
    pf = style.paragraph_format
    pf.space_before = Pt(before)
    pf.space_after = Pt(after)
    pf.line_spacing = line


def _enable_update_fields(docx_path: Path) -> None:
    """Ask Word to refresh PAGE/NUMPAGES/TOC on open."""
    ns = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
    ET.register_namespace(
        "w",
        "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
    )
    with zipfile.ZipFile(docx_path, "r") as zin:
        settings = zin.read("word/settings.xml")
        others = {
            info.filename: zin.read(info.filename)
            for info in zin.infolist()
            if info.filename != "word/settings.xml"
        }
    root = ET.fromstring(settings)
    if root.find("w:updateFields", ns) is None:
        el = ET.Element(
            "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
            "updateFields"
        )
        el.set(
            "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
            "val",
            "true",
        )
        root.insert(0, el)
    with zipfile.ZipFile(docx_path, "w") as zout:
        for name, data in others.items():
            zout.writestr(name, data)
        zout.writestr(
            "word/settings.xml",
            ET.tostring(root, encoding="utf-8", xml_declaration=True),
        )


def build_reference(path: Path) -> None:
    """Write a pandoc reference.docx with publication-grade styles."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".docx", delete=False) as tmp:
        tmp_path = Path(tmp.name)
    raw = subprocess.check_output(
        ["pandoc", "--print-default-data-file", "reference.docx"]
    )
    tmp_path.write_bytes(raw)
    doc = Document(str(tmp_path))

    # Fetch styles BEFORE any mutation (python-docx lookup quirk).
    normal = _get_style(doc, "Normal")
    h1 = _get_style(doc, "Heading 1")
    h2 = _get_style(doc, "Heading 2")
    h3 = _get_style(doc, "Heading 3")
    title = _get_style(doc, "Title")
    subtitle = _get_style(doc, "Subtitle")
    toc_h = _get_style(doc, "TOC Heading")
    try:
        verbatim = _get_style(doc, "Verbatim Char")
    except KeyError:
        verbatim = None

    for section in doc.sections:
        section.top_margin = Inches(1.0)
        section.bottom_margin = Inches(1.0)
        section.left_margin = Inches(1.0)
        section.right_margin = Inches(1.0)
        section.page_width = Inches(8.5)
        section.page_height = Inches(11)
        section.different_first_page_header_footer = True

    _set_style_font(normal, "Calibri", 11, color=SPARK_GRAY)
    _set_paragraph_spacing(normal, before=0, after=8, line=1.15)

    _set_style_font(h1, "Calibri Light", 18, bold=True, color=SPARK_BLUE)
    _set_paragraph_spacing(h1, before=18, after=10, line=1.15)
    h1.paragraph_format.page_break_before = True
    h1.paragraph_format.keep_with_next = True

    _set_style_font(h2, "Calibri", 14, bold=True, color=SPARK_BLUE)
    _set_paragraph_spacing(h2, before=14, after=6, line=1.15)
    h2.paragraph_format.keep_with_next = True

    _set_style_font(h3, "Calibri", 12, bold=True, color=SPARK_BLUE)
    _set_paragraph_spacing(h3, before=10, after=4, line=1.15)
    h3.paragraph_format.keep_with_next = True

    _set_style_font(title, "Calibri Light", 28, bold=True, color=SPARK_BLUE)
    _set_paragraph_spacing(title, before=0, after=6, line=1.2)
    _set_style_font(subtitle, "Calibri", 14, color=SPARK_BLUE)
    _set_paragraph_spacing(subtitle, before=0, after=6, line=1.2)
    _set_style_font(toc_h, "Calibri Light", 16, bold=True, color=SPARK_BLUE)

    if verbatim is not None:
        try:
            _set_style_font(
                verbatim,
                "Consolas",
                9,
                color=RGBColor(0x22, 0x22, 0x22),
            )
        except (AttributeError, ValueError):
            pass

    doc.save(str(path))
    tmp_path.unlink(missing_ok=True)


def _add_field(paragraph, instr: str) -> None:
    """Insert a Word field (PAGE / NUMPAGES)."""
    run = paragraph.add_run()
    r_el = run._r
    fld_begin = OxmlElement("w:fldChar")
    fld_begin.set(qn("w:fldCharType"), "begin")
    instr_text = OxmlElement("w:instrText")
    instr_text.set(qn("xml:space"), "preserve")
    instr_text.text = instr
    fld_sep = OxmlElement("w:fldChar")
    fld_sep.set(qn("w:fldCharType"), "separate")
    placeholder = OxmlElement("w:t")
    placeholder.text = "·"
    fld_end = OxmlElement("w:fldChar")
    fld_end.set(qn("w:fldCharType"), "end")
    r_el.append(fld_begin)
    r_el.append(instr_text)
    r_el.append(fld_sep)
    r2 = paragraph.add_run()
    r2._r.append(placeholder)
    r3 = paragraph.add_run()
    r3._r.append(fld_end)


def _set_cell_shading(cell, fill_hex: str) -> None:
    tc = cell._tc
    tc_pr = tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:fill"), fill_hex)
    shd.set(qn("w:val"), "clear")
    tc_pr.append(shd)


def _shade_header_row(table) -> None:
    if not table.rows:
        return
    for cell in table.rows[0].cells:
        _set_cell_shading(cell, HEADER_SHADE)
        for para in cell.paragraphs:
            for run in para.runs:
                run.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
                run.font.bold = True
                _set_run_font(run, "Calibri", 10, bold=True)
    for ri, row in enumerate(table.rows[1:], start=1):
        if ri % 2 == 1:
            for cell in row.cells:
                _set_cell_shading(cell, ALT_ROW)
        for cell in row.cells:
            for para in cell.paragraphs:
                for run in para.runs:
                    if not run.font.name:
                        _set_run_font(run, "Calibri", 10)


def first_h1(md_text: str) -> str:
    for line in md_text.splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return "Spark"


def extract_ops_tables(
    md_text: str,
) -> list[tuple[list[str], list[list[str]]]]:
    """Pull markdown tables whose headers look like ops indexes."""
    lines = md_text.splitlines()
    tables: list[tuple[list[str], list[list[str]]]] = []
    i = 0

    def split_row(line: str) -> list[str]:
        return [c.strip() for c in line.strip().strip("|").split("|")]

    while i < len(lines):
        line = lines[i]
        if (
            line.startswith("|")
            and i + 1 < len(lines)
            and re.match(r"^\|[\s\-:|]+\|$", lines[i + 1].strip())
        ):
            header = split_row(line)
            if any(OPS_HEADER_RE.search(h) for h in header):
                rows: list[list[str]] = []
                j = i + 2
                while j < len(lines) and lines[j].startswith("|"):
                    rows.append(split_row(lines[j]))
                    j += 1
                if rows:
                    tables.append((header, rows))
                i = j
                continue
        i += 1
    return tables


def apply_header_footer(doc: Document, doc_title: str) -> None:
    """Header: Spark · title. Footer: page X of Y + confidential."""
    for section in doc.sections:
        section.different_first_page_header_footer = True
        section.first_page_header.is_linked_to_previous = False
        section.first_page_footer.is_linked_to_previous = False
        for para in section.first_page_header.paragraphs:
            _clear_paragraph(para)
        for para in section.first_page_footer.paragraphs:
            _clear_paragraph(para)

        header = section.header
        header.is_linked_to_previous = False
        hp = (
            header.paragraphs[0]
            if header.paragraphs
            else header.add_paragraph()
        )
        _clear_paragraph(hp)
        hp.alignment = WD_ALIGN_PARAGRAPH.LEFT
        r1 = hp.add_run("Spark")
        _set_run_font(r1, "Calibri", 9, bold=True)
        r1.font.color.rgb = SPARK_BLUE
        r2 = hp.add_run("  ·  ")
        _set_run_font(r2, "Calibri", 9)
        r2.font.color.rgb = SPARK_GRAY
        r3 = hp.add_run(doc_title)
        _set_run_font(r3, "Calibri", 9)
        r3.font.color.rgb = SPARK_GRAY

        p_pr = hp._p.get_or_add_pPr()
        p_bdr = OxmlElement("w:pBdr")
        bottom = OxmlElement("w:bottom")
        bottom.set(qn("w:val"), "single")
        bottom.set(qn("w:sz"), "6")
        bottom.set(qn("w:space"), "4")
        bottom.set(qn("w:color"), "1A3A5C")
        p_bdr.append(bottom)
        p_pr.append(p_bdr)

        footer = section.footer
        footer.is_linked_to_previous = False
        fp = (
            footer.paragraphs[0]
            if footer.paragraphs
            else footer.add_paragraph()
        )
        _clear_paragraph(fp)
        fp.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p_pr = fp._p.get_or_add_pPr()
        p_bdr = OxmlElement("w:pBdr")
        top = OxmlElement("w:top")
        top.set(qn("w:val"), "single")
        top.set(qn("w:sz"), "6")
        top.set(qn("w:space"), "4")
        top.set(qn("w:color"), "CCCCCC")
        p_bdr.append(top)
        p_pr.append(p_bdr)

        ra = fp.add_run("Page ")
        _set_run_font(ra, "Calibri", 8)
        ra.font.color.rgb = SPARK_GRAY
        _add_field(fp, " PAGE ")
        rb = fp.add_run(" of ")
        _set_run_font(rb, "Calibri", 8)
        rb.font.color.rgb = SPARK_GRAY
        _add_field(fp, " NUMPAGES ")
        rc = fp.add_run("  ·  Owner-local / confidential  ·  Spark")
        _set_run_font(rc, "Calibri", 8)
        rc.font.color.rgb = SPARK_GRAY


def _page_break_paragraph(doc: Document):
    para = doc.add_paragraph()
    run = para.add_run()
    br = OxmlElement("w:br")
    br.set(qn("w:type"), "page")
    run._r.append(br)
    return para


def prepend_title_page(doc: Document, title: str, date_str: str) -> None:
    """Insert a title page before pandoc body/TOC."""
    body = doc.element.body
    children = list(body)
    sect_pr = None
    content = []
    for child in children:
        if child.tag == qn("w:sectPr"):
            sect_pr = child
        else:
            content.append(child)
            body.remove(child)

    for child in content:
        if sect_pr is not None:
            body.insert(list(body).index(sect_pr), child)
        else:
            body.append(child)

    def insert_para_at(
        index: int,
        text: str,
        *,
        size: float,
        bold: bool = False,
        space_before: float = 0,
        space_after: float = 8,
    ) -> int:
        para = doc.add_paragraph()
        para.alignment = WD_ALIGN_PARAGRAPH.CENTER
        para.paragraph_format.space_before = Pt(space_before)
        para.paragraph_format.space_after = Pt(space_after)
        run = para.add_run(text)
        font = "Calibri Light" if size >= 16 else "Calibri"
        _set_run_font(run, font, size, bold=bold)
        run.font.color.rgb = SPARK_BLUE if size >= 14 else SPARK_GRAY
        element = para._element
        body.remove(element)
        body.insert(index, element)
        return 1

    idx = 0
    idx += insert_para_at(idx, "", size=11, space_before=72, space_after=0)
    idx += insert_para_at(
        idx,
        "Spark Programming",
        size=14,
        bold=True,
        space_before=0,
        space_after=12,
    )
    idx += insert_para_at(
        idx,
        title,
        size=28,
        bold=True,
        space_before=24,
        space_after=18,
    )
    idx += insert_para_at(idx, date_str, size=12, space_before=12, space_after=6)
    idx += insert_para_at(
        idx,
        "Generated from on-disk markdown · no invented content",
        size=9,
        space_before=6,
        space_after=24,
    )
    br_para = _page_break_paragraph(doc)
    element = br_para._element
    body.remove(element)
    body.insert(idx, element)


def _apply_table_style(table) -> None:
    for name in ("Table Grid", "Table", "Normal Table"):
        try:
            table.style = name
            return
        except (KeyError, ValueError):
            continue


def append_ops_index(
    doc: Document,
    tables: list[tuple[list[str], list[list[str]]]],
) -> None:
    if not tables:
        return
    _page_break_paragraph(doc)

    h1 = _get_style(doc, "Heading 1")
    h2 = _get_style(doc, "Heading 2")
    heading = doc.add_paragraph("Index of operations")
    heading.style = h1
    heading.paragraph_format.page_break_before = False

    note = doc.add_paragraph()
    nr = note.add_run(
        "Extracted from existing markdown tables in this document "
        "(ops / commands / flags / lanes / paths). Not invented."
    )
    _set_run_font(nr, "Calibri", 10)
    nr.font.italic = True
    nr.font.color.rgb = SPARK_GRAY

    for ti, (header, rows) in enumerate(tables, start=1):
        sub = doc.add_paragraph(f"Table {ti}")
        sub.style = h2
        sub.paragraph_format.page_break_before = False
        table = doc.add_table(rows=1 + len(rows), cols=len(header))
        _apply_table_style(table)
        table.alignment = WD_TABLE_ALIGNMENT.CENTER
        for ci, cell_text in enumerate(header):
            table.rows[0].cells[ci].text = cell_text
        for ri, row in enumerate(rows):
            for ci in range(len(header)):
                val = row[ci] if ci < len(row) else ""
                table.rows[ri + 1].cells[ci].text = val
        _shade_header_row(table)
        doc.add_paragraph()


def polish_tables(doc: Document) -> None:
    for table in doc.tables:
        _apply_table_style(table)
        _shade_header_row(table)


def _remove_pandoc_title_block(doc: Document) -> None:
    """Drop pandoc Title/Subtitle/Date so our title page is sole cover."""
    body = doc.element.body
    removed = 0
    for para in list(doc.paragraphs):
        if removed >= 6:
            break
        name = para.style.name if para.style else ""
        if name in ("Title", "Subtitle", "Date", "Author"):
            body.remove(para._element)
            removed += 1
        elif not (para.text or "").strip() and removed > 0 and removed < 4:
            body.remove(para._element)


def _promote_chapter_headings(doc: Document) -> None:
    """## chapters → Heading 1 (page break); ### → Heading 2."""
    h1 = _get_style(doc, "Heading 1")
    h2 = _get_style(doc, "Heading 2")
    h3 = _get_style(doc, "Heading 3")
    past_index = False
    for para in doc.paragraphs:
        text = (para.text or "").strip()
        name = para.style.name if para.style else ""
        if text == "Index of operations":
            past_index = True
            continue
        if past_index:
            continue
        if name == "Heading 2":
            para.style = h1
            para.paragraph_format.page_break_before = True
            para.paragraph_format.keep_with_next = True
        elif name == "Heading 3":
            para.style = h2
            para.paragraph_format.page_break_before = False
            para.paragraph_format.keep_with_next = True
        elif name == "Heading 4":
            para.style = h3
            para.paragraph_format.page_break_before = False


def convert_one(md_path: Path, out_path: Path, ref: Path) -> dict:
    """Convert one markdown file to a professional docx."""
    md_text = md_path.read_text(encoding="utf-8")
    title = first_h1(md_text)
    date_str = dt.date.today().isoformat()
    ops = extract_ops_tables(md_text)

    with tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".md",
        delete=False,
        encoding="utf-8",
    ) as tmp:
        # No YAML title — title page is injected post-pandoc.
        body_lines = md_text.splitlines()
        if body_lines and body_lines[0].startswith("# "):
            body_lines = body_lines[1:]
            while body_lines and not body_lines[0].strip():
                body_lines = body_lines[1:]
        tmp.write("\n".join(body_lines) + "\n")
        staged = Path(tmp.name)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.check_call(
        [
            "pandoc",
            str(staged),
            "-f",
            "markdown",
            "-t",
            "docx",
            f"--reference-doc={ref}",
            "--toc",
            "--toc-depth=3",
            "-o",
            str(out_path),
        ]
    )
    staged.unlink(missing_ok=True)

    doc = Document(str(out_path))
    for section in doc.sections:
        section.top_margin = Inches(1.0)
        section.bottom_margin = Inches(1.0)
        section.left_margin = Inches(1.0)
        section.right_margin = Inches(1.0)

    _remove_pandoc_title_block(doc)
    prepend_title_page(doc, title, date_str)
    _promote_chapter_headings(doc)
    apply_header_footer(doc, title)
    polish_tables(doc)
    append_ops_index(doc, ops)
    # Index tables labeled Heading 2 — keep without chapter page-break
    apply_header_footer(doc, title)
    doc.save(str(out_path))
    _enable_update_fields(out_path)

    size = out_path.stat().st_size
    try:
        src_disp = str(md_path.relative_to(ROOT))
    except ValueError:
        src_disp = str(md_path)
    try:
        out_disp = str(out_path.relative_to(ROOT))
    except ValueError:
        out_disp = str(out_path)
    return {
        "src": src_disp,
        "out": out_disp,
        "title": title,
        "ops_tables": len(ops),
        "bytes": size,
    }


def main(argv: list[str] | None = None) -> int:
    """Rebuild reference (optional) and convert canonical guides."""
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--rebuild-reference",
        action="store_true",
        help="Regenerate docs/docx/reference.docx",
    )
    ap.add_argument(
        "--extra",
        action="append",
        default=[],
        help="Extra md=stem pairs (path=STEM)",
    )
    args = ap.parse_args(argv)

    DOCX_DIR.mkdir(parents=True, exist_ok=True)
    if args.rebuild_reference or not REF_PATH.exists():
        build_reference(REF_PATH)
        print(f"wrote {REF_PATH.relative_to(ROOT)}")

    jobs = list(CANONICAL)
    for item in args.extra:
        if "=" not in item:
            print(f"bad --extra {item!r}; want path=STEM", file=sys.stderr)
            return 2
        rel, stem = item.split("=", 1)
        jobs.append((rel, stem))

    results = []
    for rel, stem in jobs:
        md = ROOT / rel
        if not md.is_file():
            print(f"skip missing {rel}")
            continue
        out = DOCX_DIR / f"{stem}.docx"
        info = convert_one(md, out, REF_PATH)
        results.append(info)
        print(
            f"ok {info['out']} ({info['bytes']} bytes, "
            f"{info['ops_tables']} ops tables) ← {info['src']}"
        )

    if not results:
        print("no documents converted", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
