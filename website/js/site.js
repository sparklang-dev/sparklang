(function () {
  "use strict";

  var DRY_RUN_OUTPUTS = {
    hello: {
      cmd: "./spark --dry-run hello.spark",
      out:
        '{"op":"ask","mode":"dry-run","model":"code",' +
        '"text":"Gravity is the mutual attraction between masses."}\n' +
        "Gravity is the mutual attraction between masses.",
    },
    sugar: {
      cmd: "./spark --dry-run hello_sugar.spark",
      out:
        '{"op":"ask","mode":"dry-run","model":"code",' +
        '"text":"Gravity pulls masses together."}\n' +
        "Gravity pulls masses together.",
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
      cmd: "./spark --dry-run model_improve.spark",
      out:
        '{"op":"model.analyze","alias":"alias-code",' +
        '"mode":"dry-run","fixture":true}\n' +
        '{"op":"model.improve","prefer":"quality",' +
        '"blueprint":"out/better-model.md"}',
    },
    "model-tune": {
      cmd: "./spark --dry-run tune-model.spark",
      out:
        '{"op":"model.analyze","alias":"fast","mode":"dry-run","fixture":true}\n' +
        '{"op":"model.compare","models":["fast","code","best"],' +
        '"suite":"examples/eval_suite.json","winner":"code","mode":"dry-run"}\n' +
        '{"op":"model.improve","prefer":"quality","mode":"dry-run"}\n' +
        '{"op":"model.build","path":"out/my-model.md","train":false,' +
        '"mode":"dry-run"}\n' +
        "written out/my-model.md (plan + config — review before live training)",
    },
  };

  var MODEL_WORKFLOW_CHAIN =
    'model analyze "{base}" -> report\n\n' +
    'model compare ["fast", "code", "best"]\n' +
    '  on suite "examples/eval_suite.json" -> comparison\n\n' +
    'model improve from report prefer {prefer} -> blueprint\n\n' +
    'model build blueprint into "{out}"';

  var MODEL_TEMPLATES = {
    ask:
      'use fast\n\nask "Explain {topic} in one sentence" {\n  topic: "gravity"\n} -> text\n\nprint text',
    classify:
      'use fast\n\nclassify Intent { support, sales, spam }\n  from "My account is locked and I need help"\n  min_confidence 0.7\n  -> intent\n\nprint intent',
    pipeline:
      'let doc "Your document text here."\n\npipeline {\n  ask "Summarize: {doc}" -> summary\n  | ask "Translate to Spanish: {summary}" -> es\n}\n\nprint es',
    model: MODEL_WORKFLOW_CHAIN,
    voice:
      'use fast\n\nvoice {\n  listen -> user\n  classify Intent { support, sales } from user -> intent\n  ask "Reply helpfully to: {user}" -> reply\n  speak reply -> "out.wav"\n}',
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
      hello:
        'use code\n\nask "Explain gravity in one sentence" -> text\n\nprint text',
      sugar:
        'use code\n\n? "Explain gravity in one sentence" -> text\n\nprint text',
      classify:
        'use fast\n\nclassify Intent { support, sales, spam }\n  from "My account is locked and I need help"\n  min_confidence 0.7\n  -> intent\n\nprint intent',
      pipeline:
        'let doc "Office printers need regular cleaning."\n\npipeline {\n  ask "Summarize: {doc}" -> summary\n  | ask "Translate to Spanish: {summary}" -> es\n}\n\nprint es',
      model:
        'model code\n\nmodel analyze "fast" -> report\n\nmodel compare ["fast", "code", "best"]\n  on suite "examples/eval_suite.json" -> comparison\n\nmodel improve from report prefer quality -> blueprint\n\nmodel build blueprint into "out/my-model.md"',
      "model-tune":
        'model code\n\nmodel analyze "fast" -> report\n\nmodel compare ["fast", "code", "best"]\n  on suite "examples/eval_suite.json" -> comparison\n\nmodel improve from report prefer quality -> blueprint\n\nmodel build blueprint into "out/my-model.md"',
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
    var base = opts.base || "fast";
    var prefer = opts.prefer || "quality";
    var out =
      path === "modify"
        ? "out/improved-" + base + ".md"
        : "out/my-model.md";
    var header =
      path === "modify"
        ? "# spark.toml: model = \"" + base + "\"\nuse " + base + "\n"
        : "model code\n";
    var chain = MODEL_WORKFLOW_CHAIN.replace(/\{base\}/g, base)
      .replace(/\{prefer\}/g, prefer)
      .replace(/\{out\}/g, out);
    return header + "\n" + chain;
  }

  function initModelWizard() {
    var pathSelect = qs("#wizard-path");
    var baseSelect = qs("#wizard-base");
    var preferSelect = qs("#wizard-prefer");
    var taskSelect = qs("#wizard-task");
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
      var base = baseSelect ? baseSelect.value : "fast";
      var prefer = preferSelect ? preferSelect.value : "quality";
      var task = taskSelect ? taskSelect.value : "model";
      var code = buildModelWorkflow({ path: path, base: base, prefer: prefer });
      var fname = path === "modify" ? "improve-" + base + ".spark" : "my-model.spark";

      if (task !== "model") {
        var appCode = MODEL_TEMPLATES[task] || MODEL_TEMPLATES.ask;
        code = appCode + "\n\n# --- model tune ---\n\n" + code;
      }

      snippet.querySelector("code").textContent = code;
      if (filename) filename.textContent = fname;
      if (pathHint) {
        pathHint.textContent =
          path === "modify"
            ? "Starts from your spark.toml default (model = \"" +
              base +
              "\"). Compares against other aliases, then writes an improved blueprint."
            : "Starts fresh with model code, analyzes the catalog, compares on your eval suite, and writes a new blueprint.";
      }
      if (runCmd) {
        runCmd.textContent =
          "./spark --dry-run " +
          fname +
          "   # offline fixtures, no API key\n" +
          "export AI_GATEWAY_URL=http://127.0.0.1:4000\n" +
          "./spark --live " +
          fname +
          "        # live model API calls";
      }
    }

    [pathSelect, baseSelect, preferSelect, taskSelect].forEach(function (el) {
      if (!el) return;
      el.addEventListener("change", function () {
        update();
        setWizardStep(1);
      });
    });

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
