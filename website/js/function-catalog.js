(function () {
  "use strict";

  var catalog = null;
  var filtered = [];

  function qs(sel, root) {
    return (root || document).querySelector(sel);
  }

  function esc(s) {
    var d = document.createElement("div");
    d.textContent = s || "";
    return d.innerHTML;
  }

  function publicMode(mode) {
    if (mode === "bootstrap-only" || mode === "gas-only") {
      return "dry-run";
    }
    return mode || "dry-run";
  }

  function modeBadge(mode) {
    var pub = publicMode(mode);
    var cls = "fc-mode fc-mode--" + pub.replace(/\W+/g, "-");
    return '<span class="' + cls + '">' + esc(pub) + "</span>";
  }

  function renderRows(entries) {
    var tbody = qs("#fc-tbody");
    var countEl = qs("#fc-count");
    if (!tbody) return;
    if (!entries.length) {
      tbody.innerHTML =
        '<tr><td colspan="6" class="fc-empty">' +
        "No functions match your filters." +
        "</td></tr>";
      if (countEl) countEl.textContent = "0 shown";
      return;
    }
    tbody.innerHTML = entries
      .map(function (e) {
        var ex = e.example
          ? '<a href="/docs/programming-guide.html#' +
            esc(e.example.replace(/\//g, "-")) +
            '">' +
            esc(e.example) +
            "</a>"
          : "—";
        var src = e.libFile
          ? '<code class="inline-code">' + esc(e.libFile) + "</code>"
          : esc(e.source || "language");
        return (
          "<tr>" +
          "<td><span class=\"fc-cat\">" +
          esc(e.category) +
          "</span></td>" +
          "<td><strong>" +
          esc(e.name) +
          "</strong></td>" +
          "<td>" +
          esc(e.description) +
          "</td>" +
          "<td>" +
          modeBadge(e.mode) +
          " " +
          src +
          "</td>" +
          '<td><pre class="fc-syntax">' +
          esc(e.syntax) +
          "</pre></td>" +
          "<td>" +
          ex +
          "</td>" +
          "</tr>"
        );
      })
      .join("");
    if (countEl) {
      countEl.textContent =
        entries.length +
        " of " +
        (catalog ? catalog.totalEntries : entries.length);
    }
  }

  function applyFilters() {
    if (!catalog) return;
    var q =
      ((qs("#fc-search") && qs("#fc-search").value) || "").toLowerCase();
    var cat = qs("#fc-category") && qs("#fc-category").value;
    var mode = qs("#fc-mode") && qs("#fc-mode").value;
    var src = qs("#fc-source") && qs("#fc-source").value;
    filtered = catalog.entries.filter(function (e) {
      if (cat && e.category !== cat) return false;
      if (mode && publicMode(e.mode) !== mode) return false;
      if (src && e.source !== src) return false;
      if (!q) return true;
      var hay = (
        e.name +
        " " +
        e.description +
        " " +
        e.syntax +
        " " +
        e.category
      ).toLowerCase();
      return hay.indexOf(q) >= 0;
    });
    renderRows(filtered);
  }

  function fillCategorySelect() {
    var sel = qs("#fc-category");
    if (!sel || !catalog) return;
    catalog.categories.forEach(function (c) {
      var opt = document.createElement("option");
      opt.value = c;
      opt.textContent = c;
      sel.appendChild(opt);
    });
  }

  function fillStats() {
    var el = qs("#fc-stats");
    if (!el || !catalog) return;
    el.innerHTML =
      "<strong>" +
      catalog.helperCount +
      "</strong> stdlib helpers · " +
      "<strong>" +
      catalog.totalEntries +
      "</strong> catalog entries · " +
      "<strong>" +
      catalog.categoryCount +
      "</strong> categories";
  }

  function showLoadError(msg) {
    var stats = qs("#fc-stats");
    if (stats) stats.textContent = msg;
    var tbody = qs("#fc-tbody");
    if (tbody) {
      tbody.innerHTML =
        '<tr><td colspan="6">' +
        "Could not load catalog. Run " +
        "<code>python3 tools/gen_function_catalog.py</code> " +
        "and redeploy." +
        "</td></tr>";
    }
  }

  function bindEvents() {
    ["fc-search", "fc-category", "fc-mode", "fc-source"].forEach(
      function (id) {
        var el = qs("#" + id);
        if (el) el.addEventListener("input", applyFilters);
        if (el && el.tagName === "SELECT") {
          el.addEventListener("change", applyFilters);
        }
      }
    );
    var clear = qs("#fc-clear");
    if (clear) {
      clear.addEventListener("click", function () {
        if (qs("#fc-search")) qs("#fc-search").value = "";
        if (qs("#fc-category")) qs("#fc-category").value = "";
        if (qs("#fc-mode")) qs("#fc-mode").value = "";
        if (qs("#fc-source")) qs("#fc-source").value = "";
        applyFilters();
      });
    }
  }

  function init() {
    if (!qs(".function-catalog")) return;
    fetch("/data/function-catalog.json")
      .then(function (r) {
        if (!r.ok) throw new Error("catalog load failed");
        return r.json();
      })
      .then(function (data) {
        if (!data || !Array.isArray(data.entries)) {
          throw new Error("catalog shape invalid");
        }
        catalog = data;
        filtered = data.entries.slice();
        fillCategorySelect();
        fillStats();
        bindEvents();
        renderRows(filtered);
      })
      .catch(function () {
        showLoadError("Catalog failed to load.");
      });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
