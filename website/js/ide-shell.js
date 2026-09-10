/* Spark IDE shell demo — client-only browse/ask/sync highlight. */
(function () {
 "use strict";

 var statusEl = document.getElementById("ide-status");
 var askOut = document.getElementById("ask-out");
 var dumpPane = document.getElementById("dump-pane");
 var srcPane = document.getElementById("src-pane");

 function setStatus(msg) {
 if (statusEl) statusEl.textContent = msg;
 }

 function clearSync(node) {
 if (!node) return;
 node.innerHTML = node.textContent
 .split("\n")
 .map(function (line) {
 return line
 .replace(/&/g, "&amp;")
 .replace(/</g, "&lt;")
 .replace(/>/g, "&gt;");
 })
 .join("\n");
 }

 function highlightNeedle(node, needle) {
 if (!node || !needle) return;
 var lines = node.textContent.split("\n");
 node.innerHTML = lines
 .map(function (line) {
 var esc = line
 .replace(/&/g, "&amp;")
 .replace(/</g, "&lt;")
 .replace(/>/g, "&gt;");
 if (line.indexOf(needle) !== -1) {
 return '<span class="sync">' + esc + "</span>";
 }
 return esc;
 })
 .join("\n");
 }

 function factualAsk(q) {
 var lower = (q || "").toLowerCase();
 if (
 lower.indexOf("opcode") !== -1 ||
 lower.indexOf("list op") !== -1
 ) {
 return (
 "[factual]\nOpcodes in this demo dump: LOAD, ASK, PRINT, HALT.\n" +
 "Honest note: desktop IDE uses real dump SoT. Measurement only — not a marketing win."
 );
 }
 if (lower.indexOf("sha") !== -1 || lower.indexOf("hash") !== -1) {
 return (
 "[factual]\nLive sha256 comes from desktop compile/decompile.\n" +
 "This page is a layout demo only."
 );
 }
 return (
 "[fallback]\nOpen-ended Ask needs the desktop GUI + dump context.\n" +
 "Honest note: not OpenBin-level RE Q&A. Measurement only — not a marketing win."
 );
 }

 document.querySelectorAll(".ide-tabs button").forEach(function (btn) {
 btn.addEventListener("click", function () {
 document.querySelectorAll(".ide-tabs button").forEach(function (b) {
 b.classList.remove("is-active");
 });
 btn.classList.add("is-active");
 var tab = btn.getAttribute("data-tab");
 document.getElementById("browse-files").hidden = tab !== "files";
 document.getElementById("browse-ops").hidden = tab !== "ops";
 document.getElementById("browse-weights").hidden = tab !== "weights";
 setStatus("Browse · " + tab);
 });
 });

 document.querySelectorAll("#browse-ops li").forEach(function (li) {
 li.addEventListener("click", function () {
 document.querySelectorAll("#browse-ops li").forEach(function (x) {
 x.classList.remove("is-active");
 });
 li.classList.add("is-active");
 var ip = li.getAttribute("data-ip") || "0";
 var needle = "code+" + ip;
 clearSync(srcPane);
 highlightNeedle(dumpPane, needle);
 if (ip === "3") {
 highlightNeedle(srcPane, "ask");
 }
 setStatus("Jump " + needle + " (demo sync highlight)");
 });
 });

 document.querySelectorAll("[data-act]").forEach(function (btn) {
 btn.addEventListener("click", function () {
 var act = btn.getAttribute("data-act");
 if (act === "ask") {
 var q = (document.getElementById("ask-q") || {}).value || "";
 if (askOut) askOut.textContent = factualAsk(q.trim() || "list opcodes");
 setStatus("Ask (demo factual) — real Ask is in spark-bc-gui");
 return;
 }
 if (act === "compile" || act === "decompile") {
 setStatus(
 act +
 ": run `make spark-bc-gui` or `./bin/spark-bc-gui` for real tools"
 );
 return;
 }
 if (act === "report") {
 setStatus(
 "Report: desktop IDE exports markdown from dump + ask notes"
 );
 }
 });
 });
})();
