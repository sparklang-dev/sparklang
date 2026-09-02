#include "dry_auto_model.h"
#include <stddef.h>
#include <string.h>
static int contains_ci(const char *hay, const char *needle) {
  size_t nlen, hlen, i, j;
  if (!hay || !needle || !needle[0]) return 0;
  nlen = strlen(needle); hlen = strlen(hay);
  if (nlen > hlen) return 0;
  for (i = 0; i + nlen <= hlen; i++) {
    for (j = 0; j < nlen; j++) {
      char a = hay[i + j], b = needle[j];
      if (a >= 'A' && a <= 'Z') a = (char)(a + 32);
      if (b >= 'A' && b <= 'Z') b = (char)(b + 32);
      if (a != b) break;
    }
    if (j == nlen) return 1;
  }
  return 0;
}
static int stmt_wants_code(const char *stmt) {
  if (!stmt) return 0;
  if (contains_ci(stmt, "review") || contains_ci(stmt, "builder") ||
      contains_ci(stmt, "implement")) return 1;
  if (contains_ci(stmt, "tool ") || contains_ci(stmt, "with tools")) return 1;
  return 0;
}
static int text_wants_code(const char *text) {
  static const char *needles[] = {
    "fix", "test failure", "unit test", "write test", "refactor", "rename",
    "endpoint", "api", "debug", "error message", "error:", "patch",
    "edit file", "implement", "add route", "stack trace", "assertion",
    "def test_", ".spark", ".js", ".py", "file path", NULL};
  size_t i;
  if (!text) return 0;
  for (i = 0; needles[i]; i++)
    if (contains_ci(text, needles[i])) return 1;
  return 0;
}
const char *spark_resolve_auto_model(const char *stmt, const char *prompt) {
  if (stmt_wants_code(stmt) || text_wants_code(stmt) || text_wants_code(prompt))
    return "code";
  return "fast";
}
