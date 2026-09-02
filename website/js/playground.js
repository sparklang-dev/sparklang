(function () {
  "use strict";

  var BASE_PRESETS = {
    hello: {
      label: "Train → eval (dry)",
      source:
        'model train dataset "examples/fixtures/train/dataset.jsonl" base "fixture-base" out "out/train/job-dry-001" backend "http" -> job\n\n' +
        'model status "job-dry-001" -> status\n\n' +
        'model compare ["fast", "code", "best"] on suite "examples/eval_suite.json" -> comparison\n\n' +
        "print comparison",
    },
    classify: {
      label: "Classify intent",
      source:
        'classify Intent { support, sales, spam }\n' +
        '  from "My account is locked and I need help"\n' +
        "  min_confidence 0.7\n" +
        "  -> intent\n\nprint intent",
    },
    extract: {
      label: "Extract person",
      source:
        "extract Person {\n" +
        "  name: string\n" +
        "  age: int\n" +
        "  email?: string\n" +
        '} from "Ada Lovelace was born in 1815"\n' +
        '  fixture "examples/fixtures/extract/person.json" -> person\n' +
        "\nprint person",
    },
    pipeline: {
      label: "Pipeline translate",
      source:
        'let doc "Office printers need regular cleaning."\n\n' +
        "pipeline {\n" +
        '  ask "Summarize: {doc}" -> summary\n' +
        '  | ask "Translate to Spanish: {summary}" -> es\n' +
        "}\n\nprint es",
    },
    train: {
      label: "Model train (dry)",
      source:
        'model train dataset "examples/fixtures/train/dataset.jsonl" base "fixture-base" out "out/train/job-dry-001" backend "http" -> job\n\n' +
        'model status "job-dry-001" -> status\n\n' +
        'model compare ["fast", "code", "best"] on suite "examples/eval_suite.json" -> comparison\n\n' +
        "print comparison",
    },
    voice: {
      label: "Voice session (listen/speak)",
      source:
        "voice {\n" +
        "  listen -> user_text\n" +
        '  ask "Reply briefly: {user_text}" -> reply\n' +
        '  say reply -> "out.wav"\n' +
        "}",
    },
  };

  var PRESETS = Object.assign({}, BASE_PRESETS);
  var catalogLoaded = false;
  var playbooksLoaded = false;
  var playbooksMeta = null;

  var VOICE_FIXTURE = {
    transcript: "My login won't work — can you help?",
    reply:
      "Sure — try resetting your password, then sign in again. " +
      "If it still fails, check that caps lock is off.",
    listenJson:
      '{"op":"listen","mode":"dry-run",' +
      '"transcript":"My login won\'t work — can you help?"}',
    askJson:
      '{"op":"ask","mode":"dry-run",' +
      '"text":"Sure — try resetting your password, then sign in again. If it still fails, check that caps lock is off."}',
    speakJson:
      '{"op":"speak","mode":"dry-run","path":"out.wav","bytes":88244}',
  };

  function wrapCatalogSource(entry) {
    var syntax = (entry.syntax || "").trim();
    if (!syntax) return "# " + entry.name;
    return syntax;
  }

  function mergeCatalogPresets(data) {
    if (!data || !data.entries) return;
    var added = 0;
    var pool = (data.popularPresets || []).concat(
      data.entries.filter(function (e) {
        return e.source === "stdlib" && e.syntax && e.syntax.length > 10;
      })
    );
    var seen = {};
    Object.keys(BASE_PRESETS).forEach(function (k) {
      seen[k] = true;
    });
    pool.forEach(function (entry) {
      if (added >= 20) return;
      var key = "cat-" + entry.id;
      if (seen[key]) return;
      seen[key] = true;
      PRESETS[key] = {
        label: entry.name + " (" + entry.category + ")",
        source: wrapCatalogSource(entry),
        catalog: true,
      };
      added += 1;
    });
    catalogLoaded = true;
  }

  function fillPresetSelect(select) {
    if (!select) return;
    var current = select.value;
    select.innerHTML = "";
    var built = document.createElement("optgroup");
    built.label = "Built-in";
    Object.keys(BASE_PRESETS).forEach(function (key) {
      var opt = document.createElement("option");
      opt.value = key;
      opt.textContent = BASE_PRESETS[key].label;
      built.appendChild(opt);
    });
    select.appendChild(built);
    if (playbooksLoaded) {
      var pb = document.createElement("optgroup");
      pb.label = "AI playbooks";
      Object.keys(PRESETS).forEach(function (key) {
        if (!PRESETS[key].playbook) return;
        var opt = document.createElement("option");
        opt.value = key;
        opt.textContent = PRESETS[key].label;
        pb.appendChild(opt);
      });
      if (pb.children.length) select.appendChild(pb);
    }
    if (catalogLoaded) {
      var cat = document.createElement("optgroup");
      cat.label = "Catalog";
      Object.keys(PRESETS).forEach(function (key) {
        if (!PRESETS[key].catalog) return;
        var opt = document.createElement("option");
        opt.value = key;
        opt.textContent = PRESETS[key].label;
        cat.appendChild(opt);
      });
      if (cat.children.length) select.appendChild(cat);
    }
    if (PRESETS[current]) select.value = current;
    else if (select.options.length) select.selectedIndex = 0;
  }

  function mergePlaybookPresets(data) {
    if (!data || !data.entries) return;
    playbooksMeta = data;
    data.entries.forEach(function (entry) {
      if (!entry.id || !entry.source) return;
      var key = "pb-" + entry.id;
      PRESETS[key] = {
        label: entry.label || entry.name || entry.id,
        source: entry.source,
        playbook: true,
        playbookId: entry.id,
        fixture: entry.fixture || null,
        siteRun: entry.siteRun || "download-required",
      };
    });
    playbooksLoaded = true;
  }

  function loadPlaybookPresets(select) {
    return fetch("/data/playbooks-catalog.json")
      .then(function (r) {
        if (!r.ok) throw new Error("playbooks");
        return r.json();
      })
      .then(function (data) {
        if (!data.entries || !data.entries.length) {
          throw new Error("playbooks empty");
        }
        mergePlaybookPresets(data);
        fillPresetSelect(select);
      })
      .catch(function () {
        playbooksLoaded = false;
        var status = qs("#pg-playbook-status");
        if (status) {
          status.textContent =
            "Could not load playbooks-catalog.json — run " +
            "make playbooks-catalog and redeploy.";
        }
      });
  }

  function playbookFailLoud(preset) {
    var dl =
      (playbooksMeta && playbooksMeta.downloadUrl) || "/downloads.html";
    var localCmd =
      (playbooksMeta && playbooksMeta.localDryRun) ||
      "./spark-bootstrap --dry-run <file.spark>";
    var id = (preset && preset.playbookId) || "playbook";
    var fx = (preset && preset.fixture) || "bootstrap/fixtures/playbooks/";
    return (
      "=== NO WASM RUNTIME ON THIS SITE ===\n" +
      "Playbook loaded into the editor only.\n" +
      "This browser page does not execute Spark (no WASM / no runtime).\n" +
      "Refusing to fake dry-run output for playbook: " +
      id +
      "\n\n" +
      "Download the runtime:\n" +
      "  https://sparklang.dev" +
      dl +
      "\n" +
      "  (or open " +
      dl +
      " on this site)\n\n" +
      "Then dry-run locally:\n" +
      "  " +
      localCmd.replace("<file.spark>", fx) +
      "\n" +
      "  # or: make test-ai-playbooks\n" +
      "===================================="
    );
  }

  function loadCatalogPresets(select, onReady) {
    fetch("/data/function-catalog.json")
      .then(function (r) {
        if (!r.ok) throw new Error("catalog");
        return r.json();
      })
      .then(function (data) {
        mergeCatalogPresets(data);
        fillPresetSelect(select);
        if (onReady) onReady();
      })
      .catch(function () {
        catalogLoaded = false;
      });
  }

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

  function flashCopy(btn) {
    var prev = btn.textContent;
    btn.textContent = "Copied!";
    setTimeout(function () {
      btn.textContent = prev;
    }, 1600);
  }

  function detectModel(source) {
    var use = source.match(/^\s*use\s+(\w+)/m);
    if (use) return use[1];
    var model = source.match(/^\s*model\s+(\w+)/m);
    if (model) return model[1];
    return "code";
  }

  function setUseLine(source, alias) {
    if (/^\s*use\s+\w+/m.test(source)) {
      return source.replace(/^\s*use\s+\w+/m, "use " + alias);
    }
    if (/^\s*model\s+\w+/m.test(source)) {
      return source.replace(/^\s*model\s+\w+/m, "model " + alias);
    }
    return "use " + alias + "\n\n" + source;
  }

  function simulateAsk(source, model) {
    var m = source.match(/ask\s+"([^"]+)"/);
    if (!m) return [];
    var prompt = m[1];
    var text = "Sample reply for: " + prompt.slice(0, 60);
    if (prompt.toLowerCase().indexOf("gravity") >= 0) {
      text = "Gravity is the mutual attraction between masses.";
    }
    if (prompt.toLowerCase().indexOf("reply") >= 0) {
      text = VOICE_FIXTURE.reply;
    }
    return [
      JSON.stringify({ op: "ask", mode: "dry-run", model: model, text: text }),
      text,
    ];
  }

  function simulateClassify(source) {
    if (!/classify\s/i.test(source)) return [];
    var multi = /classify\s+multi/i.test(source);
    if (multi) {
      return [
        '{"labels":["support","sales"],"confidence":0.81}',
        '{"labels":["support","sales"],"confidence":0.81}',
      ];
    }
    return [
      '{"label":"support","confidence":0.92,"reasons":["account","help"]}',
      '{"label":"support","confidence":0.92,"reasons":["account","help"]}',
    ];
  }

  function simulatePipeline(source, model) {
    if (!/pipeline\s*\{/i.test(source)) return [];
    return [
      JSON.stringify({
        op: "ask",
        mode: "dry-run",
        model: model,
        step: "summary",
        text: "Office printers need regular cleaning.",
      }),
      JSON.stringify({
        op: "ask",
        mode: "dry-run",
        model: model,
        step: "translate",
        text: "Las impresoras de oficina necesitan limpieza regular.",
      }),
    ];
  }

  function simulateModelOps(source) {
    var out = [];
    if (/model\s+analyze/i.test(source)) {
      var alias = detectModel(source);
      var aMatch = source.match(/model\s+analyze\s+"([^"]+)"/);
      if (aMatch) alias = aMatch[1];
      out.push(MODEL_FIXTURES.analyze.replace("{alias}", alias));
    }
    if (/model\s+compare/i.test(source)) {
      out.push(MODEL_FIXTURES.compare);
    }
    if (/model\s+improve/i.test(source)) {
      out.push(MODEL_FIXTURES.improve);
    }
    if (/model\s+build/i.test(source)) {
      out.push(MODEL_FIXTURES.build);
    }
    return out;
  }

  function simulateVoice(source, model) {
    if (!/(listen|speak|say|\bvoice\s*\{)/i.test(source)) return [];
    var out = [];
    if (/listen/i.test(source)) {
      out.push(VOICE_FIXTURE.listenJson);
      out.push("transcript: " + VOICE_FIXTURE.transcript);
    }
    if (/ask\s+"[^"]*\{user/i.test(source) || /voice\s*\{/i.test(source)) {
      out.push(VOICE_FIXTURE.askJson);
      out.push(VOICE_FIXTURE.reply);
    }
    if (/speak|say/i.test(source)) {
      out.push(VOICE_FIXTURE.speakJson);
      out.push("wrote out.wav (dry-run stub WAV)");
    }
    if (!out.length && /voice/i.test(source)) {
      out.push(VOICE_FIXTURE.listenJson);
      out.push(VOICE_FIXTURE.askJson);
      out.push(VOICE_FIXTURE.speakJson);
    }
    return out;
  }

  function simulateDryRun(source) {
    var model = detectModel(source);
    var parts = [];
    parts = parts.concat(simulateAsk(source, model));
    parts = parts.concat(simulateClassify(source));
    parts = parts.concat(simulatePipeline(source, model));
    parts = parts.concat(simulateModelOps(source));
    parts = parts.concat(simulateVoice(source, model));

    if (!parts.length) {
      parts.push(
        '{"op":"run","mode":"dry-run","note":"No recognized ops — try ask, classify, model, or voice"}'
      );
    }
    return parts.join("\n");
  }

  function liveCmd(source) {
    return (
      "./spark-run.sh --dry-run my_program.spark\n" +
      "export AI_GATEWAY_URL=http://127.0.0.1:4000\n" +
      "./spark-run.sh --live my_program.spark"
    );
  }

  function initTabs() {
    var tabs = qsa(".pg-tab");
    var panels = qsa(".pg-panel");
    if (!tabs.length) return;

    function activate(id, focusTab) {
      tabs.forEach(function (tab) {
        var on = tab.getAttribute("data-tab") === id;
        tab.classList.toggle("is-active", on);
        tab.setAttribute("aria-selected", on ? "true" : "false");
        tab.tabIndex = on ? 0 : -1;
        if (on && focusTab) tab.focus();
      });
      panels.forEach(function (panel) {
        var on = panel.getAttribute("data-panel") === id;
        panel.classList.toggle("is-active", on);
        panel.hidden = !on;
      });
    }

    tabs.forEach(function (tab, index) {
      tab.addEventListener("click", function () {
        activate(tab.getAttribute("data-tab"), false);
      });
      tab.addEventListener("keydown", function (ev) {
        var next = -1;
        if (ev.key === "ArrowRight" || ev.key === "ArrowDown") {
          next = (index + 1) % tabs.length;
        } else if (ev.key === "ArrowLeft" || ev.key === "ArrowUp") {
          next = (index - 1 + tabs.length) % tabs.length;
        } else if (ev.key === "Home") {
          next = 0;
        } else if (ev.key === "End") {
          next = tabs.length - 1;
        } else if (ev.key === "Enter" || ev.key === " ") {
          ev.preventDefault();
          activate(tab.getAttribute("data-tab"), false);
          return;
        }
        if (next < 0) return;
        ev.preventDefault();
        activate(tabs[next].getAttribute("data-tab"), true);
      });
    });

    activate("code", false);
  }

  function initCodePanel() {
    var textarea = qs("#pg-source");
    var output = qs("#pg-output");
    var preset = qs("#pg-preset");
    var runBtn = qs("#pg-run-dry");
    var clearBtn = qs("#pg-clear-output");
    var copyOutBtn = qs("#pg-copy-output");
    var cmdEl = qs("#pg-cmd");
    if (!textarea || !output) return;

    function loadPreset(key) {
      var p = PRESETS[key] || PRESETS.hello;
      textarea.value = p.source;
      var status = qs("#pg-playbook-status");
      if (status) {
        if (p.playbook) {
          status.textContent =
            "Playbook \u201c" +
            (p.playbookId || key) +
            "\u201d loaded from catalog. " +
            "Run dry-run will refuse to fake execution (download runtime).";
        } else {
          status.textContent = "";
        }
      }
    }

    if (preset) {
      fillPresetSelect(preset);
      preset.addEventListener("change", function () {
        loadPreset(preset.value);
      });
      loadPreset(preset.value);
      loadPlaybookPresets(preset).then(function () {
        loadCatalogPresets(preset, function () {
          loadPreset(preset.value);
        });
      });
    }

    function runDry() {
      var src = textarea.value;
      var selected = preset ? PRESETS[preset.value] : null;
      if (selected && selected.playbook) {
        output.textContent = playbookFailLoud(selected);
        output.classList.remove("is-empty");
        if (cmdEl) {
          cmdEl.textContent =
            "./spark-bootstrap --dry-run " +
            (selected.fixture || "my_playbook.spark");
        }
        return;
      }
      var banner =
        "=== Browser dry-run preview (fixtures only) ===\n" +
        "This page does not embed the Spark runtime or WASM.\n" +
        "For real dry-run / live execution, download the runtime:\n" +
        "  https://sparklang.dev/downloads.html\n" +
        "  ./spark-run.sh --dry-run my_program.spark\n" +
        "==============================================\n\n";
      output.textContent = banner + simulateDryRun(src);
      output.classList.remove("is-empty");
      if (cmdEl) cmdEl.textContent = liveCmd(src);
    }

    if (runBtn) runBtn.addEventListener("click", runDry);
    if (clearBtn) {
      clearBtn.addEventListener("click", function () {
        output.textContent = "Output cleared. Run dry-run to simulate again.";
        output.classList.add("is-empty");
        if (cmdEl) cmdEl.textContent = "";
      });
    }
    if (copyOutBtn) {
      copyOutBtn.addEventListener("click", function () {
        copyText(output.textContent).then(function () {
          flashCopy(copyOutBtn);
        });
      });
    }

    return { getSource: function () { return textarea.value; }, setSource: function (s) { textarea.value = s; }, runDry: runDry };
  }

  function initVoicePanel(codeApi) {
    var micBtn = qs("#pg-voice-mic");
    var speakBtn = qs("#pg-voice-speak");
    var transcriptEl = qs("#pg-voice-transcript");
    var replyEl = qs("#pg-voice-reply");
    var statusEl = qs("#pg-voice-status");
    var voiceDryBtn = qs("#pg-voice-dry");
    var copyVoiceBtn = qs("#pg-copy-voice-snippet");
    var voiceSnippet = qs("#pg-voice-snippet");
    var SpeechRecognition =
      window.SpeechRecognition || window.webkitSpeechRecognition;

    var lastReply = VOICE_FIXTURE.reply;

    function setStatus(msg) {
      if (statusEl) statusEl.textContent = msg;
    }

    if (micBtn) {
      if (!SpeechRecognition) {
        micBtn.disabled = true;
        setStatus(
          "Speech recognition not supported in this browser. Use Chrome or Edge, or run Spark locally."
        );
      } else {
        micBtn.addEventListener("click", function () {
          var rec = new SpeechRecognition();
          rec.lang = "en-US";
          rec.interimResults = false;
          rec.maxAlternatives = 1;
          setStatus("Listening…");
          micBtn.disabled = true;
          rec.onresult = function (ev) {
            var text = ev.results[0][0].transcript;
            if (transcriptEl) transcriptEl.textContent = text;
            lastReply =
              "Thanks — I heard: \"" +
              text +
              "\". In a live Spark program this would flow into ask → speak.";
            if (replyEl) replyEl.textContent = lastReply;
            setStatus("Transcript captured.");
            micBtn.disabled = false;
          };
          rec.onerror = function () {
            setStatus("Mic error — check permissions or try again.");
            micBtn.disabled = false;
          };
          rec.onend = function () {
            micBtn.disabled = false;
          };
          rec.start();
        });
      }
    }

    if (speakBtn) {
      speakBtn.addEventListener("click", function () {
        if (!window.speechSynthesis) {
          setStatus("Speech synthesis not available in this browser.");
          return;
        }
        var text = replyEl ? replyEl.textContent : lastReply;
        var u = new SpeechSynthesisUtterance(text);
        u.rate = 1;
        window.speechSynthesis.cancel();
        window.speechSynthesis.speak(u);
        setStatus("Speaking assistant reply (browser TTS demo).");
      });
    }

    if (voiceDryBtn && codeApi) {
      voiceDryBtn.addEventListener("click", function () {
        codeApi.setSource(PRESETS.voice.source);
        codeApi.runDry();
        var tabs = qs('.pg-tab[data-tab="code"]');
        if (tabs) tabs.click();
      });
    }

    if (copyVoiceBtn && voiceSnippet) {
      copyVoiceBtn.addEventListener("click", function () {
        copyText(voiceSnippet.textContent).then(function () {
          flashCopy(copyVoiceBtn);
        });
      });
    }

    if (transcriptEl) transcriptEl.textContent = VOICE_FIXTURE.transcript;
    if (replyEl) replyEl.textContent = VOICE_FIXTURE.reply;
  }

  function init() {
    if (!qs(".playground")) return;
    initTabs();
    var codeApi = initCodePanel();
    initVoicePanel(codeApi);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
