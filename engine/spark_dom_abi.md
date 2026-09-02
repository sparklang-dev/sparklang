# Spark engine B — DOM + layout→paint ABI

**No inventing.** Parse fills `nodes[]`; layout emits `SePaintBox[]`;
paint fills the FB. PyQt is not this path.

## Parse DOM — `engine_html.s` (64 bytes / node)

Exports: `nodes`, `nnodes`, `root_id`, `html_buf`. Max 256 nodes.

After parse, `engine_js_run_dom_scripts` walks `TAG_SCRIPT` elements and
evals each text child's `data[40]` via phase-1 `engine_js_eval` (tiny
only — not full ES).

| Off | Type | Name | Notes |
|-----|------|------|-------|
| 0 | u8 | kind | 1=element 2=text |
| 1 | u8 | tag | `TAG_*` below |
| 2 | u8 | void | |
| 3 | u8 | pad | |
| 4 | i32 | parent | index or -1 |
| 8 | i32 | first_child | |
| 12 | i32 | last_child | |
| 16 | i32 | next_sibling | |
| 20 | i32 | pad | |
| 24 | u8[40] | data | tag name or text |

### Tags (`TAG_*`)

| Id | Name |
|----|------|
| 0 | UNK |
| 1 | HTML |
| 2 | HEAD |
| 3 | BODY |
| 4 | TITLE |
| 5 | P |
| 6 | H1 |
| 7 | H2 |
| 8 | H3 |
| 9 | A |
| 10 | DIV |
| 11 | SPAN |
| 12 | IMG |
| 13 | UL |
| 14 | LI |
| 15 | SCRIPT |
| 16 | STYLE |
| 17 | BR |
| 18 | TABLE |
| 19 | TR |
| 20 | TD |
| 21 | TH |

## CSS — `engine_css.s` + `engine_style.inc`

`se_style_pool[node_id]` (`SE_STYLE_SIZE` 72B). Layout takes the pool via
`spark_layout_set_styles(rdi=pool, esi=count)`.

Display subset (`SE_DISP_*`): `none` `block` `inline` `inline-block`
`table` `table-row` `table-cell`. Props: `color`, `background-color`,
`font-size`, `margin`, `padding`, `border-width`, `border-color`,
`border-style`, `visibility`, `opacity`, `width`, `height`, `max-height`,
`min-height`, `max-width`, `min-width`, `display`. Tag selectors +
inline `style=` only.

**Layout box model (engine_layout.s):**
- Default display: `table`/`tr`/`td`/`th`/`img` → table/row/cell/inline-block
- `table-row`: equal-width cells side-by-side (`lay_ox` origin)
- `inline-block`: participates on the line (img / CSS); min width / img 32px subset
- Table cells (`td`/`th`): default tint + `SE_FLAG_BORDER`; CSS
  `border-width` px → SePaintBox `border_w` (+28) for multi-px paint
  stroke; `border-width:0` clears; unset → UA 1px
- Cell/block text: `lay_line_y` = box_y + padding (absolute) so glyphs paint
  inside the padded content band; `layout.table` reports `cell_text`
- Shorthand `padding` px: insets content below box top; grows box height
  (top+bottom); `layout.table` counts glyphs in `[cell_y, cell_y+h)`
- Shorthand `border-width` px: parse/merge into pool; gates cell border +
  multi-px paint stroke via SePaintBox+28
- CSS `border-color` (#hex/named): SePaintBox+32 stroke RGB; UA `#606060`
- CSS `border-style` (`none`|`solid`): `none` skips cell stroke; unset → UA
  solid
- CSS `visibility` (`visible`|`hidden`): inherits (nearest flagged
  ancestor); `hidden` keeps layout space, skips fill/border/text paint
- CSS `opacity` (`0`|`1` subset): UA 1; `0` keeps layout space, skips
  fill/border/text paint (no fractional alpha)
- CSS `transparent` keyword: `background-color` → SePaintBox NOFILL
  (border still ok); `color` → skip glyph paint (advance kept)
- CSS named `yellow` → `#ffff00` text/fill
- CSS named `cyan` → `#00ffff` text/fill
- CSS named `magenta` → `#ff00ff` text/fill
- CSS named `orange` → `#ffa500` text/fill
- CSS named `lime` → `#00ff00` text/fill
- CSS `color` (named + `#rrggbb`): paints **text** glyphs via parent walk
- CSS `background-color` (named + `#rrggbb`): paints block/cell **fills**
  (`SE_FLAG_BG` / `SE_OFF_BG`); unset → UA gray / cell tints
- Shorthand `margin` px: already live on block/cell (vertical gap)
- Shorthand `width` px: clamps block/cell box (+ kids) to min(width, avail);
  table-row cells prefer CSS width when set (else equal split)
- Shorthand `max-width` px: clamps after width (block/cell avail)
- Shorthand `min-width` px: expands floor after max-width (≤ parent avail)
- Shorthand `height` px: expands block/cell box to at least height
  (content taller wins)
- Shorthand `min-height` px: expands floor like height (before max)
- Shorthand `max-height` px: clamps box after height/min expand
- Not done: colspan/rowspan, % widths/heights, fractional opacity,
  full inline IFC

## SePaintBox — `engine_paint.s` (36 bytes)

Layout → paint stable ABI. FB max **640×480**.

| Off | Type | Name |
|-----|------|------|
| 0 | i32 | x |
| 4 | i32 | y |
| 8 | i32 | w |
| 12 | i32 | h |
| 16 | u8 | r |
| 17 | u8 | g |
| 18 | u8 | b |
| 19 | u8 | flags | bit0=text bit1=border |
| 20 | u32 | text_off | into text blob |
| 24 | u32 | text_len | |
| 28 | i32 | border_w | CSS border-width px (0→paint UA 1) |
| 32 | u32 | border_rgb | CSS border-color (UA `#606060`) |

Paint entry: `engine_paint_boxes(rdi=boxes, rsi=n, rdx=text_blob)`.

## Layout API (`asm/engine_layout.s`)

```
spark_layout_reset
spark_layout_set_viewport(edi=w, esi=h)   # use ≤640×480 for paint
spark_layout_set_styles(rdi=pool, esi=count)
spark_layout_run(rdi=nodes, esi=n, edx=root) → eax=box_count
spark_layout_box_count → eax
spark_layout_box_at(edi) → rax=&SePaintBox or 0
spark_layout_boxes_base → rax
spark_layout_text_blob → rax
spark_layout_box_stride → 36
spark_layout_fixture_simple / spark_layout_selftest
```

Wire: `engine layout` / `engine layout fixture` / `engine render`
(layout→paint_boxes→`out/engine/layout.ppm`→show; no DOM → paint_fixture).

Proof: `make test-engine-layout` · `./engine/tests/test_layout_boxes.sh`
(simple box_count=8 + table row cell0_x < cell1_x).
