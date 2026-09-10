/**
 * Render measured decompile scoreboard from JSON.
 * Every badge is computed by tools/spark-bc-dump/decompile_bench.py
 * from measured probe output. Tools without a byte-level probe on
 * the bench box render "not probed" — never a declared win/tie/loss.
 */
(function () {
  "use strict";
  var mount = document.getElementById("decompile-scoreboard-body");
  if (!mount) return;

  var TOOLS = [
    ["spark", "Spark"],
    ["objdump", "objdump"],
    ["openbin", "OpenBin"],
    ["ghidra", "Ghidra"],
    ["ida", "IDA"],
    ["binja", "Binja"],
    ["llm4decompile", "LLM4Decompile"],
  ];

  function esc(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function badge(v) {
    var cls =
      v === "win"
        ? "win"
        : v === "tie"
          ? "tie"
          : v === "loss"
            ? "loss"
            : v === "not probed"
              ? "notprobed"
              : "na";
    return (
      '<span class="score-badge score-badge--' +
      cls +
      '">' +
      esc(v) +
      "</span>"
    );
  }

  if (!document.getElementById("decompile-score-style")) {
    var st = document.createElement("style");
    st.id = "decompile-score-style";
    st.textContent =
      ".score-badge{display:inline-block;padding:.1rem .45rem;" +
      "border-radius:4px;font:600 12px/1.3 ui-sans-serif,system-ui;" +
      "text-transform:uppercase;letter-spacing:.03em}" +
      ".score-badge--win{background:#143d2a;color:#7dffa8}" +
      ".score-badge--tie{background:#3d3514;color:#ffe27d}" +
      ".score-badge--loss{background:#3d1414;color:#ff9b9b}" +
      ".score-badge--na{background:#2a3038;color:#9aa3ad}" +
      ".score-badge--notprobed{background:transparent;" +
      "border:1px dashed #4a545f;color:#9aa3ad;" +
      "text-transform:none}";
    document.head.appendChild(st);
  }

  fetch("/data/decompile-scoreboard.json")
    .then(function (res) {
      if (!res.ok) throw new Error("HTTP " + res.status);
      return res.json();
    })
    .then(function (data) {
      var rt = data.roundtrip || {};
      var summary = data.summary_counts || {};
      var spark = summary.spark || {};
      var html = "";
      html +=
        "<p><strong>generated</strong> " +
        esc(data.generated_at || "?") +
        " · domain <code>" +
        esc(data.domain || "") +
        "</code> · round-trip <strong>" +
        esc(String(rt.round_trip_pct)) +
        "%</strong> (" +
        esc(String(rt.n_pass)) +
        "/" +
        esc(String(rt.n_total)) +
        ")</p>";
      html +=
        "<p>Spark counts — win " +
        esc(String(spark.win || 0)) +
        ", tie " +
        esc(String(spark.tie || 0)) +
        ", loss " +
        esc(String(spark.loss || 0)) +
        ", na " +
        esc(String(spark.na || 0)) +
        ", not probed " +
        esc(String(spark["not probed"] || 0)) +
        "</p>";
      html +=
        '<div class="doc__table-wrap"><table class="doc__table">' +
        "<thead><tr><th>Category</th>";
      TOOLS.forEach(function (t) {
        html += "<th>" + esc(t[1]) + "</th>";
      });
      html += "<th>Note</th></tr></thead><tbody>";
      (data.parity || []).forEach(function (row) {
        html += "<tr><td>" + esc(row.category) + "</td>";
        TOOLS.forEach(function (t) {
          html += "<td>" + badge(row[t[0]]) + "</td>";
        });
        html += "<td>" + esc(row.note || "") + "</td></tr>";
      });
      html += "</tbody></table></div>";
      html +=
        "<p><em>" +
        esc(data.honesty || "") +
        "</em></p>";
      var ext = data.external_tools || [];
      if (ext.length) {
        html += "<p><strong>External probes</strong></p><ul>";
        ext.forEach(function (t) {
          html +=
            "<li>" +
            esc(t.tool) +
            ": " +
            esc(t.status) +
            " / " +
            esc(t.verdict) +
            " — " +
            esc(t.note || "") +
            "</li>";
        });
        html += "</ul>";
      }
      mount.innerHTML = html;
    })
    .catch(function (err) {
      mount.innerHTML =
        "<p>Scoreboard JSON unavailable (" +
        esc(err.message || err) +
        "). Run <code>make decompile-bench</code>.</p>";
    });
})();
