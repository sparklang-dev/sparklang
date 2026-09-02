# Shared computed-style ABI for engine B (CSS → layout).
# Indexed by HTML DOM node id (engine_html.s NODE_SIZE 64).
# Layout: spark_layout_set_styles(pool) + se_style_count.
#
# SeComputedStyle — 72 bytes
# +0   display      i32   see SE_DISP_* (real CSS subset)
# +4   color_rgb    u32   0x00RRGGBB (text ink)
# +8   font_size_px i32
# +12  margin_px    i32   shorthand
# +16  flags        i32   bit0..bit15 + bit16 opacity
# +20  padding_px   i32
# +24  border_w_px  i32
# +28  bg_rgb       u32   0xFFFFFFFF = transparent
# +32  width_px     i32
# +36  height_px    i32
# +40  max_height_px i32
# +44  min_height_px i32
# +48  max_width_px  i32
# +52  min_width_px  i32
# +56  border_rgb    u32
# +60  border_style  i32  0=none 1=solid (UA solid when unset)
# +64  visibility    i32  0=visible 1=hidden (inherits; UA visible)
# +68  opacity       i32  0 or 1 (UA 1; 0 skips paint, keeps space)

.equ SE_STYLE_SIZE, 72
.equ SE_STYLE_MAX, 256
.equ SE_RULE_MAX, 32
.equ SE_TAG_MAX, 20
.equ SE_RULE_STRIDE, 92

.equ SE_DISP_NONE, 0
.equ SE_DISP_BLOCK, 1
.equ SE_DISP_INLINE, 2
.equ SE_DISP_INLINE_BLOCK, 3
.equ SE_DISP_TABLE, 4
.equ SE_DISP_TABLE_ROW, 5
.equ SE_DISP_TABLE_CELL, 6

.equ SE_BORDER_NONE, 0
.equ SE_BORDER_SOLID, 1

.equ SE_VIS_VISIBLE, 0
.equ SE_VIS_HIDDEN, 1

.equ SE_BG_TRANSPARENT, 0xFFFFFFFF

.equ SE_FLAG_COLOR, 1
.equ SE_FLAG_FONT, 2
.equ SE_FLAG_MARGIN, 4
.equ SE_FLAG_DISPLAY, 8
.equ SE_FLAG_PADDING, 16
.equ SE_FLAG_BORDER_W, 32
.equ SE_FLAG_BG, 64
.equ SE_FLAG_WIDTH, 128
.equ SE_FLAG_HEIGHT, 256
.equ SE_FLAG_MAX_HEIGHT, 512
.equ SE_FLAG_MIN_HEIGHT, 1024
.equ SE_FLAG_MAX_WIDTH, 2048
.equ SE_FLAG_MIN_WIDTH, 4096
.equ SE_FLAG_BORDER_C, 8192
.equ SE_FLAG_BORDER_S, 16384
.equ SE_FLAG_VIS, 32768
.equ SE_FLAG_OPACITY, 65536

.equ SE_OFF_DISPLAY, 0
.equ SE_OFF_COLOR, 4
.equ SE_OFF_FONT, 8
.equ SE_OFF_MARGIN, 12
.equ SE_OFF_FLAGS, 16
.equ SE_OFF_PADDING, 20
.equ SE_OFF_BORDER_W, 24
.equ SE_OFF_BG, 28
.equ SE_OFF_WIDTH, 32
.equ SE_OFF_HEIGHT, 36
.equ SE_OFF_MAX_HEIGHT, 40
.equ SE_OFF_MIN_HEIGHT, 44
.equ SE_OFF_MAX_WIDTH, 48
.equ SE_OFF_MIN_WIDTH, 52
.equ SE_OFF_BORDER_C, 56
.equ SE_OFF_BORDER_S, 60
.equ SE_OFF_VIS, 64
.equ SE_OFF_OPACITY, 68
