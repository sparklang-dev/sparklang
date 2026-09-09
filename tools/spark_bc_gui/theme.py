"""Spark GUI theme — mirrors website/css/tokens.json (IDE dark)."""

from __future__ import annotations

# Keep hex in sync with website/css/tokens.css --ide-* and tokens.json.
IDE = {
    "bg": "#12151a",
    "bg_panel": "#1a1e26",
    "bg_elevated": "#222833",
    "border": "#2e3642",
    "text": "#e8eaed",
    "text_muted": "#9aa3b2",
    "accent": "#e85d04",
    "accent_dark": "#c44d03",
    "focus": "#5eb1ff",
    "selection": "#1a3a5c",
}

FONT_MONO = ("IBM Plex Mono", "Cascadia Code", "Consolas", "monospace")
FONT_UI = ("IBM Plex Sans", "Segoe UI", "Helvetica", "sans-serif")


def apply_ttk_theme(root) -> None:
    """Apply dense dark engineer chrome to a Tk root + ttk styles."""
    import tkinter as tk
    from tkinter import ttk

    root.configure(bg=IDE["bg"])
    style = ttk.Style(root)
    # clam paints backgrounds reliably across platforms
    try:
        style.theme_use("clam")
    except tk.TclError:
        pass

    style.configure(
        ".",
        background=IDE["bg_panel"],
        foreground=IDE["text"],
        fieldbackground=IDE["bg"],
        bordercolor=IDE["border"],
        troughcolor=IDE["bg"],
        focuscolor=IDE["focus"],
        font=(FONT_UI[0], 10),
    )
    style.configure("TFrame", background=IDE["bg_panel"])
    style.configure("TLabel", background=IDE["bg_panel"], foreground=IDE["text"])
    style.configure(
        "Muted.TLabel",
        background=IDE["bg_panel"],
        foreground=IDE["text_muted"],
        font=(FONT_UI[0], 9),
    )
    style.configure(
        "Status.TLabel",
        background=IDE["bg_elevated"],
        foreground=IDE["text_muted"],
        font=(FONT_MONO[0], 9),
        padding=(8, 4),
    )
    style.configure(
        "TButton",
        background=IDE["bg_elevated"],
        foreground=IDE["text"],
        bordercolor=IDE["border"],
        focusthickness=2,
        focuscolor=IDE["focus"],
        padding=(10, 5),
        font=(FONT_UI[0], 9, "bold"),
    )
    style.map(
        "TButton",
        background=[
            ("active", IDE["accent_dark"]),
            ("pressed", IDE["accent_dark"]),
        ],
        foreground=[("active", "#ffffff"), ("pressed", "#ffffff")],
    )
    style.configure(
        "Accent.TButton",
        background=IDE["accent"],
        foreground="#ffffff",
        bordercolor=IDE["accent_dark"],
    )
    style.map(
        "Accent.TButton",
        background=[
            ("active", IDE["accent_dark"]),
            ("pressed", IDE["accent_dark"]),
        ],
    )
    style.configure(
        "TPanedwindow",
        background=IDE["bg"],
    )
    style.configure(
        "TNotebook",
        background=IDE["bg_panel"],
        borderwidth=0,
    )
    style.configure(
        "TNotebook.Tab",
        background=IDE["bg_elevated"],
        foreground=IDE["text_muted"],
        padding=(10, 4),
    )
    style.map(
        "TNotebook.Tab",
        background=[("selected", IDE["bg_panel"])],
        foreground=[("selected", IDE["text"])],
    )


def style_scrolled_text(widget) -> None:
    """Dark monospace editor / dump pane."""
    widget.configure(
        bg=IDE["bg"],
        fg=IDE["text"],
        insertbackground=IDE["accent"],
        selectbackground=IDE["selection"],
        selectforeground=IDE["text"],
        highlightthickness=1,
        highlightbackground=IDE["border"],
        highlightcolor=IDE["focus"],
        relief="flat",
        borderwidth=0,
        font=(FONT_MONO[0], 11),
        padx=8,
        pady=8,
    )
