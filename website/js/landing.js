/* SparkLang landing — terminal replay + scroll reveals.
 *
 * The hero terminal's static HTML is the source of truth: every byte
 * shown is real captured toolchain output embedded in index.html.
 * No-JS and prefers-reduced-motion both keep the full static transcript.
 */
(function () {
  "use strict";

  function qs(sel, root) {
    return (root || document).querySelector(sel);
  }

  function qsa(sel, root) {
    return Array.prototype.slice.call((root || document).querySelectorAll(sel));
  }

  function prefersReducedMotion() {
    try {
      return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    } catch (e) {
      return false;
    }
  }

  /* ——— Scroll reveal ——— */
  function initReveals() {
    if (prefersReducedMotion()) return;
    if (!("IntersectionObserver" in window)) {
      qsa("[data-reveal]").forEach(function (el) {
        el.classList.add("is-in");
      });
      return;
    }
    var io = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-in");
            io.unobserve(entry.target);
          }
        });
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.08 }
    );
    qsa("[data-reveal]").forEach(function (el) {
      io.observe(el);
    });
  }

  /* ——— Hero terminal typed replay ——— */
  var TYPE_MS = 16;
  var OUT_MS = 26;
  var BLOCK_PAUSE_MS = 620;
  var END_PAUSE_MS = 4600;

  function initTerminal() {
    var code = qs("#hero-term-code");
    if (!code || prefersReducedMotion()) return;

    var lines = qsa(".tl", code).map(function (el) {
      return {
        cmd: el.classList.contains("tl-cmd"),
        text: el.textContent,
        html: el.innerHTML,
      };
    });
    if (!lines.length) return;

    var cursor = document.createElement("span");
    cursor.className = "t-cursor";
    cursor.setAttribute("aria-hidden", "true");

    var cancelled = false;
    var timers = [];

    function later(fn, ms) {
      var id = setTimeout(function () {
        if (!cancelled) fn();
      }, ms);
      timers.push(id);
    }

    function newLine() {
      code.appendChild(document.createTextNode("\n"));
    }

    function appendOutput(line, done) {
      var span = document.createElement("span");
      span.className = "tl";
      span.innerHTML = line.html;
      code.insertBefore(span, cursor);
      newLine();
      later(done, OUT_MS);
    }

    function typeCommand(line, done) {
      var span = document.createElement("span");
      span.className = "tl tl-cmd";
      var prompt = document.createElement("span");
      prompt.className = "t-prompt";
      prompt.textContent = "$";
      var cmdText = document.createElement("span");
      cmdText.className = "t-cmd";
      span.appendChild(prompt);
      span.appendChild(document.createTextNode(" "));
      span.appendChild(cmdText);
      code.insertBefore(span, cursor);

      var raw = line.text.replace(/^\$\s*/, "");
      var i = 0;
      function tick() {
        if (i < raw.length) {
          cmdText.textContent += raw.charAt(i);
          i += 1;
          later(tick, TYPE_MS);
        } else {
          newLine();
          later(done, BLOCK_PAUSE_MS);
        }
      }
      tick();
    }

    function run(idx) {
      if (idx >= lines.length) {
        later(function () {
          code.textContent = "";
          code.appendChild(cursor);
          run(0);
        }, END_PAUSE_MS);
        return;
      }
      var line = lines[idx];
      var next = function () {
        run(idx + 1);
      };
      if (line.cmd) typeCommand(line, next);
      else appendOutput(line, next);
    }

    code.textContent = "";
    code.appendChild(cursor);
    run(0);

    document.addEventListener("visibilitychange", function () {
      if (document.hidden) {
        cancelled = true;
        timers.forEach(clearTimeout);
      } else if (cancelled) {
        cancelled = false;
        code.textContent = "";
        code.appendChild(cursor);
        run(0);
      }
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    initReveals();
    initTerminal();
  });
})();
