"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

class SparkBinNotFound extends Error {
  constructor(message) {
    super(message);
    this.name = "SparkBinNotFound";
  }
}

function isExec(p) {
  try {
    fs.accessSync(p, fs.constants.X_OK);
    return fs.statSync(p).isFile();
  } catch (_e) {
    return false;
  }
}

function findSpark(explicit) {
  const candidates = [];
  if (explicit) candidates.push(explicit);
  if (process.env.SPARK_BIN) candidates.push(process.env.SPARK_BIN);
  candidates.push(path.join(process.cwd(), "spark"));
  let dir = __dirname;
  for (let i = 0; i < 8; i++) {
    candidates.push(path.join(dir, "spark"));
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  const pathEnv = process.env.PATH || "";
  for (const part of pathEnv.split(path.delimiter)) {
    if (part) candidates.push(path.join(part, "spark"));
  }
  const seen = new Set();
  for (const cand of candidates) {
    const resolved = path.resolve(cand);
    if (seen.has(resolved)) continue;
    seen.add(resolved);
    if (isExec(resolved)) return resolved;
  }
  throw new SparkBinNotFound(
    "spark binary not found — build with `make`, set SPARK_BIN, " +
      "or run from the repo root"
  );
}

function looksLikePath(text) {
  if (text.includes("\n") || text.includes("\r")) return false;
  if (text.endsWith(".spark")) return true;
  try {
    return fs.existsSync(text);
  } catch (_e) {
    return false;
  }
}

function run(program, opts) {
  const options = opts || {};
  const live = Boolean(options.live);
  let dry = options.dry === undefined ? !live : Boolean(options.dry);
  if (live)
    dry = false;
  if (!live && !dry) {
    throw new Error(
      "run() needs dry=true (default) or live=true; " +
        "open exec without a mode is not supported"
    );
  }
  const mode = live ? "live" : "dry-run";
  const flag = live ? "--live" : "--dry-run";
  const binary = findSpark(options.sparkBin);
  const cwd = options.cwd || process.cwd();
  const timeout = options.timeout === undefined ? 120000 : options.timeout;

  let progPath = String(program);
  let tmpPath = null;
  try {
    if (looksLikePath(progPath)) {
      if (!fs.existsSync(progPath) || !fs.statSync(progPath).isFile()) {
        throw new Error("spark program not found: " + progPath);
      }
      progPath = path.resolve(progPath);
    } else {
      tmpPath = path.join(
        os.tmpdir(),
        "sparklang-embed-" + process.pid + "-" + Date.now() + ".spark"
      );
      fs.writeFileSync(tmpPath, progPath, "utf8");
      progPath = tmpPath;
    }
    const proc = spawnSync(binary, [flag, progPath], {
      encoding: "utf8",
      timeout,
      cwd,
    });
    if (proc.error) throw proc.error;
    return {
      returncode: proc.status === null ? 1 : proc.status,
      stdout: proc.stdout || "",
      stderr: proc.stderr || "",
      mode,
      path: tmpPath ? null : progPath,
      get ok() {
        return this.returncode === 0;
      },
    };
  } finally {
    if (tmpPath) {
      try {
        fs.unlinkSync(tmpPath);
      } catch (_e) {
        /* ignore */
      }
    }
  }
}

module.exports = { run, findSpark, SparkBinNotFound };
