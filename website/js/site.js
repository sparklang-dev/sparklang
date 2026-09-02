(function () {
  "use strict";

  var DRY_RUN_OUTPUTS = {
    hello: {
      cmd: "./spark --dry-run examples/train_eval.spark",
      out:
        '{"op":"train","job_id":"job-dry-001","status":"accepted","mode":"dry-run"}\n' +
        '{"op":"status","state":"succeeded","mode":"dry-run"}\n' +
        "[expect] pass contains job\n" +
        "[expect] pass contains status\n" +
        "wrote out/train/job-dry-001/ARTIFACT",
    },
    sugar: {
      cmd: "./spark --dry-run examples/train_eval.spark",
      out:
        '{"op":"train","job_id":"job-dry-001","status":"accepted","mode":"dry-run"}\n' +
        "[expect] pass contains job",
    },
    classify: {
      cmd: "./spark --dry-run classify_intent.spark",
      out:
        '{"label":"support","confidence":0.92,' +
        '"reasons":["account","help"]}\n' +
        '{"labels":["support","sales"],"confidence":0.81}',
    },
    pipeline: {
      cmd: "./spark --dry-run pipeline_translate.spark",
      out:
        '{"op":"ask","mode":"dry-run","step":"summary",' +
        '"text":"Machines need cleaning and balance checks."}\n' +
        '{"op":"ask","mode":"dry-run","step":"translate",' +
        '"text":"Las máquinas necesitan limpieza y equilibrio."}',
    },
    model: {
      cmd: "./spark --dry-run examples/train_eval.spark",
      out:
        '{"op":"train","job_id":"job-dry-001","status":"accepted","mode":"dry-run"}\n' +
        '{"op":"status","state":"succeeded","mode":"dry-run"}\n' +
        "[expect] pass contains job\n" +
        "[expect] pass contains status\n" +
        "wrote out/train/job-dry-001/ARTIFACT",
    },
    "model-tune": {
      cmd: "./spark --dry-run examples/train_eval.spark",
      out:
        '{"op":"train","job_id":"job-dry-001","status":"accepted","mode":"dry-run"}\n' +
        '{"op":"status","state":"succeeded","mode":"dry-run"}\n' +
        "[expect] pass contains job\n" +
        "[expect] pass contains status\n" +
        "wrote out/train/job-dry-001/ARTIFACT",
    },
  };

  var MODEL_WORKFLOW_CHAIN =
    'model train dataset "examples/fixtures/train/dataset.jsonl" base "fixture-base" out "out/train/job-dry-001" backend "http" -> job\n\n' +
    'model status "job-dry-001" -> status\n\n' +
    'expect contains job fixture "examples/fixtures/train/want_accepted.txt"\n' +
    'expect contains status fixture "examples/fixtures/train/want_succeeded.txt"';

  var MODEL_TEMPLATES = {
    ask:
      'expect contains job fixture "examples/fixtures/train/want_accepted.txt"\n' +
      'expect contains status fixture "examples/fixtures/train/want_succeeded.txt"',
    classify:
      'classify Intent { support, sales, spam }\n' +
      '  from "My account is locked and I need help"\n' +
      '  min_confidence 0.7\n' +
      '  -> intent\n\nprint intent',
    pipeline:
      'let doc "Your document text here."\n\npipeline {\n  ask "Summarize: {doc}" -> summary\n  | ask "Translate to Spanish: {summary}" -> es\n}\n\nprint es',
    model: MODEL_WORKFLOW_CHAIN,
    voice:
      'voice {\n  listen -> user\n  ask "Reply briefly: {user}" -> reply\n  speak reply -> "out.wav"\n}',
  };

  function qs(sel, root) {
    return (root || document).querySelector(sel);
  }

  function qsa(sel, root) {
    return Array.prototype.slice.call((root || document).querySelectorAll(sel));
  }

  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    var ta = document.createElement("textarea");
    ta.value = text;
    ta.style.position = "fixed";
    ta.style.left = "-9999px";
    document.body.appendChild(ta);
    ta.select();
    document.execCommand("copy");
    document.body.removeChild(ta);
    return Promise.resolve();
  }

  function initNavToggle() {
    var toggle = qs(".nav-toggle");
    var wrap = qs(".header-nav-wrap");
    if (!toggle || !wrap) return;

    function setOpen(open) {
      wrap.classList.toggle("is-open", open);
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
      toggle.setAttribute("aria-label", open ? "Close menu" : "Open menu");
      if (!open) closeMoreMenus();
    }

    toggle.addEventListener("click", function () {
      setOpen(!wrap.classList.contains("is-open"));
    });

    qsa(".site-nav a, .nav-more__menu a").forEach(function (link) {
      link.addEventListener("click", function () {
        setOpen(false);
      });
    });

    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") {
        setOpen(false);
        closeMoreMenus();
      }
    });
  }

  function closeMoreMenus() {
    qsa(".nav-more").forEach(function (item) {
      item.classList.remove("is-open");
      var btn = qs(".nav-more__toggle", item);
      var menu = qs(".nav-more__menu", item);
      if (btn) btn.setAttribute("aria-expanded", "false");
      if (menu) menu.hidden = true;
    });
  }

  function initNavMore() {
    qsa(".nav-more").forEach(function (item) {
      var btn = qs(".nav-more__toggle", item);
      var menu = qs(".nav-more__menu", item);
      if (!btn || !menu) return;

      btn.addEventListener("click", function (e) {
        e.stopPropagation();
        var open = menu.hidden;
        closeMoreMenus();
        menu.hidden = !open;
        btn.setAttribute("aria-expanded", open ? "true" : "false");
        item.classList.toggle("is-open", open);
      });
    });

    document.addEventListener("click", function () {
      closeMoreMenus();
    });

    qsa(".nav-more__menu").forEach(function (menu) {
      menu.addEventListener("click", function (e) {
        e.stopPropagation();
      });
    });
  }

  function initSkipLink() {
    var main = qs("main");
    if (!main) return;
    if (!main.id) main.id = "main-content";
    if (main.tabIndex < 0) main.tabIndex = -1;

    if (qs(".skip-link")) return;
    var skip = document.createElement("a");
    skip.className = "skip-link";
    skip.href = "#" + main.id;
    skip.textContent = "Skip to content";
    document.body.insertBefore(skip, document.body.firstChild);
  }

  function initCopyButtons() {
    qsa("pre.doc__pre, pre.terminal, pre.code-block").forEach(function (pre) {
      if (pre.querySelector(".copy-btn")) return;
      var code = pre.querySelector("code");
      var text = code ? code.textContent : pre.textContent;
      var btn = document.createElement("button");
      btn.type = "button";
      btn.className = "copy-btn";
      btn.textContent = "Copy";
      btn.setAttribute("aria-label", "Copy code");
      btn.addEventListener("click", function () {
        copyText(text).then(function () {
          btn.textContent = "Copied!";
          setTimeout(function () {
            btn.textContent = "Copy";
          }, 1600);
        });
      });
      pre.style.position = "relative";
      pre.appendChild(btn);
    });
  }

  function initDocToc() {
    var article = qs(".doc__body");
    var toc = qs("#doc-toc-list");
    if (!article || !toc) return;
    var headings = qsa("h2[id], h3[id]", article);
    if (!headings.length) return;
    var ul = document.createElement("ul");
    ul.className = "toc-list";
    headings.forEach(function (h) {
      var li = document.createElement("li");
      if (h.tagName === "H3") li.className = "toc-h3";
      var a = document.createElement("a");
      a.href = "#" + h.id;
      a.textContent = h.textContent.replace(/`/g, "");
      li.appendChild(a);
      ul.appendChild(li);
    });
    toc.appendChild(ul);
  }

  function initTrySpark() {
    var textarea = qs("#try-source");
    var output = qs("#try-output");
    var cmdEl = qs("#try-cmd");
    var runBtn = qs("#try-run");
    var exampleSelect = qs("#try-example");
    if (!textarea || !output || !runBtn) return;

    var examples = {
      hello: MODEL_WORKFLOW_CHAIN,
      sugar: MODEL_WORKFLOW_CHAIN,
      classify:
        'classify Intent { support, sales, spam }\n  from "My account is locked and I need help"\n  min_confidence 0.7\n  -> intent\n\nprint intent',
      pipeline:
        'let doc "Office printers need regular cleaning."\n\npipeline {\n  ask "Summarize: {doc}" -> summary\n  | ask "Translate to Spanish: {summary}" -> es\n}\n\nprint es',
      model: MODEL_WORKFLOW_CHAIN,
      "model-tune": MODEL_WORKFLOW_CHAIN,
    };

    function syncExample() {
      var key = exampleSelect ? exampleSelect.value : "hello";
      if (examples[key]) textarea.value = examples[key];
    }

    if (exampleSelect) {
      exampleSelect.addEventListener("change", syncExample);
      syncExample();
    }

    runBtn.addEventListener("click", function () {
      var key = exampleSelect ? exampleSelect.value : "hello";
      var canned = DRY_RUN_OUTPUTS[key] || DRY_RUN_OUTPUTS.hello;
      if (cmdEl) cmdEl.textContent = canned.cmd;
      output.textContent = canned.out;
      output.classList.remove("is-empty");
    });
  }

  function buildModelWorkflow(opts) {
    var path = opts.path || "create";
    if (path === "modify") {
      return (
        "model analyze all -> report\n\n" +
        "model improve from report prefer quality -> blueprint\n\n" +
        'model plan blueprint into "out/better-model.md"'
      );
    }
    return (
      'model train dataset "examples/fixtures/train/dataset.jsonl" base "fixture-base" out "out/train/job-dry-001" backend "http" -> job\n\n' +
      'model status "job-dry-001" -> status\n\n' +
      'expect contains job fixture "examples/fixtures/train/want_accepted.txt"\n' +
      'expect contains status fixture "examples/fixtures/train/want_succeeded.txt"'
    );
  }

  function initModelWizard() {
    var pathSelect = qs("#wizard-path");
    var snippet = qs("#wizard-snippet");
    var runCmd = qs("#wizard-run-cmd");
    var filename = qs("#wizard-filename");
    var pathHint = qs("#wizard-path-hint");
    var steps = qsa(".wizard-steps li");
    if (!snippet) return;

    function setWizardStep(activeIndex) {
      steps.forEach(function (step, i) {
        step.classList.remove("is-active", "is-done");
        if (i < activeIndex) step.classList.add("is-done");
        if (i === activeIndex) step.classList.add("is-active");
      });
    }

    function update() {
      var path = pathSelect ? pathSelect.value : "create";
      var code = buildModelWorkflow({ path: path });
      var fname =
        path === "modify" ? "model_improve.spark" : "model_train.spark";

      snippet.querySelector("code").textContent = code;
      if (filename) filename.textContent = fname;
      if (pathHint) {
        pathHint.textContent =
          path === "modify"
            ? "Eval helpers plus optional model plan markdown under out/."
            : "Dry-run train job — fixtures only; no GPU and no network.";
      }
      if (runCmd) {
        runCmd.textContent =
          "./spark --dry-run " +
          fname +
          "\n" +
          "# Live train (HTTP backend):\n" +
          "# export SPARK_TRAIN_BACKEND=http\n" +
          "# export SPARK_TRAIN_URL=https://train.example/v1\n" +
          "# ./spark --live " +
          fname;
      }
    }

    if (pathSelect) {
      pathSelect.addEventListener("change", function () {
        update();
        setWizardStep(1);
      });
    }

    var copyPre = snippet.closest("pre");
    if (copyPre) {
      copyPre.addEventListener("click", function (e) {
        if (e.target.closest(".copy-btn")) setWizardStep(2);
      });
    }

    update();
    setWizardStep(0);
  }

  function markActiveNav() {
    var path = window.location.pathname.replace(/\/$/, "") || "/";

    qsa(".site-nav a, .nav-more__menu a").forEach(function (a) {
      a.removeAttribute("aria-current");
    });

    qsa(".site-nav a, .nav-more__menu a").forEach(function (a) {
      var href = (a.getAttribute("href") || "").replace(/\/$/, "") || "/";
      if (path === href) {
        a.setAttribute("aria-current", "page");
      }
    });

    if (path.indexOf("/learn") === 0) {
      var learn = qs('.nav-primary a[href="/learn/"], .nav-primary a[href="/learn"]');
      if (learn) learn.setAttribute("aria-current", "page");
    }

    if (path.indexOf("/docs") === 0) {
      var docs = qs('.nav-primary a[href="/docs/language.html"]');
      if (docs && !qs('.nav-more__menu a[aria-current="page"]')) {
        docs.setAttribute("aria-current", "page");
      }
    }

    if (path.indexOf("/playground") === 0 || path.indexOf("/try") === 0) {
      var pg = qs('.nav-cta[href="/playground.html"]');
      if (pg) pg.setAttribute("aria-current", "page");
    }
  }

  document.addEventListener("DOMContentLoaded", function () {
    initSkipLink();
    initNavToggle();
    initNavMore();
    initCopyButtons();
    initDocToc();
    initTrySpark();
    initModelWizard();
    markActiveNav();
  });
})();
