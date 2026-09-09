/**
 * Render measured decompile scoreboard from JSON.
 * No invented green checks — data from make decompile-bench only.
 */
(function () {
  const mount = document.getElementById("decompile-scoreboard-body");
  if (!mount) return;

  function esc(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function badge(v) {
    const cls =
      v === "win"
        ? "win"
        : v === "tie"
          ? "tie"
          : v === "loss"
            ? "loss"
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
    const st = document.createElement("style");
    st.id = "decompile-score-style";
    st.textContent =
      ".score-badge{display:inline-block;padding:.1rem .45rem;" +
      "border-radius:4px;font:600 12px/1.3 ui-sans-serif,system-ui;" +
      "text-transform:uppercase;letter-spacing:.03em}" +
      ".score-badge--win{background:#143d2a;color:#7dffa8}" +
      ".score-badge--tie{background:#3d3514;color:#ffe27d}" +
      ".score-badge--loss{background:#3d1414;color:#ff9b9b}" +
      ".score-badge--na{background:#2a3038;color:#9aa3ad}";
    document.head.appendChild(st);
  }

  fetch("/data/decompile-scoreboard.json")
    .then(function (res) {
      if (!res.ok) throw new Error("HTTP " + res.status);
      return res.json();
    })
    .then(function (data) {
      const rt = data.roundtrip || {};
      const summary = data.summary_counts || {};
      const spark = summary.spark || {};
      let html = "";
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
        "</p>";
      html +=
        '<div class="doc__table-wrap"><table class="doc__table"><thead><tr>' +
        "<th>Category</th><th>Spark</th><th>OpenBin</th>" +
        "<th>Ghidra</th><th>IDA</th><th>Binja</th>" +
        "<th>LLM4Decompile</th><th>Note</th>" +
        "</tr></thead><tbody>";
      (data.parity || []).forEach(function (row) {
        html +=
          "<tr><td>" +
          esc(row.category) +
          "</td><td>" +
          badge(row.spark) +
          "</td><td>" +
          badge(row.openbin) +
          "</td><td>" +
          badge(row.ghidra) +
          "</td><td>" +
          badge(row.ida) +
          "</td><td>" +
          badge(row.binja) +
          "</td><td>" +
          badge(row.llm4decompile) +
          "</td><td>" +
          esc(row.note || "") +
          "</td></tr>";
      });
      html += "</tbody></table></div>";
      html +=
        "<p><em>" +
        esc(data.honesty || "") +
        "</em></p>";
      const ext = data.external_tools || [];
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
