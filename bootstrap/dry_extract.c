/* Typed extract — schema parse + fixture validation. LANGUAGE.md.
 *
 * The fixture is the only source of field values: this file never
 * synthesises one. A missing fixture, an unparseable schema, a missing
 * required field, or a type mismatch are all errors with a non-zero
 * return, not warnings printed alongside a pretend success.
 */
#include "dry_extract.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_FIXTURE (1 << 20)

/* Type of a JSON value as it actually appears in the fixture. */
enum json_kind {
	J_STRING,
	J_INT,
	J_FLOAT,
	J_BOOL,
	J_NULL,
	J_OBJECT,
	J_ARRAY,
	J_BAD
};

const char *spark_extract_type_name(enum spark_extract_type t)
{
	switch (t) {
	case SPARK_X_STRING:
		return "string";
	case SPARK_X_INT:
		return "int";
	case SPARK_X_FLOAT:
		return "float";
	case SPARK_X_BOOL:
		return "bool";
	}
	return "?";
}

static const char *kind_name(enum json_kind k)
{
	switch (k) {
	case J_STRING:
		return "string";
	case J_INT:
		return "int";
	case J_FLOAT:
		return "float";
	case J_BOOL:
		return "bool";
	case J_NULL:
		return "null";
	case J_OBJECT:
		return "object";
	case J_ARRAY:
		return "array";
	case J_BAD:
		break;
	}
	return "invalid";
}

static const char *skip_ws(const char *p)
{
	while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r')
		p++;
	return p;
}

/* ---------------------------------------------------------------
 * Schema
 * --------------------------------------------------------------- */

static int type_from_word(const char *w, size_t n,
			  enum spark_extract_type *out)
{
	if (n == 6 && memcmp(w, "string", 6) == 0)
		*out = SPARK_X_STRING;
	else if (n == 3 && memcmp(w, "int", 3) == 0)
		*out = SPARK_X_INT;
	else if (n == 5 && memcmp(w, "float", 5) == 0)
		*out = SPARK_X_FLOAT;
	else if (n == 4 && memcmp(w, "bool", 4) == 0)
		*out = SPARK_X_BOOL;
	else
		return 1;
	return 0;
}

static int ident_char(char c)
{
	return isalnum((unsigned char)c) || c == '_';
}

int spark_extract_parse_schema(const char *stmt,
			       struct spark_extract_schema *out)
{
	const char *p;
	size_t n;

	memset(out, 0, sizeof(*out));
	if (!stmt) {
		fprintf(stderr, "error: extract has no statement\n");
		return 1;
	}
	p = strstr(stmt, "extract");
	if (!p) {
		fprintf(stderr, "error: extract statement missing "
				"'extract' keyword\n");
		return 1;
	}
	p = skip_ws(p + 7);

	/* Schema name. */
	n = 0;
	while (ident_char(p[n]))
		n++;
	if (n == 0) {
		fprintf(stderr, "error: extract needs a schema name, "
				"e.g. extract Person { ... }\n");
		return 1;
	}
	if (n >= SPARK_EXTRACT_NAME_MAX) {
		fprintf(stderr, "error: extract schema name too long\n");
		return 1;
	}
	memcpy(out->name, p, n);
	out->name[n] = 0;
	p = skip_ws(p + n);

	if (*p != '{') {
		fprintf(stderr,
			"error: extract %s needs a { field: type } "
			"schema block\n", out->name);
		return 1;
	}
	p = skip_ws(p + 1);

	while (*p && *p != '}') {
		struct spark_extract_field *f;
		size_t fn = 0;

		if (out->n_fields >= SPARK_EXTRACT_MAX_FIELDS) {
			fprintf(stderr,
				"error: extract %s has more than %d "
				"fields\n", out->name,
				SPARK_EXTRACT_MAX_FIELDS);
			return 1;
		}
		f = &out->fields[out->n_fields];

		while (ident_char(p[fn]))
			fn++;
		if (fn == 0) {
			fprintf(stderr,
				"error: extract %s: expected a field "
				"name near \"%.16s\"\n", out->name, p);
			return 1;
		}
		if (fn >= SPARK_EXTRACT_NAME_MAX) {
			fprintf(stderr, "error: extract %s: field name "
					"too long\n", out->name);
			return 1;
		}
		memcpy(f->name, p, fn);
		f->name[fn] = 0;
		p = skip_ws(p + fn);

		/* `field?: type` marks the field optional. */
		if (*p == '?') {
			f->optional = 1;
			p = skip_ws(p + 1);
		}
		if (*p != ':') {
			fprintf(stderr,
				"error: extract %s: field %s needs "
				"\": type\"\n", out->name, f->name);
			return 1;
		}
		p = skip_ws(p + 1);

		fn = 0;
		while (ident_char(p[fn]))
			fn++;
		if (type_from_word(p, fn, &f->type) != 0) {
			fprintf(stderr,
				"error: extract %s: field %s has "
				"unknown type \"%.*s\" "
				"(want string, int, float, bool)\n",
				out->name, f->name, (int)fn, p);
			return 1;
		}
		p = skip_ws(p + fn);
		out->n_fields++;

		/* Fields separate on a comma, a newline, or both. */
		while (*p == ',')
			p = skip_ws(p + 1);
	}

	if (*p != '}') {
		fprintf(stderr,
			"error: extract %s schema block is not closed "
			"with }\n", out->name);
		return 1;
	}
	if (out->n_fields == 0) {
		fprintf(stderr,
			"error: extract %s declares no fields, so "
			"there is nothing to validate\n", out->name);
		return 1;
	}
	return 0;
}

/* ---------------------------------------------------------------
 * Fixture
 * --------------------------------------------------------------- */

int spark_extract_resolve_fixture(const char *stmt, char *buf,
				  size_t buflen)
{
	const char *p;
	size_t n = 0;

	p = stmt ? strstr(stmt, "fixture") : NULL;
	if (p)
		p = strchr(p + 7, '"');
	if (!p) {
		fprintf(stderr,
			"error: extract dry-run requires "
			"fixture \"PATH\" — no model call, "
			"no invented fields\n");
		return 1;
	}
	p++;
	while (p[n] && p[n] != '"') {
		if (n + 1 >= buflen) {
			fprintf(stderr,
				"error: extract fixture path too "
				"long\n");
			return 1;
		}
		buf[n] = p[n];
		n++;
	}
	if (p[n] != '"') {
		fprintf(stderr, "error: extract fixture path is not "
				"closed with \"\n");
		return 1;
	}
	buf[n] = 0;
	if (n == 0) {
		fprintf(stderr,
			"error: extract fixture path is empty\n");
		return 1;
	}
	return 0;
}


int spark_extract_resolve_from(const char *stmt, char *buf, size_t buflen)
{
	const char *p;
	size_t n = 0;

	p = stmt ? strstr(stmt, "from") : NULL;
	if (!p) {
		fprintf(stderr,
			"error: extract live requires from \"TEXT\"\n");
		return 1;
	}
	p += 4;
	while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r')
		p++;
	if (*p != '"') {
		fprintf(stderr,
			"error: extract from clause needs \"TEXT\"\n");
		return 1;
	}
	p++;
	while (*p && *p != '"') {
		if (n + 1 >= buflen) {
			fprintf(stderr,
				"error: extract from text too long\n");
			return 1;
		}
		if (*p == '\\' && p[1]) {
			p++;
			if (*p == 'n')
				buf[n++] = '\n';
			else if (*p == 't')
				buf[n++] = '\t';
			else
				buf[n++] = *p;
			p++;
			continue;
		}
		buf[n++] = *p++;
	}
	if (*p != '"') {
		fprintf(stderr,
			"error: extract from text is not closed with \"\n");
		return 1;
	}
	buf[n] = 0;
	if (n == 0) {
		fprintf(stderr, "error: extract from text is empty\n");
		return 1;
	}
	return 0;
}

int spark_extract_load_fixture(const char *path, char **out,
			       size_t *out_len)
{
	FILE *f;
	long n;
	char *bufp;

	*out = NULL;
	if (out_len)
		*out_len = 0;
	f = fopen(path, "rb");
	if (!f) {
		fprintf(stderr,
			"error: extract fixture missing: %s\n", path);
		return 1;
	}
	if (fseek(f, 0, SEEK_END) != 0) {
		fclose(f);
		fprintf(stderr, "error: extract fseek %s\n", path);
		return 1;
	}
	n = ftell(f);
	if (n < 0 || n > MAX_FIXTURE) {
		fclose(f);
		fprintf(stderr,
			"error: extract fixture too large or bad: "
			"%s\n", path);
		return 1;
	}
	rewind(f);
	bufp = malloc((size_t)n + 1);
	if (!bufp) {
		fclose(f);
		fprintf(stderr, "error: extract oom\n");
		return 1;
	}
	if (fread(bufp, 1, (size_t)n, f) != (size_t)n) {
		free(bufp);
		fclose(f);
		fprintf(stderr, "error: extract read %s\n", path);
		return 1;
	}
	bufp[n] = 0;
	fclose(f);
	/* Drop the file's trailing newline so every engine prints the
	 * same one-line result; JSON ignores it either way. */
	while (n > 0 && (bufp[n - 1] == '\n' || bufp[n - 1] == '\r' ||
			 bufp[n - 1] == ' ' || bufp[n - 1] == '\t'))
		bufp[--n] = 0;
	*out = bufp;
	if (out_len)
		*out_len = (size_t)n;
	return 0;
}

/* ---------------------------------------------------------------
 * JSON scan
 *
 * Only enough JSON to walk the top-level object and classify each
 * value. Nested objects and arrays are skipped wholesale so a nested
 * key can never be mistaken for a top-level one.
 * --------------------------------------------------------------- */

static const char *scan_string(const char *p)
{
	if (*p != '"')
		return NULL;
	p++;
	while (*p) {
		if (*p == '\\') {
			if (!p[1])
				return NULL;
			p += 2;
			continue;
		}
		if (*p == '"')
			return p + 1;
		p++;
	}
	return NULL;
}

static const char *scan_value(const char *p, enum json_kind *kind);

static const char *scan_container(const char *p, char open, char close)
{
	int depth = 0;

	while (*p) {
		if (*p == '"') {
			const char *e = scan_string(p);

			if (!e)
				return NULL;
			p = e;
			continue;
		}
		if (*p == open) {
			depth++;
		} else if (*p == close) {
			depth--;
			if (depth == 0)
				return p + 1;
		}
		p++;
	}
	return NULL;
}

static const char *scan_value(const char *p, enum json_kind *kind)
{
	const char *e;

	p = skip_ws(p);
	if (*p == '"') {
		e = scan_string(p);
		if (!e)
			return NULL;
		*kind = J_STRING;
		return e;
	}
	if (*p == '{') {
		e = scan_container(p, '{', '}');
		if (!e)
			return NULL;
		*kind = J_OBJECT;
		return e;
	}
	if (*p == '[') {
		e = scan_container(p, '[', ']');
		if (!e)
			return NULL;
		*kind = J_ARRAY;
		return e;
	}
	if (strncmp(p, "true", 4) == 0) {
		*kind = J_BOOL;
		return p + 4;
	}
	if (strncmp(p, "false", 5) == 0) {
		*kind = J_BOOL;
		return p + 5;
	}
	if (strncmp(p, "null", 4) == 0) {
		*kind = J_NULL;
		return p + 4;
	}
	if (*p == '-' || *p == '+' || isdigit((unsigned char)*p)) {
		int is_float = 0;

		if (*p == '-' || *p == '+')
			p++;
		if (!isdigit((unsigned char)*p))
			return NULL;
		while (isdigit((unsigned char)*p))
			p++;
		if (*p == '.') {
			is_float = 1;
			p++;
			while (isdigit((unsigned char)*p))
				p++;
		}
		if (*p == 'e' || *p == 'E') {
			is_float = 1;
			p++;
			if (*p == '-' || *p == '+')
				p++;
			while (isdigit((unsigned char)*p))
				p++;
		}
		*kind = is_float ? J_FLOAT : J_INT;
		return p;
	}
	return NULL;
}

/* Find a top-level key. Returns 1 when found and sets *kind. */
static int json_find_key(const char *json, const char *key,
			 enum json_kind *kind)
{
	const char *p = skip_ws(json);
	size_t keylen = strlen(key);

	if (*p != '{')
		return -1;
	p = skip_ws(p + 1);
	if (*p == '}')
		return 0;

	for (;;) {
		const char *kstart;
		const char *kend;
		size_t klen;
		enum json_kind vk = J_BAD;

		p = skip_ws(p);
		if (*p != '"')
			return -1;
		kstart = p + 1;
		kend = scan_string(p);
		if (!kend)
			return -1;
		klen = (size_t)(kend - 1 - kstart);
		p = skip_ws(kend);
		if (*p != ':')
			return -1;
		p = scan_value(p + 1, &vk);
		if (!p)
			return -1;
		if (klen == keylen &&
		    memcmp(kstart, key, keylen) == 0) {
			*kind = vk;
			return 1;
		}
		p = skip_ws(p);
		if (*p == ',') {
			p = skip_ws(p + 1);
			continue;
		}
		if (*p == '}')
			return 0;
		return -1;
	}
}

static int kind_matches(enum spark_extract_type want,
			enum json_kind got)
{
	switch (want) {
	case SPARK_X_STRING:
		return got == J_STRING;
	case SPARK_X_INT:
		return got == J_INT;
	case SPARK_X_FLOAT:
		/* JSON writes 3 for 3.0, so an int is a valid float. */
		return got == J_FLOAT || got == J_INT;
	case SPARK_X_BOOL:
		return got == J_BOOL;
	}
	return 0;
}

static void append_err(char *errbuf, size_t errcap, const char *line)
{
	size_t have, need;

	if (!errbuf || errcap == 0)
		return;
	have = strlen(errbuf);
	need = strlen(line) + 1;
	if (have + need + 1 >= errcap)
		return;
	if (have)
		errbuf[have++] = '\n';
	memcpy(errbuf + have, line, need);
}

int spark_extract_validate_explain(
	const struct spark_extract_schema *schema, const char *json,
	char *errbuf, size_t errcap)
{
	size_t i;
	int bad = 0;
	char line[256];

	if (errbuf && errcap)
		errbuf[0] = 0;

	for (i = 0; i < schema->n_fields; i++) {
		const struct spark_extract_field *f = &schema->fields[i];
		enum json_kind kind = J_BAD;
		int found = json_find_key(json, f->name, &kind);

		if (found < 0) {
			snprintf(line, sizeof(line),
				 "error: extract %s: fixture is not a "
				 "JSON object", schema->name);
			fprintf(stderr, "%s\n", line);
			append_err(errbuf, errcap, line);
			return 1;
		}
		if (!found) {
			if (f->optional)
				continue;
			snprintf(line, sizeof(line),
				 "error: extract %s: missing required "
				 "field %s (%s)", schema->name, f->name,
				 spark_extract_type_name(f->type));
			fprintf(stderr, "%s\n", line);
			append_err(errbuf, errcap, line);
			bad = 1;
			continue;
		}
		if (!kind_matches(f->type, kind)) {
			snprintf(line, sizeof(line),
				 "error: extract %s: field %s expected "
				 "%s, fixture has %s", schema->name,
				 f->name,
				 spark_extract_type_name(f->type),
				 kind_name(kind));
			fprintf(stderr, "%s\n", line);
			append_err(errbuf, errcap, line);
			bad = 1;
		}
	}
	return bad;
}

int spark_extract_validate(const struct spark_extract_schema *schema,
			   const char *json)
{
	return spark_extract_validate_explain(schema, json, NULL, 0);
}
