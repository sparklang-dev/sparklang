/* sparkc / spark-bootstrap — C dry-run VM (path B).
 * --run-bc / --compile / --lex on bc_vm + lex. */
#include "bc_vm.h"
#include "spark_parse.h"
#include "vm.h"

#include "../selfhost/lex.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void usage(const char *argv0)
{
  fprintf(stderr,
          "usage: %s [--dry-run] [--run-bc <file.sparkbc>]\n"
          "          [--compile <file.spark> -o <out.sparkbc>]\n"
          "          [--lex <file.spark>] [--version] [--compare]\n"
          "          [<file.spark>]\n"
          "  C bootstrap VM dry subset (model/ask/print/let +\n"
          "  classify/extract/tool/with/listen/speak/pipeline).\n"
          "  --run-bc: execute SPARK_BC on bc_vm.\n"
          "  --compile: LANGUAGE forms → .sparkbc (C lowering; fail loud).\n"
          "  --lex: token JSONL (selfhost goldens).\n"
          "  --compare: also run ./spark --dry-run (harness only).\n",
          argv0);
}

int main(int argc, char **argv)
{
  const char *path = NULL;
  const char *bc_path = NULL;
  const char *compile_in = NULL;
  const char *compile_out = NULL;
  const char *lex_path = NULL;
  int compare = 0;
  int i;
  SparkVM vm;
  int rc;

  for (i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
      usage(argv[0]);
      return 0;
    }
    if (strcmp(argv[i], "--version") == 0) {
      printf("spark-bootstrap 0.1 (C VM path B)\n");
      return 0;
    }
    if (strcmp(argv[i], "--dry-run") == 0)
      continue;
    if (strcmp(argv[i], "--run-bc") == 0) {
      if (i + 1 >= argc) {
        fprintf(stderr, "error: --run-bc requires a .sparkbc path\n");
        usage(argv[0]);
        return 2;
      }
      bc_path = argv[++i];
      continue;
    }
    if (strcmp(argv[i], "--compile") == 0) {
      if (i + 1 >= argc) {
        fprintf(stderr, "error: --compile requires <file.spark>\n");
        usage(argv[0]);
        return 2;
      }
      compile_in = argv[++i];
      continue;
    }
    if (strcmp(argv[i], "-o") == 0) {
      if (i + 1 >= argc) {
        fprintf(stderr, "error: -o requires output path\n");
        return 2;
      }
      compile_out = argv[++i];
      continue;
    }
    if (strcmp(argv[i], "--lex") == 0) {
      if (i + 1 >= argc) {
        fprintf(stderr, "error: --lex requires <file.spark>\n");
        usage(argv[0]);
        return 2;
      }
      lex_path = argv[++i];
      continue;
    }
    if (strcmp(argv[i], "--live") == 0) {
      fprintf(stderr,
              "error: --live not supported in C bootstrap "
              "(use ./spark)\n");
      return 2;
    }
    if (strcmp(argv[i], "--compare") == 0) {
      compare = 1;
      continue;
    }
    if (argv[i][0] == '-') {
      fprintf(stderr, "error: unknown flag %s\n", argv[i]);
      usage(argv[0]);
      return 2;
    }
    path = argv[i];
  }

  if (bc_path) {
    if (path || compile_in || lex_path) {
      fprintf(stderr, "error: --run-bc excludes other input modes\n");
      return 2;
    }
    if (compare) {
      fprintf(stderr,
              "error: --compare is for .spark tree-walk only\n");
      return 2;
    }
    return spark_bc_run_file(bc_path);
  }

  if (lex_path) {
    if (path || compile_in) {
      fprintf(stderr, "error: --lex excludes other input modes\n");
      return 2;
    }
    return spark_lex_file(lex_path, stdout);
  }

  if (compile_in) {
    const char *out = compile_out;
    if (path || lex_path) {
      fprintf(stderr, "error: --compile excludes other input modes\n");
      return 2;
    }
    if (!out) {
      fprintf(stderr, "error: --compile requires -o <out.sparkbc>\n");
      return 2;
    }
    return spark_compile_file(compile_in, out);
  }

  if (!path) {
    usage(argv[0]);
    return 2;
  }

  {
    int compiled = 0;
    rc = spark_bc_compile_and_run(path, &compiled);
    if (compiled)
      return rc;
  }

  spark_vm_init(&vm);
  rc = spark_vm_run_file(&vm, path);
  if (rc != 0)
    return rc;

  if (compare) {
    char *spargv[] = {"./spark", "--dry-run", (char *)path, NULL};
    printf("--- compare harness: ./spark --dry-run ---\n");
    if (access("./spark", X_OK) != 0) {
      fprintf(stderr,
              "error: ./spark missing for --compare "
              "(run make spark)\n");
      return 1;
    }
    execv("./spark", spargv);
    perror("execv ./spark");
    return 1;
  }
  return 0;
}
