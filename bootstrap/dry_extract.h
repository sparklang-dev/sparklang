/* Typed extract — schema parse + fixture validation. LANGUAGE.md.
 * Reads fixture files from disk; never invents a field value. */
#ifndef SPARK_DRY_EXTRACT_H
#define SPARK_DRY_EXTRACT_H

#include <stddef.h>

#define SPARK_EXTRACT_MAX_FIELDS 32
#define SPARK_EXTRACT_NAME_MAX 64

enum spark_extract_type {
	SPARK_X_STRING = 0,
	SPARK_X_INT,
	SPARK_X_FLOAT,
	SPARK_X_BOOL
};

struct spark_extract_field {
	char name[SPARK_EXTRACT_NAME_MAX];
	enum spark_extract_type type;
	int optional;
};

struct spark_extract_schema {
	char name[SPARK_EXTRACT_NAME_MAX];
	struct spark_extract_field fields[SPARK_EXTRACT_MAX_FIELDS];
	size_t n_fields;
};

/* Type name as written in the schema ("string", "int", ...). */
const char *spark_extract_type_name(enum spark_extract_type t);

/* Parse `extract NAME { f: type, g?: type } ...` out of a statement.
 * Accepts the block on one line or spread over several (the caller
 * joins continuation lines). Returns 0 on success, 1 on a bad schema
 * with a reason on stderr. */
int spark_extract_parse_schema(const char *stmt,
			       struct spark_extract_schema *out);

/* Read a `fixture "PATH"` clause. Returns 0 and fills buf, or 1 and
 * explains that dry-run has no fixture to read. */
int spark_extract_resolve_fixture(const char *stmt, char *buf,
				  size_t buflen);

/* fopen + slurp. Missing file is an error, not an empty result. */
int spark_extract_load_fixture(const char *path, char **out,
			       size_t *out_len);

/* Check every required field is present and every present field has
 * the declared type. Returns 0 when valid, 1 when not, listing each
 * violation on stderr. Extra fields in the fixture are allowed. */
int spark_extract_validate(const struct spark_extract_schema *schema,
			   const char *json);

#endif /* SPARK_DRY_EXTRACT_H */
