#include "dry_auto_model.h"
#include <stddef.h>

/* Deprecated: SparkLang does not pick Bifrost-style aliases.
 * Kept as a no-op symbol for leftover link sites.
 */
const char *spark_resolve_auto_model(const char *stmt, const char *prompt)
{
  (void)stmt;
  (void)prompt;
  return NULL;
}
