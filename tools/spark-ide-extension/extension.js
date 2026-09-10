/* eslint-disable */
/**
 * SparkLang editor support — TextMate + LSP client spawn +
 * in-process hover/completion fallback.
 * Product name: Spark / SparkLang only.
 */
const vscode = require("vscode");
const path = require("path");
const fs = require("fs");
const { spawn } = require("child_process");

const HOVER = {
  ask: "Gateway or dry ask — bind with -> name",
  classify: "Intent / multi-label classify (dry fixtures)",
  expect: "Pass/fail assert: equal | contains [fixture]",
  retrieve: "RAG retrieve — dry fixtures or live gateway",
  embed: "Embed text to vectors",
  shell: "Host escape — dry allowlist; live needs --allow-shell",
  model: "Select model alias (fast / code / best / …)",
  train: "Submit train job (dry accepted fixture)",
  http: "http get|post with optional bearer / retries",
  ide: "IDE buffer ops (new/open/save/run/ask/show)",
  voice: "Voice demos — not production telephony",
  binary: "Local ELF probe — not Ghidra-class RE",
  extract: "Typed extract + schema validate / retry",
  print: "Print a bound value or literal",
  let: "Bind a name to a string / value",
};

const KEYWORDS = Object.keys(HOVER).concat([
  "generate",
  "pipeline",
  "tool",
  "with",
  "tools",
  "listen",
  "speak",
  "review",
  "builder",
  "implement",
  "cuda",
  "memory",
  "pcie",
  "network",
  "os",
  "browser",
  "mitm",
  "crypto",
  "encrypt",
  "gateway",
  "multi",
  "min_confidence",
  "run",
  "status",
  "get",
  "post",
  "bearer",
  "header",
  "retries",
  "backoff",
  "stream",
  "open",
  "save",
  "buffer",
  "new",
  "keys",
  "key",
  "show",
  "from",
  "project",
  "head",
  "abstain",
  "equal",
  "contains",
  "fixture",
  "fast",
  "code",
  "best",
  "code-max",
  "code-bulk",
]);

function findRepoRoot(start) {
  let cur = start;
  for (let i = 0; i < 14; i++) {
    const server = path.join(cur, "tools", "spark_lsp", "server.py");
    const makefile = path.join(cur, "Makefile");
    if (fs.existsSync(server) && fs.existsSync(makefile)) {
      return cur;
    }
    const parent = path.dirname(cur);
    if (parent === cur) break;
    cur = parent;
  }
  return start;
}

function wordAt(document, position) {
  const range = document.getWordRangeAtPosition(
    position,
    /[A-Za-z_][\w-]*/
  );
  return range ? document.getText(range) : "";
}

function activate(context) {
  const folder =
    vscode.workspace.workspaceFolders &&
    vscode.workspace.workspaceFolders[0]
      ? vscode.workspace.workspaceFolders[0].uri.fsPath
      : process.cwd();
  const root = findRepoRoot(folder);
  const serverPy = path.join(root, "tools", "spark_lsp", "server.py");

  const hover = vscode.languages.registerHoverProvider("spark", {
    provideHover(document, position) {
      const w = wordAt(document, position);
      if (!w) return null;
      const tip = HOVER[w];
      if (!tip) {
        if (KEYWORDS.indexOf(w) >= 0) {
          return new vscode.Hover(`**${w}** — SparkLang keyword`);
        }
        return null;
      }
      return new vscode.Hover(`**${w}** — ${tip}`);
    },
  });

  const complete = vscode.languages.registerCompletionItemProvider(
    "spark",
    {
      provideCompletionItems(document, position) {
        const w = wordAt(document, position);
        const items = [];
        for (let i = 0; i < KEYWORDS.length; i++) {
          const kw = KEYWORDS[i];
          if (w && kw.indexOf(w) !== 0) continue;
          const item = new vscode.CompletionItem(
            kw,
            vscode.CompletionItemKind.Keyword
          );
          item.detail = "SparkLang";
          if (HOVER[kw]) item.documentation = HOVER[kw];
          items.push(item);
        }
        return items;
      },
    },
    " ",
    "."
  );

  const collection = vscode.languages.createDiagnosticCollection(
    "spark-lsp"
  );

  function refreshDiags(document) {
    if (!document || document.languageId !== "spark") return;
    if (!fs.existsSync(serverPy)) {
      collection.set(document.uri, []);
      return;
    }
    const tmp = path.join(
      require("os").tmpdir(),
      "spark-lsp-" + Date.now() + ".spark"
    );
    fs.writeFileSync(tmp, document.getText(), "utf8");
    const child = spawn(
      process.env.SPARK_LSP_PYTHON || "python3",
      [serverPy, "--check", tmp],
      { cwd: root }
    );
    let out = "";
    child.stdout.on("data", (b) => {
      out += b.toString();
    });
    child.on("close", () => {
      try {
        fs.unlinkSync(tmp);
      } catch (e) {
        /* ignore */
      }
      let payload;
      try {
        payload = JSON.parse(out);
      } catch (e) {
        collection.set(document.uri, []);
        return;
      }
      const list = [];
      const diags = payload.diagnostics || [];
      for (let i = 0; i < diags.length; i++) {
        const d = diags[i];
        const sev =
          d.severity === "Error"
            ? vscode.DiagnosticSeverity.Error
            : d.severity === "Warning"
              ? vscode.DiagnosticSeverity.Warning
              : vscode.DiagnosticSeverity.Information;
        const range = new vscode.Range(
          d.line,
          d.character,
          d.line,
          d.endCharacter || d.character + 1
        );
        const diag = new vscode.Diagnostic(range, d.message, sev);
        diag.source = "spark-lsp";
        diag.code = d.code;
        list.push(diag);
      }
      collection.set(document.uri, list);
    });
  }

  context.subscriptions.push(
    hover,
    complete,
    collection,
    vscode.workspace.onDidOpenTextDocument(refreshDiags),
    vscode.workspace.onDidSaveTextDocument(refreshDiags),
    vscode.workspace.onDidChangeTextDocument((e) => {
      if (e.document.languageId === "spark") {
        refreshDiags(e.document);
      }
    }),
    vscode.commands.registerCommand("spark.voiceEasyTrain", async () => {
      const term = vscode.window.createTerminal({
        name: "Spark voice easy",
        cwd: root,
      });
      term.show(true);
      term.sendText("./spark-voice easy --dry --device auto --scale tiny");
      vscode.window.showInformationMessage(
        "Spark voice easy: tiny dry train (not ElevenLabs)"
      );
    }),
    vscode.commands.registerCommand("spark.checkBuffer", async () => {
      const ed = vscode.window.activeTextEditor;
      if (!ed || ed.document.languageId !== "spark") {
        vscode.window.showWarningMessage("Open a .spark file first");
        return;
      }
      refreshDiags(ed.document);
      vscode.window.showInformationMessage("Spark LSP: refreshed diagnostics");
    })
  );

  vscode.workspace.textDocuments.forEach(refreshDiags);
}

function deactivate() {}

module.exports = { activate, deactivate };
