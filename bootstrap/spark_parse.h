/* Hello/mini/classify → SPARK_BC (docs/SPARK_BC.md).
 * Tokens via selfhost/lex.c. C does the lowering — not compile.spark. */
#ifndef SPARK_PARSE_H
#define SPARK_PARSE_H

/* Compile model/ask/print/let/classify. Unknown stmts fail loud. */
int spark_compile_file(const char *path, const char *out_bc);

/* Try compile+run; *compiled=1 if subset compiled, else 0 (tree-walk). */
int spark_bc_compile_and_run(const char *path, int *compiled);

#endif
