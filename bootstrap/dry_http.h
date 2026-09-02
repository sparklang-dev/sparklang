#ifndef SPARK_DRY_HTTP_H
#define SPARK_DRY_HTTP_H

/* Dry-run HTTP: read real fixture files only. Fail loud if missing.
 * No network. No invented status codes — fixture bytes are the body. */

#include <stddef.h>

/* Load fixture path into *out (malloc'd). Returns 0 ok, 1 missing/error.
 * On error, prints to stderr and leaves *out NULL. */
int spark_http_load_fixture(const char *path, char **out, size_t *out_len);

/* Resolve dry fixture path from URL + optional fixture= clause.
 * file:// and examples/fixtures/http/… URLs may omit fixture=.
 * Writes path into buf. Returns 0 ok, 1 fail loud (stderr). */
int spark_http_resolve_dry_fixture(const char *url, const char *fixture,
				   char *buf, size_t buflen);

#endif
