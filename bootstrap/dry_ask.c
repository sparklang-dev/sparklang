/* Exact dry fixtures from bootstrap/vm.c pick_ask_reply
 * (same as asm/spark.s pick_ask_reply_ptr). No new prose. */
#include "dry_ask.h"

#include <stddef.h>
#include <string.h>

/* GAS contains: case-insensitive ASCII substring (vm.c). */
static int contains_ci(const char *hay, const char *needle)
{
  size_t nlen;
  size_t hlen;
  size_t i;
  size_t j;
  if (!hay || !needle || !needle[0])
    return 0;
  nlen = strlen(needle);
  hlen = strlen(hay);
  if (nlen > hlen)
    return 0;
  for (i = 0; i + nlen <= hlen; i++) {
    for (j = 0; j < nlen; j++) {
      char a = hay[i + j];
      char b = needle[j];
      if (a >= 'A' && a <= 'Z')
        a = (char)(a + 32);
      if (b >= 'A' && b <= 'Z')
        b = (char)(b + 32);
      if (a != b)
        break;
    }
    if (j == nlen)
      return 1;
  }
  return 0;
}

const char *spark_pick_ask_reply(const char *prompt)
{
  if (contains_ci(prompt, "gravity"))
    return "Gravity pulls masses together.";
  if (contains_ci(prompt, "spanish") || contains_ci(prompt, "translate"))
    return "Resumen en español (dry-run).";
  if (contains_ci(prompt, "summar"))
    return "Summary: dry-run summary of the document.";
  if (contains_ci(prompt, "reply") || contains_ci(prompt, "helpfully"))
    return "Happy to help — what do you need?";
  if (contains_ci(prompt, "intent") || contains_ci(prompt, "classify"))
    return "{\"label\":\"support\",\"confidence\":0.91}";
  if (contains_ci(prompt, "json") || contains_ci(prompt, "extract"))
    return "{\"name\":\"Ada Lovelace\",\"age\":36}";
  if (contains_ci(prompt, "weather"))
    return "Dry-run: partly cloudy, 72°F in Springfield.";
  if (contains_ci(prompt, "one sentence") || contains_ci(prompt, "explain"))
    return "Gravity pulls masses together.";
  if (contains_ci(prompt, "test failure") || contains_ci(prompt, "fix this"))
    return "Fix: update assertion in test_add.";
  if (contains_ci(prompt, "endpoint") || contains_ci(prompt, "/health"))
    return "Plan: add GET /health returning {\"status\":\"ok\"}.";
  if (contains_ci(prompt, "rename") || contains_ci(prompt, "refactor"))
    return "Rename consistently: foo → bar across module.";
  if (contains_ci(prompt, "unit test") || contains_ci(prompt, "write a test"))
    return "def test_add(): assert add(1, 2) == 3";
  if (contains_ci(prompt, "debug") && contains_ci(prompt, "error"))
    return "Hint: check stack trace line 42 — undefined is not a function.";
  return "[dry-run] model response";
}
