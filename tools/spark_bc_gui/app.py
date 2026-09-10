"""Spark IDE GUI — browse / compile / dump / ask / weights / report.

Launch: ``python3 -m spark_bc_gui`` or ``./bin/spark-bc-gui``.
Dark engineer chrome (Spark palette). Functions first — not an
OpenBin clone. Never 6000. No frontier-parity claim.
"""

from __future__ import annotations

import re
import subprocess
import sys
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, scrolledtext, ttk

from . import core
from . import theme


class SparkIde(ttk.Frame):
    """Three-pane Spark IDE shell with real tool actions."""

    def __init__(self, master: tk.Tk) -> None:
        """Build browse | editor/dump | tools layout."""
        super().__init__(master)
        self.master = master
        self.root_path = core._repo_root()
        self._sparkbc_path: Path | None = None
        self._source_path: Path | None = None
        self._ops: list = []
        self._sync: list = []
        self._ask_notes = ""
        self._weight_path: Path | None = None
        self.pack(fill=tk.BOTH, expand=True)
        theme.apply_ttk_theme(master)
        self._build()

    def _text_widget(
        self, parent: tk.Misc, **kw: object
    ) -> scrolledtext.ScrolledText:
        """Monospace editor with shared Spark dark theme."""
        opts = {"wrap": tk.NONE}
        opts.update(kw)
        widget = scrolledtext.ScrolledText(parent, **opts)
        theme.style_scrolled_text(widget)
        return widget


    def _build(self) -> None:
        """Create chrome, three panes, status."""
        self.master.title("Spark IDE — browse · compile · ask · weights")
        self.master.geometry("1280x800")
        self._build_toolbar()
        body = ttk.Panedwindow(self, orient=tk.HORIZONTAL)
        body.pack(fill=tk.BOTH, expand=True, padx=6, pady=4)
        left = ttk.Frame(body, padding=4)
        center = ttk.Frame(body, padding=4)
        right = ttk.Frame(body, padding=4)
        body.add(left, weight=1)
        body.add(center, weight=3)
        body.add(right, weight=2)
        self._build_left(left)
        self._build_center(center)
        self._build_right(right)
        self.status = ttk.Label(
            self, text="Ready — Spark IDE (functions first)", style="Status.TLabel"
        )
        self.status.pack(fill=tk.X, padx=8, pady=(0, 6))
        self.on_sample()
        self.refresh_files()
        self.refresh_weights()
        self.refresh_helpers()

    def _build_toolbar(self) -> None:
        """First-class action buttons."""
        bar = ttk.Frame(self, padding=(6, 6, 6, 2))
        bar.pack(fill=tk.X)
        buttons = [
            ("Open…", self.on_open_any, None),
            ("Compile", self.on_compile, "Accent.TButton"),
            ("Decompile", self.on_decompile, None),
            ("Dump", self.on_decompile, None),
            ("Ask", self.on_ask_focus, None),
            ("Report", self.on_export_report, None),
            ("Sample", self.on_sample, None),
        ]
        for text, cmd, style_name in buttons:
            kw = {"text": text, "command": cmd}
            if style_name:
                kw["style"] = style_name
            ttk.Button(bar, **kw).pack(side=tk.LEFT, padx=2)

    def _build_left(self, parent: ttk.Frame) -> None:
        """Browse: files / opcodes / weights."""
        ttk.Label(parent, text="Browse").pack(anchor=tk.W)
        nb = ttk.Notebook(parent)
        nb.pack(fill=tk.BOTH, expand=True, pady=(4, 0))
        files_f = ttk.Frame(nb, padding=2)
        ops_f = ttk.Frame(nb, padding=2)
        w_f = ttk.Frame(nb, padding=2)
        nb.add(files_f, text="Files")
        nb.add(ops_f, text="Opcodes")
        nb.add(w_f, text="Weights")
        self.files_tree = ttk.Treeview(
            files_f, columns=("rel",), show="tree", selectmode="browse"
        )
        self.files_tree.pack(fill=tk.BOTH, expand=True)
        self.files_tree.bind("<<TreeviewSelect>>", self.on_file_select)
        self.ops_tree = ttk.Treeview(
            ops_f, columns=("label",), show="tree", selectmode="browse"
        )
        self.ops_tree.pack(fill=tk.BOTH, expand=True)
        self.ops_tree.bind("<<TreeviewSelect>>", self.on_op_select)
        self.weights_tree = ttk.Treeview(
            w_f, columns=("rel",), show="tree", selectmode="browse"
        )
        self.weights_tree.pack(fill=tk.BOTH, expand=True)
        self.weights_tree.bind("<<TreeviewSelect>>", self.on_weight_select)
        ttk.Button(
            files_f, text="Refresh", command=self.refresh_files
        ).pack(fill=tk.X, pady=2)
        ttk.Button(
            w_f, text="Refresh", command=self.refresh_weights
        ).pack(fill=tk.X, pady=2)

    def _build_center(self, parent: ttk.Frame) -> None:
        """Split source ↔ dump with sync highlight."""
        ttk.Label(parent, text="Source  ↔  Dump / disasm").pack(anchor=tk.W)
        panes = ttk.Panedwindow(parent, orient=tk.HORIZONTAL)
        panes.pack(fill=tk.BOTH, expand=True, pady=(4, 0))
        src_f = ttk.Frame(panes)
        dump_f = ttk.Frame(panes)
        panes.add(src_f, weight=1)
        panes.add(dump_f, weight=1)
        ttk.Label(src_f, text=".spark source").pack(anchor=tk.W)
        self.source = self._text_widget(src_f)
        self.source.pack(fill=tk.BOTH, expand=True)
        self.source.tag_configure(
            "sync", background=theme.IDE["selection"]
        )
        ttk.Label(dump_f, text="SPARK_BC dump").pack(anchor=tk.W)
        self.dump = self._text_widget(dump_f, font=("ui-monospace", 10))
        self.dump.pack(fill=tk.BOTH, expand=True)
        self.dump.tag_configure(
            "sync", background=theme.IDE["selection"]
        )
        self.dump.configure(state=tk.NORMAL)

    def _build_right(self, parent: ttk.Frame) -> None:
        """Tools: Ask / Weights play / Helpers / Report log."""
        ttk.Label(parent, text="Tools").pack(anchor=tk.W)
        nb = ttk.Notebook(parent)
        nb.pack(fill=tk.BOTH, expand=True, pady=(4, 0))
        ask_f = ttk.Frame(nb, padding=4)
        wt_f = ttk.Frame(nb, padding=4)
        help_f = ttk.Frame(nb, padding=4)
        log_f = ttk.Frame(nb, padding=4)
        nb.add(ask_f, text="Ask")
        nb.add(wt_f, text="Weights")
        nb.add(help_f, text="Helpers")
        nb.add(log_f, text="Output")
        self._tools_nb = nb
        ttk.Label(ask_f, text="Question over dump context").pack(anchor=tk.W)
        self.ask_entry = self._text_widget(ask_f, height=4, wrap=tk.WORD)
        self.ask_entry.pack(fill=tk.X, pady=2)
        ttk.Button(
            ask_f, text="Ask (text)", command=self.on_ask, style="Accent.TButton"
        ).pack(fill=tk.X, pady=2)
        ttk.Label(
            ask_f,
            text="Voice Ask hooks when tools/spark_ask lands",
            style="Muted.TLabel",
        ).pack(anchor=tk.W)
        self.ask_out = self._text_widget(ask_f, height=12, wrap=tk.WORD)
        self.ask_out.pack(fill=tk.BOTH, expand=True, pady=2)

        ttk.Label(wt_f, text="Tensor list / play (CPU)").pack(anchor=tk.W)
        self.tensor_tree = ttk.Treeview(
            wt_f, columns=("shape",), show="tree headings", selectmode="browse"
        )
        self.tensor_tree.heading("#0", text="tensor")
        self.tensor_tree.heading("shape", text="shape")
        self.tensor_tree.pack(fill=tk.BOTH, expand=True)
        ttk.Button(
            wt_f, text="Play selected", command=self.on_play_tensor
        ).pack(fill=tk.X, pady=2)
        self.weight_out = self._text_widget(wt_f, height=8, wrap=tk.WORD)
        self.weight_out.pack(fill=tk.BOTH, expand=True)

        ttk.Label(help_f, text="Helpers & shadows").pack(anchor=tk.W)
        self.helper_list = tk.Listbox(
            help_f,
            bg=theme.IDE["bg"],
            fg=theme.IDE["text"],
            selectbackground=theme.IDE["selection"],
            selectforeground=theme.IDE["accent"],
            relief=tk.FLAT,
            highlightthickness=1,
            highlightbackground=theme.IDE["border"],
        )
        self.helper_list.pack(fill=tk.BOTH, expand=True, pady=2)
        row = ttk.Frame(help_f)
        row.pack(fill=tk.X)
        ttk.Button(row, text="Run", command=self.on_run_helper).pack(
            side=tk.LEFT, expand=True, fill=tk.X, padx=(0, 2)
        )
        ttk.Button(
            row, text="Shadow copy", command=lambda: self.on_run_shadow("copy")
        ).pack(side=tk.LEFT, expand=True, fill=tk.X)

        self.tool_log = self._text_widget(log_f, wrap=tk.WORD)
        self.tool_log.pack(fill=tk.BOTH, expand=True)

    def _set_status(self, text: str) -> None:
        self.status.configure(text=text)

    def _log(self, text: str) -> None:
        self.tool_log.insert(tk.END, text.rstrip() + "\n")
        self.tool_log.see(tk.END)

    def _clear_sync(self) -> None:
        self.source.tag_remove("sync", "1.0", tk.END)
        self.dump.tag_remove("sync", "1.0", tk.END)

    def _highlight_sync(
        self, source_line: int | None, dump_needle: str | None
    ) -> None:
        """Highlight matching source line and dump opcode line."""
        self._clear_sync()
        if source_line:
            start = "%d.0" % source_line
            end = "%d.0" % (source_line + 1)
            self.source.tag_add("sync", start, end)
            self.source.see(start)
        if dump_needle:
            dump_text = self.dump.get("1.0", tk.END)
            line = core.dump_line_for_needle(dump_text, dump_needle)
            if line:
                start = "%d.0" % line
                end = "%d.0" % (line + 1)
                self.dump.tag_add("sync", start, end)
                self.dump.see(start)

    def _set_dump(self, text: str) -> None:
        self.dump.delete("1.0", tk.END)
        self.dump.insert("1.0", text)

    def _refresh_ops_tree(self) -> None:
        self.ops_tree.delete(*self.ops_tree.get_children())
        if not self._sparkbc_path:
            return
        try:
            rows = core.browse_opcodes(
                self._sparkbc_path, root=self.root_path
            )
        except (OSError, ValueError, RuntimeError) as exc:
            self._log("opcodes: %s" % exc)
            return
        self._ops = rows
        for row in rows:
            self.ops_tree.insert(
                "", tk.END, iid=str(row["ip"]), text=row["label"]
            )
        src = self.source.get("1.0", tk.END)
        try:
            self._sync = core.sync_map(
                src, self._sparkbc_path, root=self.root_path
            )
        except (OSError, ValueError, RuntimeError):
            self._sync = []

    def refresh_files(self) -> None:
        """Reload Files browse pane."""
        self.files_tree.delete(*self.files_tree.get_children())
        for row in core.list_workspace_files(self.root_path):
            self.files_tree.insert(
                "", tk.END, iid=row["path"], text=row["label"]
            )

    def refresh_weights(self) -> None:
        """Reload Weights browse pane."""
        self.weights_tree.delete(*self.weights_tree.get_children())
        for row in core.list_weight_files(self.root_path):
            self.weights_tree.insert(
                "", tk.END, iid=row["path"], text=row["label"]
            )

    def refresh_helpers(self) -> None:
        """Fill helpers listbox."""
        self.helper_list.delete(0, tk.END)
        self._helper_keys: list[str] = []
        for h in core.list_helpers(self.root_path):
            mark = "✓" if h["available"] else "·"
            self.helper_list.insert(
                tk.END, "%s %s" % (mark, h["label"])
            )
            self._helper_keys.append(h["key"])
        for s in core.list_shadows(self.root_path):
            mark = "✓" if s["available"] else "·"
            self.helper_list.insert(
                tk.END, "%s %s" % (mark, s["label"])
            )
            self._helper_keys.append("shadow:%s" % s["key"])

    def on_sample(self) -> None:
        """Load sample source into the editor."""
        self.source.delete("1.0", tk.END)
        self.source.insert("1.0", core.sample_source())
        self._source_path = None
        self._set_status("Loaded sample source")

    def on_open_any(self) -> None:
        """Open ``.spark`` or ``.sparkbc``."""
        path = filedialog.askopenfilename(
            title="Open Spark file",
            filetypes=[
                ("Spark", "*.spark *.sparkbc"),
                ("Source", "*.spark"),
                ("SPARK_BC", "*.sparkbc"),
                ("All", "*.*"),
            ],
        )
        if not path:
            return
        self._open_path(Path(path))

    def _open_path(self, path: Path) -> None:
        """Open source or bytecode into the IDE panes."""
        path = path.resolve()
        if path.suffix.lower() == ".sparkbc":
            self._sparkbc_path = path
            try:
                text = core.decompile_sparkbc(
                    path, root=self.root_path
                )
            except (OSError, ValueError, RuntimeError) as exc:
                messagebox.showerror("Decompile failed", str(exc))
                return
            self._set_dump(text)
            self._refresh_ops_tree()
            self._set_status("Opened %s" % path)
            return
        text = path.read_text(encoding="utf-8")
        self.source.delete("1.0", tk.END)
        self.source.insert("1.0", text)
        self._source_path = path
        self._set_status("Opened %s" % path)

    def on_file_select(self, _event: object = None) -> None:
        """Jump-open from Files browse."""
        sel = self.files_tree.selection()
        if not sel:
            return
        self._open_path(Path(sel[0]))

    def on_op_select(self, _event: object = None) -> None:
        """Jump dump + sync highlight from opcode list."""
        sel = self.ops_tree.selection()
        if not sel:
            return
        ip = int(sel[0])
        row = next((r for r in self._ops if int(r["ip"]) == ip), None)
        if not row:
            return
        src_line = None
        for m in self._sync:
            if int(m["ip"]) == ip:
                src_line = m.get("source_line")
                break
        self._highlight_sync(src_line, row.get("dump_needle"))
        self._set_status("Jump %s" % row["label"])

    def on_weight_select(self, _event: object = None) -> None:
        """Load tensor list for selected safetensors."""
        sel = self.weights_tree.selection()
        if not sel:
            return
        path = Path(sel[0])
        self._weight_path = path
        try:
            summary = core.summarize_weights(
                path, root=self.root_path
            )
        except (OSError, ValueError, KeyError) as exc:
            messagebox.showerror("Weights", str(exc))
            return
        self.tensor_tree.delete(*self.tensor_tree.get_children())
        for t in summary["tensors"]:
            self.tensor_tree.insert(
                "",
                tk.END,
                iid=t["name"],
                text=t["name"],
                values=("×".join(str(x) for x in t["shape"]),),
            )
        self._tools_nb.select(1)
        meta = summary.get("metadata") or {}
        self.weight_out.delete("1.0", tk.END)
        self.weight_out.insert(
            "1.0",
            "Loaded %s (%d tensors)\nmeta: %s\n"
            % (path.name, summary["count"], json_preview(meta)),
        )
        self._set_status("Weights %s" % path)

    def on_play_tensor(self) -> None:
        """Play selected tensor stats on CPU."""
        if not self._weight_path:
            messagebox.showinfo("Weights", "Select a weights file first")
            return
        sel = self.tensor_tree.selection()
        if not sel:
            messagebox.showinfo("Weights", "Select a tensor")
            return
        try:
            play = core.play_tensor(
                self._weight_path, sel[0], root=self.root_path
            )
        except (OSError, ValueError, KeyError) as exc:
            messagebox.showerror("Play failed", str(exc))
            return
        msg = (
            "%s shape=%s n=%d mean=%.6f min=%.6f max=%.6f\n"
            "sample=%s\n%s\n"
            % (
                play["name"],
                play["shape"],
                play["n"],
                play["mean"],
                play["min"],
                play["max"],
                play["sample"],
                play.get("note") or "",
            )
        )
        self.weight_out.insert(tk.END, msg)
        self._log(msg)
        self._set_status("Played %s (CPU)" % play["name"])

    def on_compile(self) -> None:
        """Compile editor text via real ``--compile``."""
        text = self.source.get("1.0", tk.END)
        default = None
        if self._source_path:
            default = str(self._source_path.with_suffix(".sparkbc"))
        out = filedialog.asksaveasfilename(
            title="Save SPARK_BC as",
            defaultextension=".sparkbc",
            initialfile=Path(default).name if default else "out.sparkbc",
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
        self._set_dump(dump)
        self._refresh_ops_tree()
        # Auto sync-highlight first string-linked opcode
        for m in self._sync:
            if m.get("source_line"):
                self._highlight_sync(
                    m["source_line"], m["dump_needle"]
                )
                break
        msg = "Compiled %s (%d bytes, sha %s…)" % (
            result["out"],
            result["size"],
            result["sha256"][:12],
        )
        self._log(msg)
        self._set_status(msg)

    def on_decompile(self) -> None:
        """Re-run decompile on last or chosen ``.sparkbc``."""
        if self._sparkbc_path and self._sparkbc_path.is_file():
            path = self._sparkbc_path
        else:
            path_s = filedialog.askopenfilename(
                title="Open SPARK_BC",
                filetypes=[
                    ("SPARK_BC", "*.sparkbc"),
                    ("All", "*.*"),
                ],
            )
            if not path_s:
                return
            path = Path(path_s)
            self._sparkbc_path = path
        try:
            text = core.decompile_sparkbc(path, root=self.root_path)
        except (OSError, ValueError, RuntimeError) as exc:
            messagebox.showerror("Decompile failed", str(exc))
            return
        self._set_dump(text)
        self._refresh_ops_tree()
        self._set_status("Decompiled %s" % path)

    def on_ask_focus(self) -> None:
        """Switch to Ask tab."""
        self._tools_nb.select(0)
        self.ask_entry.focus_set()

    def on_ask(self) -> None:
        """Run text Ask over current dump context."""
        question = self.ask_entry.get("1.0", tk.END).strip()
        if not question:
            messagebox.showinfo("Ask", "Enter a question")
            return
        dump_text = self.dump.get("1.0", tk.END)
        sha = ""
        m = re.search(r"sha256:\s*([0-9a-f]{64})", dump_text)
        if m:
            sha = m.group(1)
        try:
            result = core.ask_over_dump(
                question,
                dump_text=dump_text,
                ops=self._ops,
                sha256=sha,
                sparkbc=self._sparkbc_path,
                root=self.root_path,
            )
        except (OSError, ValueError, RuntimeError) as exc:
            messagebox.showerror("Ask failed", str(exc))
            return
        answer = str(result.get("answer") or "")
        engine = str(result.get("engine") or "?")
        block = "[%s]\n%s\n" % (engine, answer)
        self.ask_out.delete("1.0", tk.END)
        self.ask_out.insert("1.0", block)
        self._ask_notes = (
            self._ask_notes + "\n### Q\n%s\n\n### A\n%s\n" % (question, answer)
        ).strip()
        self._log("ask/%s: %s" % (engine, question[:80]))
        self._set_status("Ask via %s" % engine)

    def on_export_report(self) -> None:
        """Export markdown analysis stub."""
        path = filedialog.asksaveasfilename(
            title="Export report",
            defaultextension=".md",
            filetypes=[("Markdown", "*.md"), ("All", "*.*")],
        )
        if not path:
            return
        dump_text = self.dump.get("1.0", tk.END)
        sha = ""
        m = re.search(r"sha256:\s*([0-9a-f]{64})", dump_text)
        if m:
            sha = m.group(1)
        md = core.export_report_markdown(
            dump_text=dump_text,
            ops=self._ops,
            sha256=sha,
            source_path=str(self._source_path or ""),
            sparkbc_path=str(self._sparkbc_path or ""),
            ask_notes=self._ask_notes,
        )
        Path(path).write_text(md, encoding="utf-8")
        self._log("Wrote report %s" % path)
        self._set_status("Report %s" % path)

    def on_run_helper(self) -> None:
        """Run selected helper or shadow entry."""
        idx = self.helper_list.curselection()
        if not idx:
            messagebox.showinfo("Helpers", "Select a helper")
            return
        key = self._helper_keys[idx[0]]
        try:
            if key.startswith("shadow:"):
                result = core.run_shadow(
                    key.split(":", 1)[1], root=self.root_path
                )
            else:
                result = core.run_helper(key, root=self.root_path)
        except (OSError, FileNotFoundError, subprocess.TimeoutExpired) as exc:
            messagebox.showerror("Helper failed", str(exc))
            return
        out = (result.get("stdout") or "") + (result.get("stderr") or "")
        self._tools_nb.select(3)
        self._log("$ %s\n%s" % (result.get("command"), out[:4000]))
        self._set_status(
            "%s → exit %s" % (key, result.get("returncode"))
        )

    def on_run_shadow(self, action: str) -> None:
        """One-click shadow action."""
        try:
            result = core.run_shadow(action, root=self.root_path)
        except (OSError, FileNotFoundError, subprocess.TimeoutExpired) as exc:
            messagebox.showerror("Shadow failed", str(exc))
            return
        out = (result.get("stdout") or "") + (result.get("stderr") or "")
        self._tools_nb.select(3)
        self._log("$ %s\n%s" % (result.get("command"), out[:4000]))
        self._set_status(
            "shadow:%s → exit %s" % (action, result.get("returncode"))
        )


def json_preview(obj: object, limit: int = 200) -> str:
    """Short JSON preview for status panes."""
    import json

    try:
        text = json.dumps(obj, sort_keys=True)
    except TypeError:
        text = str(obj)
    if len(text) > limit:
        return text[:limit] + "…"
    return text


# Keep old class name for import compatibility
SparkBcGui = SparkIde


def main(argv: list[str] | None = None) -> int:
    """Start the Spark IDE graphical shell."""
    _ = argv
    try:
        root = tk.Tk()
    except tk.TclError as exc:
        print(
            "spark-bc-gui: no display (tkinter): %s" % exc,
            file=sys.stderr,
        )
        return 2
    SparkIde(root)
    root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
