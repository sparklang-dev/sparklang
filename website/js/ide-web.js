/*
 * Spark web IDE — real client-side SPARK_BC decompile/dump/ask.
 *
 * Every pane is computed in-browser from real bytes via
 * /js/sparkbc.js (a port of python/sparklang/model_lab/bc_dump.py).
 * No server, no canned text: the bundled fixture is a real compiled
 * .sparkbc fetched as bytes and parsed live; uploads parse the same
 * way. Byte-parity with bc_dump.py is enforced by
 * tools/spark-bc-dump/test_js_parity.py.
 */
(function () {
  "use strict";

  var FIXTURE_BC = "/docs/examples/spark-train-step.sparkbc";
  var FIXTURE_SRC = "/docs/examples/spark-train-step.spark";
  var FIXTURE_WEIGHTS = "/docs/examples/spark-self.init.safetensors";
  var FIXTURE_COMPILE_CMD =
    "./spark-bootstrap --compile examples/spark_train_step.spark " +
    "-o docs/examples/spark-train-step.sparkbc";

  var els = {
    file: document.getElementById("ide-file"),
    loadFixture: document.getElementById("ide-load-fixture"),
    decompile: document.getElementById("ide-decompile"),
    dump: document.getElementById("ide-dump"),
    weights: document.getElementById("ide-weights"),
    report: document.getElementById("ide-report"),
    askForm: document.getElementById("ide-ask-form"),
    askInput: document.getElementById("ide-ask-input"),
    files: document.getElementById("ide-files"),
    opcodes: document.getElementById("ide-opcodes"),
    srcLabel: document.getElementById("ide-src-label"),
    srcPane: document.getElementById("ide-src-pane"),
    dumpLabel: document.getElementById("ide-dump-label"),
    dumpPane: document.getElementById("ide-dump-pane"),
    status: document.getElementById("ide-status"),
  };

  // Live workspace state — only real parsed artifacts land here.
  var state = {
    name: null,
    bc: null, // parsed SPARK_BC object
    analysis: null,
    sourceText: null,
    sourceName: null,
    weights: null, // parsed safetensors header
  };

  function esc(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function setStatus(html) {
    els.status.innerHTML = html;
  }

  function statusReady() {
    var a = state.analysis;
    setStatus(
      "<span><strong>Ready</strong></span>" +
        "<span>· " +
        esc(state.name) +
        "</span>" +
        "<span>· " +
        a.size +
        " bytes</span>" +
        "<span>· sha256 " +
        esc(a.sha256.slice(0, 12)) +
        "…</span>" +
        "<span>· " +
        a.ops.length +
        " ops · " +
        a.nstrings +
        " strings · " +
        a.nconsts +
        " consts</span>"
    );
  }

  function setError(err) {
    setStatus(
      "<span><strong>Parse error</strong></span><span>· " +
        esc(err.message || err) +
        "</span>"
    );
  }

  function showText(text) {
    els.dumpPane.innerHTML =
      '<pre class="ide-shell__code">' + esc(text) + "</pre>";
  }

  function renderFiles() {
    var items = "";
    if (state.name) {
      items +=
        '<li><a href="#dump" aria-current="true">' +
        esc(state.name) +
        "</a></li>";
    }
    if (state.sourceName) {
      items +=
        '<li><a href="#src">' + esc(state.sourceName) + "</a></li>";
    }
    els.files.innerHTML =
      items || "<li><a href='#dump'>(nothing loaded)</a></li>";
  }

  function renderOpcodes() {
    var counts = {};
    if (state.analysis) {
      state.analysis.ops.forEach(function (op) {
        counts[op.name] = (counts[op.name] || 0) + 1;
      });
    }
    var codes = Object.keys(SparkBC.OP_NAME)
      .map(function (k) {
        return parseInt(k, 10);
      })
      .sort(function (a, b) {
        return a - b;
      });
    var html = "";
    codes.forEach(function (code) {
      var name = SparkBC.OP_NAME[code];
      var n = counts[name] || 0;
      html +=
        "<li><button type='button' data-op='" +
        esc(name) +
        "'>" +
        esc(name) +
        " 0x" +
        code.toString(16).padStart(2, "0").toUpperCase() +
        (n ? " ×" + n : "") +
        "</button></li>";
    });
    els.opcodes.innerHTML = html;
  }

  function renderSource() {
    if (state.sourceText != null) {
      els.srcLabel.textContent = ".spark source — " + state.sourceName;
      els.srcPane.textContent = state.sourceText;
    } else {
      els.srcLabel.textContent = ".spark source";
      els.srcPane.textContent =
        "(no source for uploaded bytes — SPARK_BC keeps strings " +
        "and consts, not the original .spark text)";
    }
  }

  // Decompile view: disassembly table computed from parsed ops.
  function renderDecompile() {
    var a = state.analysis;
    var html =
      "<table class='ide-web__ops'><thead><tr>" +
      "<th>ip</th><th>hex</th><th>op</th><th>args</th>" +
      "</tr></thead><tbody>";
    a.ops.forEach(function (op) {
      html +=
        "<tr><td>code+" +
        op.ip +
        "</td><td>" +
        esc(op.hex) +
        "</td><td>" +
        esc(op.name) +
        " (0x" +
        op.op.toString(16).padStart(2, "0") +
        ")</td><td>" +
        esc(op.args_text.join(" ")) +
        "</td></tr>";
    });
    html += "</tbody></table>";
    els.dumpLabel.textContent = "Decompile — " + state.name;
    els.dumpPane.innerHTML = html;
  }

  function renderDump() {
    els.dumpLabel.textContent = "SPARK_BC dump — " + state.name;
    showText(
      SparkBC.formatDump(state.bc, {
        source: state.sourceName || state.name,
        command: state.bcCommand || "(uploaded bytes)",
        label: "ide-web " + state.name,
      })
    );
  }

  function renderWeights() {
    var w = state.weights;
    if (!w) {
      showText("Weights not loaded yet.");
      return;
    }
    var html =
      "<p>Parsed <code>" +
      esc(FIXTURE_WEIGHTS) +
      "</code> in-browser — safetensors header (" +
      w.header_bytes +
      " bytes JSON, file " +
      w.size +
      " bytes).</p>";
    var metaKeys = Object.keys(w.metadata);
    if (metaKeys.length) {
      html += "<p><strong>metadata</strong></p><ul>";
      metaKeys.sort().forEach(function (k) {
        html += "<li>" + esc(k) + ": " + esc(w.metadata[k]) + "</li>";
      });
      html += "</ul>";
    }
    html +=
      "<table class='ide-web__ops'><thead><tr>" +
      "<th>tensor</th><th>dtype</th><th>shape</th>" +
      "</tr></thead><tbody>";
    w.tensors.forEach(function (t) {
      html +=
        "<tr><td>" +
        esc(t.name) +
        "</td><td>" +
        esc(t.dtype) +
        "</td><td>[" +
        esc(t.shape.join(", ")) +
        "]</td></tr>";
    });
    html += "</tbody></table>";
    els.dumpLabel.textContent = "Weights — safetensors header";
    els.dumpPane.innerHTML = html;
  }

  // Factual ask over the live parse — mirrors spark_bc_gui's
  // factual_ask; every answer is computed from parsed bytes.
  function factualAsk(question) {
    var a = state.analysis;
    var q = question.toLowerCase().trim();
    var names = a.ops.map(function (o) {
      return o.name;
    });
    if (
      q.indexOf("how many op") !== -1 ||
      q.indexOf("opcode count") !== -1 ||
      q.indexOf("ops count") !== -1
    ) {
      return (
        "This SPARK_BC has " +
        names.length +
        " opcodes: " +
        names.join(", ") +
        "."
      );
    }
    if (
      q.indexOf("what op") !== -1 ||
      q.indexOf("list op") !== -1 ||
      q.indexOf("opcodes") !== -1 ||
      q.indexOf("mnemonics") !== -1
    ) {
      return (
        "Opcodes in this dump: " +
        names.join(", ") +
        ". SPARK_BC is orchestration bytecode, not ELF/PE."
      );
    }
    if (q.indexOf("sha") !== -1 || q.indexOf("hash") !== -1) {
      return "Dump sha256 is " + a.sha256 + ".";
    }
    if (q.indexOf("section") !== -1) {
      return (
        "Sections: " +
        a.sections
          .map(function (s) {
            return s.name + " (off=" + s.off + ", size=" + s.size + ")";
          })
          .join("; ") +
        "."
      );
    }
    if (q.indexOf("symbol") !== -1 || q.indexOf("string") !== -1) {
      return (
        "String-pool symbols (" +
        a.symbols.length +
        "): " +
        a.symbols
          .map(function (s) {
            return s.id + " " + SparkBC.pyRepr(s.text);
          })
          .join(", ") +
        "."
      );
    }
    if (
      q.indexOf("magic") !== -1 ||
      q.indexOf("spbc") !== -1 ||
      q.indexOf("what is this") !== -1
    ) {
      return (
        "This is a SPARK_BC dump (magic SPBC, version " +
        a.version +
        ") — Spark orchestration bytecode. Not neural weights " +
        "and not an ELF/PE binary."
      );
    }
    if (q.indexOf("train") !== -1) {
      return (
        "TRAIN opcode is " +
        (names.indexOf("TRAIN") !== -1 ? "present" : "absent") +
        " in this dump."
      );
    }
    return (
      "I answer dump facts computed from the parsed bytes — try " +
      "'list opcodes', 'sha256', 'sections', 'symbols', or 'magic'."
    );
  }

  function renderAsk(question) {
    var answer = factualAsk(question);
    els.dumpLabel.textContent = "Ask — " + state.name;
    showText("Q: " + question + "\n\nA: " + answer + "\n");
  }

  function downloadReport() {
    var a = state.analysis;
    var now = new Date().toISOString();
    var lines = [
      "# Spark IDE analysis",
      "",
      "- Generated: " + now,
      "- Source: `" + (state.sourceName || "(uploaded bytes)") + "`",
      "- SPARK_BC: `" + state.name + "`",
      "- sha256: `" + a.sha256 + "`",
      "- opcode count: " + a.ops.length,
      "",
      "## Opcodes",
      "",
    ];
    a.ops.forEach(function (op, i) {
      lines.push(i + ". `" + op.name + "`");
    });
    lines.push("");
    lines.push("## Dump");
    lines.push("");
    lines.push("```");
    lines.push(
      SparkBC.formatDump(state.bc, {
        source: state.sourceName || state.name,
        command: state.bcCommand || "(uploaded bytes)",
        label: "ide-web report",
      })
    );
    lines.push("```");
    lines.push("");
    var blob = new Blob([lines.join("\n")], {
      type: "text/markdown",
    });
    var url = URL.createObjectURL(blob);
    var link = document.createElement("a");
    link.href = url;
    link.download = state.name.replace(/\.sparkbc$/, "") + "-report.md";
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  }

  function afterParse() {
    state.analysis = SparkBC.analyzeBc(state.bc);
    renderFiles();
    renderOpcodes();
    renderSource();
    renderDump();
    statusReady();
  }

  function loadBytes(name, bytes, sourceText, sourceName, command) {
    return SparkBC.parseSparkBC(bytes)
      .then(function (bc) {
        state.name = name;
        state.bc = bc;
        state.bcCommand = command;
        state.sourceText = sourceText;
        state.sourceName = sourceName;
        afterParse();
      })
      .catch(setError);
  }

  function loadFixture() {
    setStatus("<span><strong>Loading bundled fixture…</strong></span>");
    els.dumpLabel.textContent = "SPARK_BC dump";
    return Promise.all([
      fetch(FIXTURE_BC).then(function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.arrayBuffer();
      }),
      fetch(FIXTURE_SRC).then(function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.text();
      }),
    ]).then(function (parts) {
      return loadBytes(
        "docs/examples/spark-train-step.sparkbc",
        new Uint8Array(parts[0]),
        parts[1],
        "examples/spark_train_step.spark",
        FIXTURE_COMPILE_CMD
      );
    }, setError);
  }

  function loadWeights() {
    return fetch(FIXTURE_WEIGHTS)
      .then(function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.arrayBuffer();
      })
      .then(function (buf) {
        state.weights = SparkBC.parseSafetensors(new Uint8Array(buf));
        renderWeights();
      })
      .catch(setError);
  }

  function onUpload() {
    var file = els.file.files && els.file.files[0];
    if (!file) return;
    file
      .arrayBuffer()
      .then(function (buf) {
        return loadBytes(file.name, new Uint8Array(buf), null, null);
      })
      .catch(setError);
    els.file.value = "";
  }

  function wire() {
    els.file.addEventListener("change", onUpload);
    els.loadFixture.addEventListener("click", loadFixture);
    els.decompile.addEventListener("click", function () {
      if (state.analysis) renderDecompile();
    });
    els.dump.addEventListener("click", function () {
      if (state.analysis) renderDump();
    });
    els.weights.addEventListener("click", loadWeights);
    els.report.addEventListener("click", function () {
      if (state.analysis) downloadReport();
    });
    els.askForm.addEventListener("submit", function (ev) {
      ev.preventDefault();
      if (!state.analysis) return;
      var q = els.askInput.value.trim();
      if (q) renderAsk(q);
    });
    document
      .querySelectorAll(".ide-shell__tools [data-action]")
      .forEach(function (btn) {
        btn.addEventListener("click", function () {
          var action = btn.getAttribute("data-action");
          if (action === "decompile" && state.analysis) {
            renderDecompile();
          } else if (action === "dump" && state.analysis) {
            renderDump();
          } else if (action === "weights") {
            loadWeights();
          } else if (action === "report" && state.analysis) {
            downloadReport();
          }
        });
      });
  }

  wire();
  loadFixture();
})();
