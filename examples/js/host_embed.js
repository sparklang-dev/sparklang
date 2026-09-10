#!/usr/bin/env node
"use strict";

const path = require("path");

const ROOT = path.resolve(__dirname, "../..");
const { run } = require(path.join(ROOT, "js/sparklang"));

function main() {
 const target = path.join(ROOT, "examples", "hello.spark");
 const result = run(target, { cwd: ROOT });
 process.stdout.write(result.stdout);
 if (result.stderr) process.stderr.write(result.stderr);
 process.exit(result.returncode);
}

main();
