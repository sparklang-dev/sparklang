#!/usr/bin/env node
/*
 * Node bridge for the JS/Python SPARK_BC parser parity gate.
 *
 * Loads the real website parser (website/js/sparkbc.js — the same
 * file the browser loads on /ide-web.html), parses a .sparkbc file,
 * and prints {dump, analysis} JSON for test_js_parity.py.
 *
 * Usage:
 *   node tools/spark-bc-dump/js_parity.js FILE.sparkbc \
 *     [--source S] [--command C] [--label L]
 */
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..", "..");
const SparkBC = require(path.join(ROOT, "website", "js", "sparkbc.js"));

function main(argv) {
  if (argv.length < 1) {
    process.stderr.write("need FILE.sparkbc\n");
    return 2;
  }
  const sparkbc = argv[0];
  const opts = { source: "", command: "", label: "SPARK_BC dump" };
  for (let i = 1; i < argv.length; i++) {
    if (argv[i] === "--source" && i + 1 < argv.length) {
      opts.source = argv[++i];
    } else if (argv[i] === "--command" && i + 1 < argv.length) {
      opts.command = argv[++i];
    } else if (argv[i] === "--label" && i + 1 < argv.length) {
      opts.label = argv[++i];
    }
  }
  const buf = fs.readFileSync(sparkbc);
  const bytes = new Uint8Array(buf.buffer, buf.byteOffset, buf.length);
  return SparkBC.parseSparkBC(bytes)
    .then((bc) => {
      const dump = SparkBC.formatDump(bc, opts);
      const analysis = SparkBC.analyzeBc(bc);
      process.stdout.write(JSON.stringify({ dump, analysis }));
      return 0;
    })
    .catch((err) => {
      process.stderr.write("parse error: " + err.message + "\n");
      return 1;
    });
}

process.exitCode = 0;
main(process.argv.slice(2)).then((rc) => {
  process.exitCode = rc;
});
