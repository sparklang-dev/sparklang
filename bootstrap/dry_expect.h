#ifndef SPARK_DRY_EXPECT_H
#define SPARK_DRY_EXPECT_H

/* Expect equal/contains — LANGUAGE.md. Pass = 0, fail = 1 (loud).
 * Fixture want-path is fopen'd; missing file fails. No invented values. */

#include <stddef.h>

/* Load want from a fixture path into *out (malloc'd). 0 ok, 1 miss. */
int spark_expect_load_fixture(const char *path, char **out,
			      size_t *out_len);

/* Compare got vs want.
 * mode: "equal" or "contains"
 * Returns 0 pass, 1 fail (prints error: expect … to stderr).
 * On pass prints "[expect] pass <mode> <name>" to stdout. */
int spark_expect_check(const char *mode, const char *name,
		       const char *got, const char *want);

/* Parse an expect statement line.
 * Forms:
 *   expect equal NAME "literal"
 *   expect contains NAME "literal"
 *   expect equal NAME fixture "path"
 *   expect contains NAME fixture "path"
 * Writes mode/name into caller buffers; *want_out is malloc'd literal
 * or fixture path; *want_is_fixture is 1 when fixture form.
 * Returns 0 ok, 1 parse error (stderr). */
int spark_expect_parse_stmt(const char *stmt, char *mode, size_t mode_n,
			    char *name, size_t name_n, char **want_out,
			    int *want_is_fixture);

#endif
