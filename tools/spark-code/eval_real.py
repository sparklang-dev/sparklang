#!/usr/bin/env python3
"""Real coding eval for the self-hosted product coder (30B).

Runs real programming tasks against the local Qwen3-Coder-30B
vLLM endpoint (default http://127.0.0.1:8003, env SPARK_CODER_URL)
and grades by **execution**: generated code must actually run and
pass asserts / produce expected stdout / exit codes in a sandboxed
subprocess. No toy next-byte accuracy. No fabricated numbers —
when the endpoint is down this says so and exits nonzero (3).

Task mix: prompts derived from the repo's authored coding fixtures
(examples/fixtures/coder/) plus held-out function-completion,
bug-fix, and explain-code tasks.

Usage:
    python3 tools/spark-code/eval_real.py [--out PATH] [--url URL]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))

from sparklang.spark_coder.real_coder import (
    generate as real_generate,
    probe_endpoint,
)

EXIT_ENDPOINT_DOWN = 3
EXEC_TIMEOUT_S = 15

CODE_SYSTEM = (
    "You are an expert Python programmer. Respond with exactly one "
    "```python code block containing the complete solution and no "
    "other text. Do not include example usage or prints unless the "
    "task asks for them."
)

# ------------------------------------------------------------------
# Tasks. kinds:
#   function_completion — write a function; graded by asserts
#   bug_fix             — fix given buggy code; graded by asserts
#   program             — whole program; graded by stdout/exit code
#   explain_code        — predict stdout; graded by running snippet
# ------------------------------------------------------------------

TASKS: list[dict[str, Any]] = [
    # --- derived from examples/fixtures/coder/dataset.jsonl ---
    {
        "id": "fixture_exit42",
        "kind": "program",
        "origin": "fixture: sparkasm exit 42",
        "prompt": (
            "Write a complete Python program that exits with "
            "status code 42."
        ),
        "expect_exit": 42,
    },
    {
        "id": "fixture_hello_spark",
        "kind": "program",
        "origin": "fixture: print hello spark",
        "prompt": (
            "Write a complete Python program that prints exactly "
            "this line and nothing else:\nhello from spark-coder"
        ),
        "expect_stdout": "hello from spark-coder",
    },
    {
        "id": "fixture_opcode_toggle",
        "kind": "function_completion",
        "origin": "fixture: opcode TRAIN -> STEP",
        "prompt": (
            "Write a Python function `def next_opcode(op: str) -> "
            "str` that returns \"STEP\" when op is \"TRAIN\" and "
            "\"TRAIN\" when op is \"STEP\"."
        ),
        "tests": (
            "assert next_opcode('TRAIN') == 'STEP'\n"
            "assert next_opcode('STEP') == 'TRAIN'\n"
        ),
    },
    {
        "id": "fixture_train_step_targets",
        "kind": "function_completion",
        "origin": "fixture: write TRAIN then STEP program",
        "prompt": (
            "Spark model lines end with an arrow target, e.g.:\n"
            "model train dataset \"d.jsonl\" base \"coder\" out "
            "\"out/x\" -> job\nmodel step \"coder-001\" -> step\n"
            "Write a Python function `def extract_targets(text: "
            "str) -> list[str]` returning the word after '->' for "
            "each line, in order."
        ),
        "tests": (
            "t = 'model train dataset \"d\" -> job\\n"
            "model step \"coder-001\" -> step\\n'\n"
            "assert extract_targets(t) == ['job', 'step']\n"
            "assert extract_targets('no arrow here') == []\n"
        ),
    },
    {
        "id": "fixture_sparkasm_explain",
        "kind": "explain_code",
        "origin": "fixture: mov rax, 60 / mov rdi, 42",
        "snippet": (
            "rax = 60  # exit syscall number\n"
            "rdi = 42  # exit code\n"
            "print(rdi - (rax - 60))\n"
        ),
    },
    # --- held-out function completion ---
    {
        "id": "fc_fizzbuzz",
        "kind": "function_completion",
        "prompt": (
            "Write a Python function `def fizzbuzz(n: int) -> str` "
            "returning \"FizzBuzz\" for multiples of 15, \"Fizz\" "
            "for multiples of 3, \"Buzz\" for multiples of 5, else "
            "str(n)."
        ),
        "tests": (
            "assert fizzbuzz(15) == 'FizzBuzz'\n"
            "assert fizzbuzz(3) == 'Fizz'\n"
            "assert fizzbuzz(5) == 'Buzz'\n"
            "assert fizzbuzz(7) == '7'\n"
            "assert fizzbuzz(30) == 'FizzBuzz'\n"
        ),
    },
    {
        "id": "fc_reverse_words",
        "kind": "function_completion",
        "prompt": (
            "Write a Python function `def reverse_words(s: str) "
            "-> str` that reverses the order of whitespace-separated"
            " words, collapsing runs of whitespace to one space."
        ),
        "tests": (
            "assert reverse_words('hello spark world') == "
            "'world spark hello'\n"
            "assert reverse_words('  a   b ') == 'b a'\n"
            "assert reverse_words('') == ''\n"
        ),
    },
    {
        "id": "fc_is_palindrome",
        "kind": "function_completion",
        "prompt": (
            "Write a Python function `def is_palindrome(s: str) "
            "-> bool` that ignores case and non-alphanumeric "
            "characters."
        ),
        "tests": (
            "assert is_palindrome('A man, a plan, a canal: "
            "Panama')\n"
            "assert is_palindrome('racecar')\n"
            "assert not is_palindrome('spark')\n"
            "assert is_palindrome('')\n"
        ),
    },
    {
        "id": "fc_flatten",
        "kind": "function_completion",
        "prompt": (
            "Write a Python function `def flatten(nested: list) "
            "-> list` that flattens exactly one level of nesting."
        ),
        "tests": (
            "assert flatten([[1, 2], [3], []]) == [1, 2, 3]\n"
            "assert flatten([[1, [2]], [3]]) == [1, [2], 3]\n"
            "assert flatten([]) == []\n"
        ),
    },
    {
        "id": "fc_count_vowels",
        "kind": "function_completion",
        "prompt": (
            "Write a Python function `def count_vowels(s: str) "
            "-> int` counting a/e/i/o/u, case-insensitive."
        ),
        "tests": (
            "assert count_vowels('spark') == 1\n"
            "assert count_vowels('AEIOU') == 5\n"
            "assert count_vowels('xyz') == 0\n"
            "assert count_vowels('') == 0\n"
        ),
    },
    {
        "id": "fc_dedupe_keep_order",
        "kind": "function_completion",
        "prompt": (
            "Write a Python function `def dedupe(xs: list) -> "
            "list` removing duplicates while keeping first "
            "occurrence order."
        ),
        "tests": (
            "assert dedupe([3, 1, 3, 2, 1]) == [3, 1, 2]\n"
            "assert dedupe([]) == []\n"
            "assert dedupe(['b', 'a', 'b']) == ['b', 'a']\n"
        ),
    },
    {
        "id": "fc_sum_even_squares",
        "kind": "function_completion",
        "prompt": (
            "Write a Python function `def sum_even_squares(nums: "
            "list[int]) -> int` returning the sum of squares of "
            "the even numbers."
        ),
        "tests": (
            "assert sum_even_squares([1, 2, 3, 4]) == 20\n"
            "assert sum_even_squares([]) == 0\n"
            "assert sum_even_squares([2]) == 4\n"
        ),
    },
    # --- held-out bug fix ---
    {
        "id": "bf_binary_search_off_by_one",
        "kind": "bug_fix",
        "prompt": (
            "This binary search has an off-by-one bug and can "
            "loop forever or miss elements. Return the fixed "
            "function.\n\n```python\ndef index_of(xs, target):\n"
            "    lo, hi = 0, len(xs)\n"
            "    while lo <= hi:\n"
            "        mid = (lo + hi) // 2\n"
            "        if xs[mid] == target:\n"
            "            return mid\n"
            "        if xs[mid] < target:\n"
            "            lo = mid\n"
            "        else:\n"
            "            hi = mid\n"
            "    return -1\n```"
        ),
        "tests": (
            "assert index_of([1, 3, 5, 7], 5) == 2\n"
            "assert index_of([1, 3, 5, 7], 1) == 0\n"
            "assert index_of([1, 3, 5, 7], 7) == 3\n"
            "assert index_of([1, 3, 5, 7], 4) == -1\n"
            "assert index_of([], 1) == -1\n"
        ),
    },
    {
        "id": "bf_mutable_default",
        "kind": "bug_fix",
        "prompt": (
            "This function leaks state between calls because of a "
            "mutable default argument. Return the fixed "
            "function.\n\n```python\ndef collect(item, box=[]):\n"
            "    box.append(item)\n"
            "    return box\n```"
        ),
        "tests": (
            "assert collect(1) == [1]\n"
            "assert collect(2) == [2]\n"
            "assert collect(1, [9]) == [9, 1]\n"
        ),
    },
    {
        "id": "bf_mean_empty",
        "kind": "bug_fix",
        "prompt": (
            "This mean function crashes on empty input. Return the "
            "fixed function; mean of no values must be 0.0.\n\n"
            "```python\ndef mean(xs):\n"
            "    return sum(xs) / len(xs)\n```"
        ),
        "tests": (
            "assert mean([2, 4]) == 3.0\n"
            "assert mean([]) == 0.0\n"
            "assert mean([5]) == 5.0\n"
        ),
    },
    # --- held-out explain code (execution-graded) ---
    {
        "id": "ec_list_comp",
        "kind": "explain_code",
        "snippet": "print([x * x for x in range(5) if x % 2])\n",
    },
    {
        "id": "ec_slice",
        "kind": "explain_code",
        "snippet": 's = "sparklang"\nprint(s[1:6:2])\n',
    },
    {
        "id": "ec_dict_sum",
        "kind": "explain_code",
        "snippet": 'd = {"a": 1, "b": 2}\nprint(sum(d.values()))\n',
    },
]


def extract_code(text: str) -> str:
    """Pull the first fenced code block; fall back to raw text."""
    m = re.search(
        r"```(?:python|py)?\s*\n(.*?)```", text, re.DOTALL
    )
    if m:
        return m.group(1).strip() + "\n"
    return text.strip() + "\n"


def _sandbox_limits() -> None:
    """Best-effort POSIX rlimits for the child process."""
    try:
        import resource

        resource.setrlimit(resource.RLIMIT_CPU, (10, 10))
        resource.setrlimit(
            resource.RLIMIT_AS, (1024**3, 1024**3)
        )
    except (ImportError, ValueError, OSError):
        pass


def run_python(
    program: str, *, timeout: int = EXEC_TIMEOUT_S
) -> dict[str, Any]:
    """Run Python source in an isolated, time-boxed subprocess."""
    with tempfile.TemporaryDirectory(prefix="spark-eval-") as tmp:
        env = {"PATH": os.environ.get("PATH", "")}
        try:
            proc = subprocess.run(
                [sys.executable, "-I", "-c", program],
                capture_output=True,
                text=True,
                timeout=timeout,
                cwd=tmp,
                env=env,
                preexec_fn=_sandbox_limits,
                check=False,
            )
        except subprocess.TimeoutExpired:
            return {
                "ok": False,
                "error": "timeout",
                "timeout_s": timeout,
            }
        return {
            "ok": proc.returncode == 0,
            "returncode": proc.returncode,
            "stdout": (proc.stdout or "").strip(),
            "stderr": (proc.stderr or "")[-500:],
        }


def grade(task: dict[str, Any], completion: str) -> dict[str, Any]:
    """Execution-grade one completion. Never lenient, never fake."""
    kind = task["kind"]
    if kind == "explain_code":
        truth = run_python(task["snippet"])
        if not truth["ok"]:
            return {
                "pass": False,
                "error": "fixture snippet failed to run",
                "detail": truth,
            }
        answer = extract_code(completion).strip()
        expected = truth["stdout"].strip()
        return {
            "pass": answer == expected,
            "expected": expected,
            "got": answer[:200],
        }
    code = extract_code(completion)
    if kind in ("function_completion", "bug_fix"):
        program = code + "\n" + task["tests"]
        run = run_python(program)
        return {
            "pass": run["ok"],
            "returncode": run.get("returncode"),
            "stderr": run.get("stderr", ""),
        }
    if kind == "program":
        run = run_python(code)
        ok = True
        if "expect_exit" in task:
            ok = run.get("returncode") == task["expect_exit"]
        if "expect_stdout" in task:
            ok = (
                ok
                and run.get("stdout", "").strip()
                == task["expect_stdout"]
            )
        return {
            "pass": ok,
            "returncode": run.get("returncode"),
            "stdout": run.get("stdout", "")[:200],
            "stderr": run.get("stderr", ""),
        }
    return {"pass": False, "error": "unknown kind %s" % kind}


def _prompt_for(task: dict[str, Any]) -> tuple[str, str]:
    """(system, user) prompt pair for one task."""
    if task["kind"] == "explain_code":
        user = (
            "What does this Python snippet print? Reply with ONLY "
            "the exact stdout inside a single ``` code block.\n\n"
            "```python\n" + task["snippet"] + "```"
        )
        system = (
            "You are a precise Python interpreter. Answer with the "
            "exact program output only."
        )
    else:
        user = task["prompt"]
        system = CODE_SYSTEM
    return system, user


def run_eval(
    *,
    url: str | None,
    max_tokens: int,
    timeout: float,
    only: set[str] | None,
) -> dict[str, Any]:
    """Run every task against the live endpoint; grade by exec."""
    started = time.time()
    probe = probe_endpoint(url)
    if not probe.get("ok"):
        return {
            "ok": False,
            "status": "skipped",
            "reason": "endpoint_down",
            "endpoint": probe.get("endpoint"),
            "detail": probe.get("detail"),
            "hint": probe.get("hint"),
            "note": (
                "no numbers reported — eval never fabricates "
                "results when the self-hosted coder is down"
            ),
        }
    rows: list[dict[str, Any]] = []
    for task in TASKS:
        if only and task["id"] not in only:
            continue
        system, user = _prompt_for(task)
        t0 = time.time()
        gen = real_generate(
            user,
            url=url,
            system=system,
            max_tokens=max_tokens,
            temperature=0.0,
            timeout=timeout,
        )
        latency = round(time.time() - t0, 2)
        row: dict[str, Any] = {
            "id": task["id"],
            "kind": task["kind"],
            "latency_s": latency,
        }
        if not gen.get("ok"):
            row["pass"] = False
            row["error"] = gen.get("error")
        else:
            verdict = grade(task, str(gen.get("completion") or ""))
            row["pass"] = bool(verdict.get("pass"))
            row["grader"] = {
                k: v
                for k, v in verdict.items()
                if k != "pass"
            }
            row["usage"] = gen.get("usage")
        rows.append(row)
    passed = sum(1 for r in rows if r["pass"])
    total = len(rows)
    by_kind: dict[str, dict[str, int]] = {}
    for row in rows:
        bucket = by_kind.setdefault(
            row["kind"], {"total": 0, "passed": 0}
        )
        bucket["total"] += 1
        bucket["passed"] += 1 if row["pass"] else 0
    return {
        "ok": True,
        "eval": "spark-coder-real",
        "endpoint": probe["endpoint"],
        "model": probe.get("model"),
        "started_at": datetime.now(timezone.utc).isoformat(),
        "duration_s": round(time.time() - started, 2),
        "grading": (
            "execution: generated code runs in a sandboxed "
            "subprocess; pass = asserts pass / exact stdout / "
            "exit code"
        ),
        "tasks": rows,
        "summary": {
            "total": total,
            "passed": passed,
            "failed": total - passed,
            "pass_at_1": round(passed / float(total), 4)
            if total
            else 0.0,
            "by_kind": by_kind,
        },
    }


def self_test() -> dict[str, Any]:
    """Validate graders with canned completions (no endpoint).

    Proves the harness mechanics (extract → sandbox → grade) work.
    These are harness checks, not model numbers.
    """
    checks: list[dict[str, Any]] = []
    good_code = "```python\ndef fizzbuzz(n):\n    return str(n)\n```"
    fc = next(t for t in TASKS if t["id"] == "fc_fizzbuzz")
    # Known-wrong must fail; a correct solution must pass.
    wrong = grade(fc, good_code)
    checks.append({"check": "fc_wrong_fails", "pass": not wrong["pass"]})
    right_src = (
        "```python\ndef fizzbuzz(n):\n"
        "    if n % 15 == 0:\n        return 'FizzBuzz'\n"
        "    if n % 3 == 0:\n        return 'Fizz'\n"
        "    if n % 5 == 0:\n        return 'Buzz'\n"
        "    return str(n)\n```"
    )
    right = grade(fc, right_src)
    checks.append({"check": "fc_right_passes", "pass": right["pass"]})
    prog = next(t for t in TASKS if t["id"] == "fixture_exit42")
    ok_prog = grade(prog, "```python\nimport sys\nsys.exit(42)\n```")
    checks.append({"check": "program_exit42", "pass": ok_prog["pass"]})
    ec = next(t for t in TASKS if t["id"] == "ec_dict_sum")
    ok_ec = grade(ec, "```\n3\n```")
    bad_ec = grade(ec, "```\n42\n```")
    checks.append({"check": "explain_right", "pass": ok_ec["pass"]})
    checks.append(
        {"check": "explain_wrong_fails", "pass": not bad_ec["pass"]}
    )
    return {
        "ok": all(c["pass"] for c in checks),
        "self_test": True,
        "checks": checks,
        "note": "harness mechanics only — no model involved",
    }


def main(argv: list[str] | None = None) -> int:
    """CLI entry for the real coder eval."""
    ap = argparse.ArgumentParser(
        description=(
            "Execution-graded eval against the self-hosted "
            "Qwen3-Coder-30B endpoint. Exits 3 when the endpoint "
            "is down (never fakes numbers)."
        )
    )
    ap.add_argument("--url", default="", help="endpoint URL")
    ap.add_argument(
        "--out",
        default="out/spark-coder/eval_real.json",
        help="where to write the JSON results",
    )
    ap.add_argument("--max-tokens", type=int, default=1024)
    ap.add_argument("--timeout", type=float, default=180.0)
    ap.add_argument(
        "--tasks",
        default="",
        help="comma-separated task ids to run (default: all)",
    )
    ap.add_argument(
        "--self-test",
        action="store_true",
        help="validate graders with canned completions (no endpoint)",
    )
    args = ap.parse_args(argv)
    if args.self_test:
        result = self_test()
        print(json.dumps(result, indent=2))
        return 0 if result["ok"] else 1
    only = (
        {t.strip() for t in args.tasks.split(",") if t.strip()}
        or None
    )
    result = run_eval(
        url=args.url or None,
        max_tokens=args.max_tokens,
        timeout=args.timeout,
        only=only,
    )
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        json.dumps(result, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(result, indent=2))
    if not result.get("ok"):
        return EXIT_ENDPOINT_DOWN
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
