/* selfhost/lex.c — Spark source lexer (lane A bootstrap aid).
 *
 * Reads a .spark file, emits one JSON object per token on stdout.
 * Kind names match selfhost/token_kinds.spark.
 * Linked into spark-bootstrap (--lex) and selfhost/spark-lex.
 */
#include "lex.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BUF_CAP (1 << 20)

/* Statement-start / core keywords only. Bindings like `text` stay IDENT. */
static const char *KEYWORDS[] = {
    "model", "use", "ask", "generate", "extract", "expect", "classify",
    "listen",
    "speak", "voice", "pipeline", "tool", "with", "let", "print",
    "set", "review", "builder", "implement", "ide", "browser",
    "mitm", "engine", "os", "cuda", "memory", "pcie", "binary",
    "network", "crypto", "encrypt", "gateway",
    NULL};

static int is_keyword(const char *s, size_t n) {
  for (const char **k = KEYWORDS; *k; k++) {
    if (strlen(*k) == n && memcmp(*k, s, n) == 0)
      return 1;
  }
  return 0;
}

static void emit_to(FILE *out, const char *kind, const char *lex, size_t n,
                    long line, long col)
{
  fputs("{\"kind\":\"", out);
  fputs(kind, out);
  fputs("\",\"lexeme\":\"", out);
  for (size_t j = 0; j < n; j++) {
    unsigned char c = (unsigned char)lex[j];
    if (c == '"' || c == '\\') {
      fputc('\\', out);
      fputc((char)c, out);
    } else if (c == '\n') {
      fputs("\\n", out);
    } else if (c == '\t') {
      fputs("\\t", out);
    } else if (c < 0x20) {
      fprintf(out, "\\u%04x", c);
    } else {
      fputc((char)c, out);
    }
  }
  fprintf(out, "\",\"line\":%ld,\"col\":%ld}\n", line, col);
}

int spark_lex_file(const char *path, FILE *out)
{
  FILE *f;
  char *buf;
  size_t len;
  long line;
  long col;
  size_t i;

  if (!path || !out) {
    fprintf(stderr, "error: spark_lex_file: null path or out\n");
    return 1;
  }
  f = fopen(path, "rb");
  if (!f) {
    perror(path);
    return 1;
  }
  buf = malloc(BUF_CAP);
  if (!buf) {
    fclose(f);
    return 1;
  }
  len = fread(buf, 1, BUF_CAP - 1, f);
  fclose(f);
  buf[len] = '\0';
  if (len == BUF_CAP - 1) {
    fprintf(stderr, "error: file too large (>%d bytes)\n", BUF_CAP - 1);
    free(buf);
    return 1;
  }

  line = 1;
  col = 1;
  i = 0;
  while (i < len) {
    char c = buf[i];
    if (c == ' ' || c == '\t' || c == '\r') {
      i++;
      col++;
      continue;
    }
    if (c == '\n') {
      i++;
      line++;
      col = 1;
      continue;
    }

    long tline = line, tcol = col;

    if (c == '#') {
      size_t start = i;
      while (i < len && buf[i] != '\n') {
        i++;
        col++;
      }
      emit_to(out, "COMMENT", buf + start, i - start, tline, tcol);
      continue;
    }

    if (c == '"') {
      size_t start = i;
      i++;
      col++;
      while (i < len) {
        if (buf[i] == '\\' && i + 1 < len) {
          i += 2;
          col += 2;
          continue;
        }
        if (buf[i] == '"') {
          i++;
          col++;
          break;
        }
        if (buf[i] == '\n') {
          fprintf(stderr, "error:%ld:%ld: unterminated string\n", tline,
                  tcol);
          free(buf);
          return 1;
        }
        i++;
        col++;
      }
      emit_to(out,"STRING", buf + start, i - start, tline, tcol);
      continue;
    }

    if (c == '-' && i + 1 < len && buf[i + 1] == '>') {
      emit_to(out,"ARROW", buf + i, 2, tline, tcol);
      i += 2;
      col += 2;
      continue;
    }

    if (c == '|') {
      emit_to(out,"PIPE", buf + i, 1, tline, tcol);
      i++;
      col++;
      continue;
    }

    if (isdigit((unsigned char)c)) {
      size_t start = i;
      while (i < len && (isdigit((unsigned char)buf[i]) || buf[i] == '.')) {
        i++;
        col++;
      }
      emit_to(out,"NUMBER", buf + start, i - start, tline, tcol);
      continue;
    }

    if (isalpha((unsigned char)c) || c == '_') {
      size_t start = i;
      while (i < len &&
             (isalnum((unsigned char)buf[i]) || buf[i] == '_' ||
              buf[i] == '-')) {
        /* keep hyphen inside idents only if mid-token; stop before -> */
        if (buf[i] == '-' && i + 1 < len && buf[i + 1] == '>')
          break;
        i++;
        col++;
      }
      size_t n = i - start;
      const char *kind = is_keyword(buf + start, n) ? "KEYWORD" : "IDENT";
      emit_to(out,kind, buf + start, n, tline, tcol);
      continue;
    }

    /* single-byte punct */
    /* '?' is punct: it marks an optional extract field (`email?: string`).
     * Statement-leading `?` ask-sugar is rewritten before the lexer. */
    if (strchr("{}[]():,.=<>!?", c)) {
      emit_to(out,"PUNCT", buf + i, 1, tline, tcol);
      i++;
      col++;
      continue;
    }

    fprintf(stderr, "error:%ld:%ld: unexpected byte 0x%02x\n", tline, tcol,
            (unsigned char)c);
    free(buf);
    return 1;
  }

  emit_to(out, "EOF", "", 0, line, col);
  free(buf);
  return 0;
}

#ifndef SPARK_LEX_STANDALONE_MAIN
/* spark-lex links with -DSPARK_LEX_STANDALONE_MAIN */
#else
int main(int argc, char **argv)
{
  if (argc != 2) {
    fprintf(stderr, "usage: %s <file.spark>\n", argv[0]);
    return 2;
  }
  return spark_lex_file(argv[1], stdout);
}
#endif
