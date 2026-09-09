"""Tkinter GUI for SparkLang SPARK_BC compile + decompile.

Launch: ``python3 -m spark_bc_gui`` (from tools/) or
``./bin/spark-bc-gui`` inside the SDK pack. Calls real
``spark-bootstrap --compile`` and ``bc_dump.format_dump``.
"""

from __future__ import annotations

import sys
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, scrolledtext, ttk

from . import core


class SparkBcGui(ttk.Frame):
    """Main window: source editor + bytecode inspector."""

    def __init__(self, master: tk.Tk) -> None:
        """Build the compile / decompile panes."""
        super().__init__(master, padding=8)
        self.master = master
        self.root_path = core._repo_root()
        self._sparkbc_path: Path | None = None
        self.pack(fill=tk.BOTH, expand=True)
        self._build()

    def _build(self) -> None:
        """Create toolbar, notebooks, and status."""
        self.master.title("SparkLang — SPARK_BC compile / decompile")
        self.master.geometry("960x640")
        toolbar = ttk.Frame(self)
        toolbar.pack(fill=tk.X, pady=(0, 6))
        ttk.Button(
            toolbar, text="Compile → .sparkbc", command=self.on_compile
        ).pack(side=tk.LEFT, padx=2)
        ttk.Button(
            toolbar, text="Decompile .sparkbc", command=self.on_decompile
        ).pack(side=tk.LEFT, padx=2)
        ttk.Button(
            toolbar, text="Open source…", command=self.on_open_source
        ).pack(side=tk.LEFT, padx=2)
        ttk.Button(
            toolbar, text="Open .sparkbc…", command=self.on_open_bc
        ).pack(side=tk.LEFT, padx=2)
        ttk.Button(
            toolbar, text="Save dump…", command=self.on_save_dump
        ).pack(side=tk.LEFT, padx=2)
        ttk.Button(
            toolbar, text="Load sample", command=self.on_sample
        ).pack(side=tk.LEFT, padx=2)

        panes = ttk.Panedwindow(self, orient=tk.HORIZONTAL)
        panes.pack(fill=tk.BOTH, expand=True)
        left = ttk.Frame(panes)
        right = ttk.Frame(panes)
        panes.add(left, weight=1)
        panes.add(right, weight=1)
        ttk.Label(left, text=".spark source").pack(anchor=tk.W)
        self.source = scrolledtext.ScrolledText(
            left, wrap=tk.NONE, font=("monospace", 11)
        )
        self.source.pack(fill=tk.BOTH, expand=True)
        ttk.Label(right, text="SPARK_BC dump / decompile").pack(
            anchor=tk.W
        )
        self.dump = scrolledtext.ScrolledText(
            right, wrap=tk.NONE, font=("monospace", 10)
        )
        self.dump.pack(fill=tk.BOTH, expand=True)
        self.status = ttk.Label(self, text="Ready")
        self.status.pack(fill=tk.X, pady=(6, 0))
        self.on_sample()

    def _set_status(self, text: str) -> None:
        self.status.configure(text=text)

    def on_sample(self) -> None:
        """Fill the editor with a minimal SparkLang program."""
        self.source.delete("1.0", tk.END)
        self.source.insert("1.0", core.sample_source())
        self._set_status("Loaded sample source")

    def on_open_source(self) -> None:
        """Load a ``.spark`` file into the editor."""
        path = filedialog.askopenfilename(
            title="Open SparkLang source",
            filetypes=[
                ("Spark", "*.spark"),
                ("All", "*.*"),
            ],
        )
        if not path:
            return
        text = Path(path).read_text(encoding="utf-8")
        self.source.delete("1.0", tk.END)
        self.source.insert("1.0", text)
        self._set_status("Opened %s" % path)

    def on_open_bc(self) -> None:
        """Open a ``.sparkbc`` and show the decompiled dump."""
        path = filedialog.askopenfilename(
            title="Open SPARK_BC",
            filetypes=[
                ("SPARK_BC", "*.sparkbc"),
                ("All", "*.*"),
            ],
        )
        if not path:
            return
        self._sparkbc_path = Path(path)
        try:
            text = core.decompile_sparkbc(
                path, root=self.root_path
            )
        except (OSError, ValueError, RuntimeError) as exc:
            messagebox.showerror("Decompile failed", str(exc))
            return
        self.dump.delete("1.0", tk.END)
        self.dump.insert("1.0", text)
        self._set_status("Decompiled %s" % path)

    def on_compile(self) -> None:
        """Compile editor text via real ``--compile``."""
        text = self.source.get("1.0", tk.END)
        out = filedialog.asksaveasfilename(
            title="Save SPARK_BC as",
            defaultextension=".sparkbc",
            filetypes=[("SPARK_BC", "*.sparkbc")],
        )
        if not out:
            return
        try:
            result = core.compile_source_text(
                text,
                out=out,
                root=self.root_path,
            )
        except (OSError, RuntimeError, FileNotFoundError) as exc:
            messagebox.showerror("Compile failed", str(exc))
            self._set_status("Compile failed")
            return
        self._sparkbc_path = Path(result["out"])
        try:
            dump = core.decompile_sparkbc(
                result["out"],
                source=result["source"],
                command=result["command"],
                root=self.root_path,
            )
        except (OSError, ValueError) as exc:
            messagebox.showerror("Dump failed", str(exc))
            return
        self.dump.delete("1.0", tk.END)
        self.dump.insert("1.0", dump)
        self._set_status(
            "Compiled %s (%d bytes, sha256 %s…)"
            % (result["out"], result["size"], result["sha256"][:12])
        )

    def on_decompile(self) -> None:
        """Re-run decompile on the last or chosen ``.sparkbc``."""
        if self._sparkbc_path and self._sparkbc_path.is_file():
            path = self._sparkbc_path
        else:
            self.on_open_bc()
            return
        try:
            text = core.decompile_sparkbc(
                path, root=self.root_path
            )
        except (OSError, ValueError, RuntimeError) as exc:
            messagebox.showerror("Decompile failed", str(exc))
            return
        self.dump.delete("1.0", tk.END)
        self.dump.insert("1.0", text)
        self._set_status("Decompiled %s" % path)

    def on_save_dump(self) -> None:
        """Save the dump pane to a text file."""
        path = filedialog.asksaveasfilename(
            title="Save dump",
            defaultextension=".txt",
            filetypes=[("Text", "*.txt"), ("All", "*.*")],
        )
        if not path:
            return
        Path(path).write_text(
            self.dump.get("1.0", tk.END), encoding="utf-8"
        )
        self._set_status("Wrote dump %s" % path)


def main(argv: list[str] | None = None) -> int:
    """Start the graphical compile / decompile app."""
    _ = argv
    try:
        root = tk.Tk()
    except tk.TclError as exc:
        print(
            "spark-bc-gui: no display (tkinter): %s" % exc,
            file=sys.stderr,
        )
        return 2
    style = ttk.Style(root)
    if "clam" in style.theme_names():
        style.theme_use("clam")
    SparkBcGui(root)
    root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
