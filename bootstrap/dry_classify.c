/* Exact dry fixtures from bootstrap/vm.c pick_classify
 * (same as asm/spark.s pick_classify_ptr). No new labels. */
#include "dry_classify.h"

#include <stddef.h>
#include <string.h>

static const char DRY_SUPPORT[] =
    "{\"label\":\"support\",\"confidence\":0.91,"
    "\"reasons\":[\"dry-run\"]}";
static const char DRY_SALES[] =
    "{\"label\":\"sales\",\"confidence\":0.88,"
    "\"reasons\":[\"dry-run\"]}";
static const char DRY_SPAM[] =
    "{\"label\":\"spam\",\"confidence\":0.95,"
    "\"reasons\":[\"dry-run\"]}";

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

const char *spark_pick_classify(const char *text)
{
  if (contains_ci(text, "buy") || contains_ci(text, "price"))
    return DRY_SALES;
  if (contains_ci(text, "broken") || contains_ci(text, "help") ||
      contains_ci(text, "support"))
    return DRY_SUPPORT;
  if (contains_ci(text, "spam"))
    return DRY_SPAM;
  return DRY_SUPPORT;
}
