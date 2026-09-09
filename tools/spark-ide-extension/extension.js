/* eslint-disable */
/**
 * Spark IDE extension — CLI-first hooks.
 * "Voice easy train" runs ./spark-voice easy --dry in a terminal.
 * Not a full IDE product; stub landing for sibling IDE packs.
 */
const vscode = require("vscode");
const path = require("path");
const fs = require("fs");

function findRepoRoot(start) {
  let cur = start;
  for (let i = 0; i < 12; i++) {
    const marker = path.join(cur, "spark-voice");
    const makefile = path.join(cur, "Makefile");
    if (fs.existsSync(marker) && fs.existsSync(makefile)) {
      return cur;
    }
    const parent = path.dirname(cur);
    if (parent === cur) break;
    cur = parent;
  }
  return start;
}

function activate(context) {
  const disposable = vscode.commands.registerCommand(
    "spark.voiceEasyTrain",
    async () => {
      const folder =
        vscode.workspace.workspaceFolders &&
        vscode.workspace.workspaceFolders[0]
          ? vscode.workspace.workspaceFolders[0].uri.fsPath
          : process.cwd();
      const root = findRepoRoot(folder);
      const term = vscode.window.createTerminal({
        name: "Spark voice easy",
        cwd: root,
      });
      term.show(true);
      term.sendText("./spark-voice easy --dry --device auto --scale tiny");
      vscode.window.showInformationMessage(
        "Spark voice easy: tiny dry train (not ElevenLabs; never 6000)"
      );
    }
  );
  context.subscriptions.push(disposable);
}

function deactivate() {}

module.exports = { activate, deactivate };
