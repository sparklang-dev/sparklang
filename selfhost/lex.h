/* selfhost/lex.h — Spark source lexer (lane A / bootstrap --lex). */
#ifndef SPARK_LEX_H
#define SPARK_LEX_H

#include <stdio.h>

/* Tokenize path; emit one JSON object per line to out. Returns 0 or 1. */
int spark_lex_file(const char *path, FILE *out);

#endif
