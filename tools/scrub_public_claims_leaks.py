#!/usr/bin/env python3
"""Scrub authenticity theater, honesty branding, owner-dump voice,
beat-Claude claims, and internal leak jargon from public Spark paths.

Edits docs/, website hand pages, README, CHANGELOG, examples, SVGs.
The `beats_claude` JSON field was removed from tool output
entirely (2026-09-10); these patterns still scrub historical prose
mentions — prose must not say “beats Claude”.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Order matters: longer / more specific first.
REPLACEMENTS: list[tuple[re.Pattern[str], str]] = [

    # --- authenticity theater / Real captions ---
    (
        re.compile(
            r"(?i)Caption:\s*Real terminal capture of\s*"
        ),
        "Caption: Terminal output from ",
    ),
    (
        re.compile(r"(?i)Caption:\s*Real\s+"),
        "Caption: ",
    ),
    (
        re.compile(r"(?i)\*Caption:\s*Real terminal capture of\s*"),
        "*Caption: Terminal output from ",
    ),
    (
        re.compile(r"(?i)Real terminal capture of\s*"),
        "Terminal output from ",
    ),
    (
        re.compile(r"(?i)Real Spark CLI dump\s*—\s*not a third-party UI screenshot\.?"),
        "Spark CLI dump output.",
    ),
    (
        re.compile(r"(?i)with real CLI screenshots"),
        "with CLI screenshots",
    ),
    (
        re.compile(r"(?i)\breal wall-clock\b"),
        "wall-clock",
    ),
    (
        re.compile(r"(?i)a real dump"),
        "a dump",
    ),
    (
        re.compile(r"(?i)uses real dump SoT"),
        "uses dump SoT",
    ),
    (
        re.compile(r"(?i)Not invented hex\.?"),
        "",
    ),
    (
        re.compile(r"(?i)\(existing fixture; not invented\)\.?"),
        "(existing fixture).",
    ),
    (
        re.compile(r"(?i)\(not invented:"),
        "(",
    ),
    (
        re.compile(r"(?i)— not invented as a real cmd\)"),
        "— unknown cmds stay fail-loud)",
    ),
    (
        re.compile(r"(?i)Never invents API keys\.?"),
        "",
    ),
    (
        re.compile(r"(?i)Never invents keys\.?"),
        "",
    ),
    (
        re.compile(r"(?i)Never invents tokens"),
        "Missing usage stays blank — no invented tokens",
    ),
    (
        re.compile(r"(?i)never invents gateway aliases"),
        "unknown prompts do not invent gateway aliases",
    ),
    (
        re.compile(r"(?i)never invents a model id"),
        "does not invent a model id",
    ),
    (
        re.compile(r"(?i)Dry never invents trained weights\.?"),
        "Dry-run does not write trained weights.",
    ),
    (
        re.compile(r"(?i)Never invents bytes"),
        "No invented bytes",
    ),
    # --- honesty / honest branding ---
    (re.compile(r"(?i)Eval honesty"), "Eval practice"),
    (re.compile(r"(?i)eval honesty"), "eval practice"),
    (re.compile(r"(?i)Spark honesty map"), "Current capabilities"),
    (re.compile(r"(?i)Spark honesty"), "Spark status"),
    (re.compile(r"(?i)Attention honesty"), "Attention status"),
    (re.compile(r"(?i)Brain honesty"), "Brain status"),
    (re.compile(r"(?i)Architecture honesty"), "Architecture status"),
    (re.compile(r"(?i)Builder factory honesty"), "Builder factory status"),
    (re.compile(r"(?i)Factory honesty"), "Factory status"),
    (re.compile(r"(?i)scale honesty"), "scale status"),
    (re.compile(r"(?i)homepage honesty"), "homepage status"),
    (re.compile(r"(?i)Mandatory Spark honesty cue"), "Spark caveat"),
    (re.compile(r"(?i)Honesty bar \(never fake\)"), "Status bar"),
    (re.compile(r"(?i)Honesty bar"), "Status"),
    (re.compile(r"(?i)Honesty contract"), "Eval contract"),
    (re.compile(r"(?i)Honesty rules \(Spark\)"), "Eval reporting rules"),
    (re.compile(r"(?i)Honesty rules"), "Eval reporting rules"),
    (re.compile(r"(?i)Honesty:"), "Status:"),
    (re.compile(r"(?i)\*\*Honesty:\*\*"), "**Status:**"),
    (re.compile(r"(?i)Honest gaps"), "Known gaps"),
    (re.compile(r"(?i)Honest limits"), "Current scope"),
    (re.compile(r"(?i)Honest capability"), "Current capability"),
    (re.compile(r"(?i)Honest bar"), "Status"),
    (re.compile(r"(?i)Honest status of"), "Status of"),
    (re.compile(r"(?i)Honest status"), "Current status"),
    (re.compile(r"(?i)Honest site run:"), "Site playground:"),
    (re.compile(r"(?i)Honest note:"), "Note:"),
    (re.compile(r"(?i)Honest —\s*"), ""),
    (re.compile(r"(?i)^Honest — "), ""),
    (re.compile(r"(?i)honest status table"), "status table"),
    (re.compile(r"(?i)honest model"), "owned model"),
    (re.compile(r"(?i)and honest model"), "and owned model"),
    (re.compile(r"(?i)answers carry an honesty note"), "answers include a capability note"),
    (re.compile(r"(?i)honesty note"), "capability note"),
    (re.compile(r"(?i)honesty footer"), "capability footer"),
    (re.compile(r"(?i)honesty table"), "status table"),
    (re.compile(r"(?i)coder honesty table"), "coder status table"),
    (re.compile(r"(?i)JSON honesty table"), "JSON status table"),
    (re.compile(r"(?i)knobs \+ honesty"), "knobs + status"),
    (re.compile(r"(?i)Tiny vs large \(honesty\)"), "Tiny vs large"),
    (re.compile(r"(?i)ARTIFACT / checkpoint honesty"), "ARTIFACT / checkpoint status"),
    (re.compile(r"(?i)Eval &amp; honesty"), "Eval &amp; status"),
    (re.compile(r"(?i)Eval / honesty"), "Eval / status"),
    (re.compile(r"(?i)Eval &amp; honesty"), "Eval &amp; status"),
    (re.compile(r"(?i)Training &amp; adaptation · Eval &amp; honesty"), "Training &amp; adaptation · Eval &amp; status"),
    (re.compile(r"(?i)honest about fixture-scale"), "fixture-scale"),
    (re.compile(r"(?i)honest about what"), "clear about what"),
    (re.compile(r"(?i)tiny and honest"), "tiny and explicit"),
    (re.compile(r"(?i)labeled honestly"), "labeled as a mock"),
    (re.compile(r"(?i)are honest misses"), "are recorded misses"),
    (re.compile(r"(?i)and honest <"), "and <"),
    (re.compile(r"(?i)honest <code"), "<code"),
    (re.compile(r"(?i)Not magic honesty weights"), "Not magic calibration weights"),
    (re.compile(r"class=\"honest-note\""), 'class="status-note"'),
    (re.compile(r"\.honest-note"), ".status-note"),
    (re.compile(r"id=\"spark-honesty-map\""), 'id="current-capabilities"'),
    (re.compile(r"id=\"spark-honesty\""), 'id="spark-status"'),
    (re.compile(r"id=\"honesty-rules-spark\""), 'id="eval-reporting-rules"'),
    (re.compile(r"id=\"honesty-bar\""), 'id="status"'),
    (re.compile(r"id=\"honesty-bar-never-fake\""), 'id="status-bar"'),
    (re.compile(r"id=\"honesty-contract\""), 'id="eval-contract"'),
    (re.compile(r"id=\"eval-and-benchmark-honesty\""), 'id="eval-and-benchmark-practice"'),
    (re.compile(r"id=\"eval-honesty[^\"]*\""), 'id="eval-practice"'),
    (re.compile(r"id=\"brain-honesty\""), 'id="brain-status"'),
    (re.compile(r"id=\"tiny-vs-large-honesty\""), 'id="tiny-vs-large"'),
    (re.compile(r"id=\"honest-capability\""), 'id="current-capability"'),
    (re.compile(r"id=\"honest-bar\""), 'id="status"'),
    (re.compile(r"id=\"artifact-checkpoint-honesty\""), 'id="artifact-checkpoint-status"'),
    (re.compile(r"(?i)Eval and benchmark honesty"), "Eval and benchmark practice"),
    (re.compile(r"(?i)\bhonesty\b"), "status"),
    (re.compile(r"(?i)\bHonestly\b"), "Clearly"),
    (re.compile(r"(?i)\bhonestly\b"), "clearly"),
    # leftover bare Honest / honest as adjective branding
    (re.compile(r"(?i)\bHonest\b"), "Current"),
    (re.compile(r"(?i)\bhonest\b"), "clear"),
    # --- owner Not/Never dumps / vendor bans ---
    # No (?s)/DOTALL: greedy \s* across whole HTML hangs.
    (
        re.compile(
            r"<p><strong>Not</strong> ElevenLabs, Kokoro, or a downloaded "
            r"mega TTS overnight\.\s*"
            r"<strong>Never</strong> trains on the RTX PRO "
            r"<strong>6000</strong> \(voice-serving only\)\.\s*"
            r"Prefers RTX <strong>5090</strong> for large\. "
            r"Does <strong>not</strong> beat Claude\.\s*"
            r"(?:No API keys in git\.\s*)?</p>",
            re.I,
        ),
        "<p>Owned STT/TTS heads you train in-repo (tiny CI default; "
        "optional larger scale on CPU or a consumer GPU).</p>",
    ),
    (
        re.compile(
            r"<p><strong>Not</strong> ElevenLabs, Kokoro, or a downloaded "
            r"mega TTS overnight\.\s*"
            r"Prefer CPU or a consumer GPU for optional train\.\s*"
            r"Prefers RTX <strong>5090</strong> for large\.\s*"
            r"Measurement only — not a marketing win\.\s*"
            r"(?:No API keys in git\.\s*)?</p>",
            re.I,
        ),
        "<p>Owned STT/TTS heads you train in-repo (tiny CI default; "
        "optional larger scale on CPU or a consumer GPU).</p>",
    ),
    (
        re.compile(
            r"\*\*Not\*\* ElevenLabs, Kokoro, or a downloaded mega TTS "
            r"overnight\.\s*"
            r"\*\*Never\*\* trains on the RTX PRO \*\*6000\*\* "
            r"\(voice-serving only\)\.\s*"
            r"Prefers RTX \*\*5090\*\* for large\. "
            r"Does \*\*not\*\* beat Claude\.\s*"
            r"(?:No API keys in git\.\s*)?",
            re.I,
        ),
        "Owned Spark STT/TTS heads trained in this repo — not a "
        "vendor TTS SaaS. Prefer CPU or a consumer GPU for optional "
        "train. ",
    ),
    (
        re.compile(
            r"(?i)\*\*Not\*\* ElevenLabs, Kokoro, or a downloaded mega TTS "
            r"overnight\.\s*"
        ),
        "",
    ),
    (
        re.compile(
            r"(?i)Not ElevenLabs, Kokoro, or a downloaded mega TTS "
            r"overnight\.\s*"
        ),
        "",
    ),
    (
        re.compile(r"(?i)Not ElevenLabs overnight\.?\s*"),
        "",
    ),
    (
        re.compile(r"(?i)— not ElevenLabs overnight\.?\s*"),
        ". ",
    ),
    (
        re.compile(r"(?i)Owned heads — not ElevenLabs overnight\.?\s*"),
        "Owned STT/TTS heads. ",
    ),
    (
        re.compile(
            r"(?i)Vendor <strong>neural</strong> clone \(ElevenLabs/etc\.\) is outside this artifact;?"
        ),
        "Third-party neural voice cloning is outside this artifact;",
    ),
    (
        re.compile(
            r"(?i)Vendor \*\*neural\*\* clone \(ElevenLabs/etc\.\) is outside this artifact;?"
        ),
        "Third-party neural voice cloning is outside this artifact;",
    ),
    (
        re.compile(r"(?i)\| Replace ElevenLabs overnight \|"),
        "| Third-party mega-TTS overnight |",
    ),
    (
        re.compile(r"(?i)<td>Replace ElevenLabs overnight</td>"),
        "<td>Third-party mega-TTS overnight</td>",
    ),
    (
        re.compile(r"(?i)Vendor mega-TTS overnight"),
        "Third-party mega-TTS overnight",
    ),
    (
        re.compile(r"(?i)No API keys in git\.?\s*"),
        "",
    ),
    (
        re.compile(
            r"(?i)# Large — opt-in; prefers 5090; fail closed if only 6000 visible"
        ),
        "# Large — opt-in; prefer a consumer GPU or CPU",
    ),
    (
        re.compile(
            r"(?i)Prefers RTX <strong>5090</strong> for large\.?\s*"
        ),
        "",
    ),
    (
        re.compile(r"(?i)Prefers RTX \*\*5090\*\* for large\.?\s*"),
        "",
    ),
    (
        re.compile(r"(?i)prefer <strong>RTX 5090</strong>"),
        "prefer a consumer GPU",
    ),
    (
        re.compile(r"(?i)Prefer <strong>5090</strong>"),
        "Prefer a consumer GPU",
    ),
    (
        re.compile(r"(?i)prefers RTX 5090 \(or CPU\)"),
        "prefers a consumer GPU or CPU",
    ),
    (
        re.compile(r"(?i)auto prefers RTX 5090 \(or CPU\)"),
        "auto prefers a consumer GPU or CPU",
    ),
    (
        re.compile(r"(?i)Prefer CPU or a consumer GPU for optional train\.?\s*"),
        "Train on CPU or a consumer GPU. ",
    ),
    (
        re.compile(
            r"(?i)\(voice-serving GPU elsewhere — not Spark train\)\.?\s*"
        ),
        "",
    ),
    (
        re.compile(r"(?i)\(voice GPU\)\.?\s*"),
        "",
    ),
    (
        re.compile(
            r"(?i)fail closed if only PRO <strong>6000</strong> visible unless"
        ),
        "use CPU when no suitable GPU is visible unless",
    ),
    (
        re.compile(r"(?i)RTX 5090 OK;?\s*"),
        "",
    ),
    (
        re.compile(r"(?i)CPU default;?\s*Do not"),
        "CPU default. Do not",
    ),
    # --- soften competitive / marketing-win theater ---
    (
        re.compile(
            r"(?i)Measurement only — not a marketing win\.?"
        ),
        "Scores and probes are measurement-only.",
    ),
    (
        re.compile(
            r"(?i)measurement only — not a marketing win\.?"
        ),
        "scores and probes are measurement-only.",
    ),
    (
        re.compile(r"(?i)not a marketing win\.?"),
        "measurement-only.",
    ),
    (
        re.compile(r"(?i)Never publish a competitive AI win claim\.?"),
        "",
    ),
    (
        re.compile(r"(?i)Never publishes competitive AI win claims\.?"),
        "",
    ),
    (
        re.compile(r"(?i)\*\*Never\*\* publishes competitive AI win claims\.?"),
        "",
    ),
    (
        re.compile(r"(?i)Competitive AI win claim"),
        "Frontier benchmark win",
    ),
    (
        re.compile(r"(?i)competitive AI win claims?"),
        "frontier benchmark wins",
    ),
    (
        re.compile(r'(?i)Never "competitive AI win" banner'),
        "Report scores without a win banner",
    ),
    (
        re.compile(r"(?i)ban\[Never \"competitive AI win\" banner\]"),
        "ban[Report without win banner]",
    ),
    # --- beat Claude / competitive AI claims ---
    (
        re.compile(
            r"\*\*\.\*\*",
            re.I,
        ),
        "****",
    ),
    (
        re.compile(r"Does\s+\*\*not\*\*\s+beat Claude\.?", re.I),
        "",
    ),
    (
        re.compile(r"does\s+\*\*not\*\*\s+beat Claude\.?", re.I),
        "",
    ),
    (
        re.compile(r"\*\*Not beat Claude\.\*\*", re.I),
        "**Measurement only.**",
    ),
    (
        re.compile(r"\*\*not\*\*\s+beat Claude\.?", re.I),
        "**measurement only**",
    ),
    (
        re.compile(r"[Nn]ever\s+beat Claude\.?"),
        "",
    ),
    (
        re.compile(r"[Dd]oes\s+not\s+beat Claude\.?"),
        "",
    ),
    (
        re.compile(r"[Nn]ot beat Claude\.?"),
        "measurement only.",
    ),
    (
        re.compile(r"not\s+beat Claude", re.I),
        "measurement only",
    ),
    (
        re.compile(
            r"\*\*Never\*\*\s+claims beat Claude\.?",
            re.I,
        ),
        "**Never** publishes competitive AI win claims.",
    ),
    (
        re.compile(r"[Nn]ever claims beat Claude\.?"),
        "Never publishes competitive AI win claims.",
    ),
    (
        re.compile(r"[Nn]ever invents keys\. Never claims beat Claude\.?"),
        "Never publishes competitive AI win claims.",
    ),
    (
        re.compile(
            r"later stages aim to beat Claude",
            re.I,
        ),
        "later stages may grow train/eval (not a published claim)",
    ),
    (
        re.compile(
            r"later owner train toward beat-Claude — not claimed today",
            re.I,
        ),
        "later owner train/eval growth — not claimed today",
    ),
    (
        re.compile(r"train aims to beat Claude", re.I),
        "train grows under measurement (not a published claim)",
    ),
    (
        re.compile(
            r"<strong>Later beat Claude</strong>",
            re.I,
        ),
        "<strong>Later larger train/eval</strong>",
    ),
    (
        re.compile(r"Later beat Claude", re.I),
        "Later larger train/eval",
    ),
    (
        re.compile(r"\| Beat Claude \|", re.I),
        "| Competitive AI win claim |",
    ),
    (
        re.compile(r"\| “Beat Claude” \|", re.I),
        "| Competitive AI win claim |",
    ),
    (
        re.compile(r"\| \"Beat Claude\" \|", re.I),
        "| Competitive AI win claim |",
    ),
    (
        re.compile(r"Beat Claude — \*\*no\*\*\.?", re.I),
        "Competitive AI win claims — **no**.",
    ),
    (
        re.compile(r"Beat Claude / use RTX PRO 6000", re.I),
        "Competitive AI win claims / train on RTX PRO 6000",
    ),
    (
        re.compile(r"Beat Claude / perfect decompile", re.I),
        "Competitive AI win / perfect decompile",
    ),
    (
        re.compile(r"Claim beat Claude", re.I),
        "Claim a competitive AI win",
    ),
    (
        re.compile(r"claim beat Claude", re.I),
        "claim a competitive AI win",
    ),
    (
        re.compile(r"scores beat Claude", re.I),
        "scores as a competitive AI win",
    ),
    (
        re.compile(r"Does not beat Claude\.?", re.I),
        "Does not publish competitive AI win claims.",
    ),
    (
        re.compile(r"does not beat Claude\.?", re.I),
        "does not publish competitive AI win claims.",
    ),
    (
        re.compile(r"Does \*\*not\*\* beat Claude\.?", re.I),
        "Does not publish competitive AI win claims.",
    ),
    (
        re.compile(r"\"beat Claude\"", re.I),
        '"competitive AI win"',
    ),
    (
        re.compile(r"'beat Claude'", re.I),
        "'competitive AI win'",
    ),
    (
        re.compile(r"beat-Claude", re.I),
        "competitive-AI-win",
    ),
    (
        re.compile(r"better than Claude", re.I),
        "a competitive AI win",
    ),
    (
        re.compile(
            r"Eval harness \(measure later — not beat Claude\)",
            re.I,
        ),
        "Eval harness (measurement only)",
    ),
    (
        re.compile(
            r"still <strong>not</strong> beat Claude\.?",
            re.I,
        ),
        "still <strong>measurement only</strong>.",
    ),
    (
        re.compile(r"Honest — not beat Claude\.?", re.I),
        "Status — measurement only, not a marketing win.",
    ),
    (
        re.compile(r"Not production LLM weights\. Never beat Claude\.?", re.I),
        "Not production LLM weights. Measurement only.",
    ),
    (
        re.compile(
            r"optional Claude baseline — \*\*not\*\* beat Claude",
            re.I,
        ),
        "optional Claude API baseline — measurement only",
    ),
    (
        re.compile(
            r"Measurement only — not beat Claude\.?",
            re.I,
        ),
        "Measurement only — no competitive AI win claim.",
    ),
    (
        re.compile(
            r"not beat Claude\.?",
            re.I,
        ),
        "no competitive AI win claim.",
    ),
    (
        re.compile(
            r"\(`make spark-eval`\); exit 0 = harness ran "
            r"\(\*\*not\*\* beat Claude\)",
            re.I,
        ),
        "(`make spark-eval`); exit 0 = harness ran (measurement only)",
    ),
    (
        re.compile(
            r"Frozen copy/recall \+ next-token probes; exit 0 = "
            r"harness ran \(\*\*not\*\* beat Claude\)",
            re.I,
        ),
        "Frozen copy/recall + next-token probes; exit 0 = "
        "harness ran (measurement only)",
    ),
    (
        re.compile(
            r"Exit 0 = harness ran — \*\*not\*\* beat Claude",
            re.I,
        ),
        "Exit 0 = harness ran — measurement only",
    ),
    (
        re.compile(
            r"eyes planned stub only; not beat Claude",
            re.I,
        ),
        "eyes planned stub only; measurement only",
    ),
    (
        re.compile(
            r"Still \*\*not\*\* beat Claude",
            re.I,
        ),
        "Still **measurement only**",
    ),
    (
        re.compile(
            r"TinyCoder\. Still \*\*not\*\* beat Claude",
            re.I,
        ),
        "TinyCoder. Still **measurement only**",
    ),
    (
        re.compile(
            r"attention decode still partial; \*\*not\*\* beat Claude",
            re.I,
        ),
        "attention decode still partial; **measurement only**",
    ),
    (
        re.compile(
            r"\(tiny; attn train; loss drop \+ eval>0 proven; "
            r"not beat Claude\)",
            re.I,
        ),
        "(tiny; attn train; loss drop + eval>0 proven; measurement only)",
    ),
    (
        re.compile(
            r"Does \*\*not\*\* beat Claude or these models/products\.?",
            re.I,
        ),
        "Does **not** publish competitive AI win claims vs these models/products.",
    ),
    (
        re.compile(
            r"eval never claims beat Claude",
            re.I,
        ),
        "eval ",
    ),
    (
        re.compile(
            r"CPU only · not beat Claude",
            re.I,
        ),
        "CPU only · measurement only",
    ),
    (
        re.compile(
            r"Never invents bytes · CPU only · not beat Claude",
            re.I,
        ),
        "Never invents bytes · CPU only · measurement only",
    ),
    (
        re.compile(
            r"\. Never uses the RTX PRO 6000\.?",
            re.I,
        ),
        "Prefer CPU or RTX 5090 for train.",
    ),
    (
        re.compile(
            r"Output `beats_claude` always \*\*false\*\*\.?",
            re.I,
        ),
        "Harness sets `claim: none` (no marketing-win flag).",
    ),
    (
        re.compile(
            r"Output <code class=\"inline-code\">beats_claude</code> "
            r"always <strong>false</strong>\.?",
            re.I,
        ),
        "Harness sets <code class=\"inline-code\">claim: none</code> "
        "(no marketing-win flag).",
    ),
    (
        re.compile(
            r"`beats_claude` always \*\*false\*\*\.?",
            re.I,
        ),
        "`claim: none` (no marketing-win flag).",
    ),
    (
        re.compile(
            r"<code class=\"inline-code\">beats_claude</code>: always "
            r"<strong>false</strong>",
            re.I,
        ),
        "<code class=\"inline-code\">claim: none</code> "
        "(no marketing-win flag)",
    ),
    (
        re.compile(
            r"and <code class=\"inline-code\">beats_claude: false</code>\.?",
            re.I,
        ),
        "and no marketing-win flag.",
    ),
    (
        re.compile(
            r"and `beats_claude: false`\.?",
            re.I,
        ),
        "and no marketing-win flag.",
    ),
    (
        re.compile(r"beats_claude=false", re.I),
        "claim=none",
    ),
    (
        re.compile(r"beats_claude=False", re.I),
        "claim=none",
    ),
    (
        re.compile(r"beats_claude", re.I),
        "claim",  # last resort in prose; code files excluded below
    ),
    # --- lane / host / ops leaks ---
    (re.compile(r"\bSoapBox\b"), "the deploy host"),
    # Neutral product framing (keep URLs; drop operator-* voice)
    (
        re.compile(
            r"(?i)Research links\s*\(cite these\)"
        ),
        "Further reading",
    ),
    (
        re.compile(
            r"(?i)Folded into this page from research notes\s*"
            r"\(full URLs\):?"
        ),
        "Selected public papers, repos, and articles:",
    ),
    (re.compile(r"(?i)\boperator research\b"), "research notes"),
    (re.compile(r"(?i)\boperator links\b"), "references"),
    (re.compile(r"(?i)\boperator host\b"), "deploy host"),
    (re.compile(r"(?i)\boperator backends\b"), "advanced backends"),
    (re.compile(r"(?i)\boperator work\b"), "lab setup"),
    (re.compile(r"(?i)\boperator Q&A\b"), "grounded Q&A"),
    (re.compile(r"(?i)\boperator choice\b"), "opt-in"),
    (re.compile(r"(?i)\bowner citations\b"), "public citations"),
    (re.compile(r"\bCRAG-lite\b"), "retrieval-grading lite"),
    (re.compile(r"\bCRAG\b"), "retrieval grading"),
    (re.compile(r"\bD-lane\b"), "attention train"),
    (re.compile(r"\bF-lane\b"), "scale fixtures"),
    (re.compile(r"\bE-lane\b"), "eval harness"),
    (re.compile(r"\bH-lane\b"), "docs hub"),
    (re.compile(r"\bL-lane\b"), "model aspects"),
    (re.compile(r"\bK-lane\b"), "helpers"),
    (re.compile(r"\bM-lane\b"), "model lab"),
    (re.compile(r"CallsBack\.ai workers"), "store phone workers"),
    (re.compile(r"CallsBack\.ai"), "the phone stack"),
    (re.compile(r"\bvoicecore\b", re.I), "the phone runtime"),
    (re.compile(r"REQUEST ROLL", re.I), "deploy note"),
    (re.compile(r"\bGOLDEN\b"), "operator lesson"),
    (re.compile(r"workspaces/reports/[^\s\)\"']+"), "internal report"),
    # Bifrost product identity (keep OpenAI-compatible gateway language)
    (
        re.compile(
            r"Spark is \*\*not\*\* a Bifrost plugin",
            re.I,
        ),
        "Spark is **not** tied to a single AI gateway",
    ),
    (
        re.compile(
            r"\*\*Spark is not a Bifrost plugin\*\*",
            re.I,
        ),
        "**Spark is not tied to a single AI gateway**",
    ),
    (
        re.compile(r"not a Bifrost plugin", re.I),
        "not tied to a single AI gateway",
    ),
    (
        re.compile(r"Not a Bifrost plugin", re.I),
        "Not tied to a single AI gateway",
    ),
    (
        re.compile(r"Bifrost-as-identity"),
        "Single-gateway-as-identity",
    ),
    (
        re.compile(r"Bifrost aliases"),
        "gateway aliases",
    ),
    (
        re.compile(r"\+ Bifrost"),
        "+ optional gateway",
    ),
    (
        re.compile(r"grammar \+ Bifrost"),
        "grammar + optional gateway",
    ),
    (
        re.compile(r"\bBifrost\b"),
        "the AI gateway",
    ),
    # Cursor product on public pages → generic editor
    (
        re.compile(r"VS Code / Cursor"),
        "VS Code-compatible editors",
    ),
    (
        re.compile(r"Cursor / VS Code"),
        "VS Code-compatible editors",
    ),
    (
        re.compile(r"Cursor or VS Code"),
        "a VS Code-compatible editor",
    ),
    (
        re.compile(r"in Cursor/`make ide`"),
        "in the local editor / `make ide`",
    ),
    (
        re.compile(r"interim Cursor workspace"),
        "interim editor workspace",
    ),
    (
        re.compile(r"interim Cursor optional"),
        "interim editor optional",
    ),
    (
        re.compile(r"interim Cursor editor"),
        "interim editor",
    ),
    (
        re.compile(r"Cursor workspace"),
        "editor workspace",
    ),
    (
        re.compile(r"Cursor host"),
        "editor host",
    ),
    (
        re.compile(r"opens Cursor on"),
        "opens the editor on",
    ),
    (
        re.compile(r"Open the Cursor workspace"),
        "Open the editor workspace",
    ),
    (
        re.compile(r"Cursor Override"),
        "Editor model override",
    ),
    (
        re.compile(r"\bCursor\b"),
        "the local IDE",
    ),
    # never-6000 mantra spam (keep substantive GPU policy elsewhere)
    (
        re.compile(r"Never 6000\.?\s*", re.I),
        "",
    ),
    (
        re.compile(r"never 6000\.?\s*", re.I),
        "",
    ),
    (
        re.compile(r"\*\*Never\*\*\s+6000\.?\s*", re.I),
        "",
    ),
    (
        re.compile(r"/ GPU-1\.?\s*"),
        "",
    ),

    # --- imperative agent/ops voice → product reference ---
    (
        re.compile(
            r"Do\s+\*\*not\*\*\s+treat a shadow as a richer ISA\.\s*"
            r"If GAS and bootstrap\s*disagree, bootstrap wins for "
            r"`\.sparkbc`\.",
            re.I,
        ),
        "Shadows are helpers only — they do not define a richer ISA. "
        "`.sparkbc` follows the bootstrap ISA; when GAS and bootstrap "
        "disagree, bootstrap is authoritative.",
    ),
    (
        re.compile(
            r"Do\s+<strong>not</strong>\s+treat a shadow as a richer "
            r"ISA\.\s*"
            r"If GAS and bootstrap\s*disagree, bootstrap wins for "
            r"<code class=\"inline-code\">\.sparkbc</code>\.",
            re.I,
        ),
        "Shadows are helpers only — they do not define a richer ISA. "
        '<code class="inline-code">.sparkbc</code> follows the '
        "bootstrap ISA; when GAS and bootstrap disagree, bootstrap "
        "is authoritative.",
    ),
    (
        re.compile(r"(?i)Do not treat GAS as forever SoT; do not start"),
        "GAS is a current path, not forever SoT; do not start",
    ),
    (
        re.compile(r"(?i)Do not treat model output as policy\.?"),
        "Model output is not policy.",
    ),
    (
        re.compile(r"(?i)Do not treat OpenBin output as verified Spark recovery\.?"),
        "OpenBin output is not verified Spark recovery.",
    ),
    (
        re.compile(r"(?i)never treat .it recompiled. as SPARK_BC truth\.?"),
        "a successful recompile is not SPARK_BC truth by itself.",
    ),
    (
        re.compile(r"(?i)Never treat `code-hard` as Sonnet\.?"),
        "`code-hard` is not Sonnet.",
    ),
    (
        re.compile(r"(?i)Do not invent or print tokens\.?"),
        "Tokens stay in local config — not printed here.",
    ),
    (
        re.compile(r"(?i)— do not invent or print tokens\.?"),
        "— tokens stay in local config.",
    ),
    (
        re.compile(r"(?i)do not invent that token\.?"),
        "only proven tokens apply.",
    ),
    (
        re.compile(r"(?i)\(real — do not invent others\):"),
        "(proven script tokens only):",
    ),
    (
        re.compile(r"(?i)Proven script tokens \(real — do not invent others\):"),
        "Proven script tokens:",
    ),
    (
        re.compile(r"(?i)Do not invent hashes — cite"),
        "Hashes come from",
    ),
    (
        re.compile(r"(?i); do not invent hex\.?"),
        ".",
    ),
    (
        re.compile(r"(?i), do not invent\.?"),
        ".",
    ),
    (
        re.compile(r"(?i); do not invent counts — read the file"),
        " — read counts from the file",
    ),
    (
        re.compile(r"(?i); do not invent a 3B claim\.?"),
        ".",
    ),
    (
        re.compile(r"(?i)Do not invent a context-window size for production marketing — read"),
        "Context-window size for marketing comes from",
    ),
    (
        re.compile(r"(?i)Do not invent live vision\.?"),
        "Live vision is not shipping yet.",
    ),
    (
        re.compile(r"(?i)do not invent Spark scores"),
        "Spark scores are listed only when measured",
    ),
    (
        re.compile(r"(?i)do not invent new reply prose\)"),
        "reply prose comes from the pack)",
    ),
    (
        re.compile(r"(?i)Do not invent a label-list operand\.?"),
        "There is no label-list operand.",
    ),
    (
        re.compile(r"(?i)Do not invent a signature operand\.?"),
        "There is no signature operand.",
    ),
    (
        re.compile(r"(?i)do not invent routing\.?"),
        "routing follows ASK_LIVE.",
    ),
    (
        re.compile(r"(?i)Do not invent more\.?"),
        "Additional surface area is not implied.",
    ),
    (
        re.compile(r"(?i)examples; do not invent:"),
        "examples:",
    ),
    (
        re.compile(r"(?i)Do not invent token/cost numbers in release notes\.?"),
        "Release notes use measured token/cost figures only.",
    ),
    (
        re.compile(r"(?i)do not claim Hub publish\)"),
        "Hub publish not wired)",
    ),
    (
        re.compile(r"(?i)Do not claim FineWeb-scale data\.?"),
        "Training data is not FineWeb-scale.",
    ),
    (
        re.compile(r"(?i)Do not claim LoRA or voice-GPU training on sparklang\.dev\.?"),
        "Public docs describe the CPU train methods that ship.",
    ),
    (
        re.compile(r"(?i)Do not claim Stages 4–5 until those gates have"),
        "Stages 4–5 stay unclaimed until gates have",
    ),
    (
        re.compile(r"(?i)— do not claim"),
        "— avoid claiming",
    ),
    (
        re.compile(r"(?i)Never claim an LLM perfectly decompiles SPARK_BC\.?"),
        "Perfect SPARK_BC LLM decompile is out of scope.",
    ),
    (
        re.compile(r"(?i)\*\*Never\*\* claim an LLM perfectly decompiles SPARK_BC\.?"),
        "Perfect SPARK_BC LLM decompile is out of scope.",
    ),
    (
        re.compile(r"(?i)Never claim .we trained on Llama-70B. from fixtures or smoke\.?"),
        "Fixture or smoke runs do not imply Llama-70B training.",
    ),
    (
        re.compile(r"(?i)Never commit keys\. Never route coding to voice GPU aliases\.?"),
        "Keep keys out of git. Coding routes stay on coding GPUs.",
    ),
    (
        re.compile(r"(?i)Never route Spark compute to voice / `:8010` / reserved voice GPU\.?"),
        "Spark compute stays off the reserved voice GPU path.",
    ),
    (
        re.compile(r"(?i)Training never routes to reserved voice GPUs\.?"),
        "Training uses CPU or a consumer GPU.",
    ),
    (
        re.compile(r"(?i)Never `voice` / `local-big`\.?"),
        "Skip `voice` / `local-big` aliases for this path.",
    ),
    (
        re.compile(r"(?i)reuses real `spark-engine-show`"),
        "reuses `spark-engine-show`",
    ),
    (
        re.compile(r"(?i)reuses real <code class=\"inline-code\">spark-engine-show</code>"),
        'reuses <code class="inline-code">spark-engine-show</code>',
    ),
    (
        re.compile(r"(?i)Submit a real Spark model train job"),
        "Submit a Spark model train job",
    ),
    (
        re.compile(r"(?i)maps to real Spark syntax"),
        "maps to Spark syntax",
    ),
    (
        re.compile(r"(?i)Real `mmap`"),
        "`mmap`",
    ),
    (
        re.compile(r"(?i)May explain a real dump"),
        "May explain a dump",
    ),
    (
        re.compile(r"(?i)Real SPARK_BC bytes:"),
        "SPARK_BC bytes:",
    ),

]

SKIP_SUFFIX_CODE = {
    ".py",
    ".c",
    ".h",
    ".s",
    ".rs",
    ".go",
}
# Keep eval JSON field in code; scrub prose/docs/site only.
SKIP_DIRS = {
    ".git",
    "node_modules",
    "out",
    ".wrangler",
    "__pycache__",
    "python",  # harness code is not prose
    "asm",
    "bootstrap",
    "sparkasm",
}


def scrub_text(text: str, *, path: Path) -> str:
    """Apply ordered replacements; JSON field names pass through."""
    pairs = list(REPLACEMENTS)
    if path.suffix in {".json", ".jsonl"}:
        # Keep harness / scoreboard field names; only scrub prose strings
        # already covered by earlier phrase patterns.
        pairs = [
            (rx, repl)
            for rx, repl in pairs
            if "beats_claude" not in rx.pattern
            and rx.pattern != r"beats_claude"
        ]
        # Drop the last-resort bare beats_claude → claim
        pairs = [
            (rx, repl)
            for rx, repl in pairs
            if rx.pattern.lower() != r"beats_claude"
        ]
    for rx, repl in pairs:
        text = rx.sub(repl, text)
    # Do not collapse horizontal whitespace — that merges markdown
    # headings into prior paragraphs.
    return text


def should_touch(path: Path) -> bool:
    """Whether path is a public prose/asset scrub target."""
    if any(p in SKIP_DIRS for p in path.parts):
        return False
    if path.suffix in SKIP_SUFFIX_CODE:
        return False
    if path.suffix in {
        ".md",
        ".html",
        ".svg",
        ".json",
        ".spark",
        ".txt",
        ".js",
        ".jsonl",
    }:
        return True
    return False


def main() -> int:
    """Scrub public paths; print before/after summary."""
    targets = [
        ROOT / "docs",
        ROOT / "website",
        ROOT / "examples",
        ROOT / "tools" / "spark-ide-extension",
        ROOT / "README.md",
        ROOT / "CHANGELOG.md",
        ROOT / "shadows",
        ROOT / "helpers" / "README.md",
        ROOT / "models" / "spark-coder" / "README.md",
        ROOT / "models" / "spark-voice-easy" / "README.md",
    ]
    files: list[Path] = []
    for t in targets:
        if t.is_file():
            files.append(t)
        elif t.is_dir():
            for p in t.rglob("*"):
                if p.is_file() and should_touch(p):
                    files.append(p)

    changed = 0
    print(f"scrub_targets {len(files)}", flush=True)
    for path in sorted(files):
        try:
            raw = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        new = scrub_text(raw, path=path)
        if new != raw:
            path.write_text(new, encoding="utf-8")
            changed += 1
            print("scrubbed", path.relative_to(ROOT), flush=True)
    print("files_changed", changed, flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
