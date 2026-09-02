/* sparkasm CLI */
#include "sparkasm.h"

#include <stdio.h>
#include <string.h>

static void usage(const char *argv0) {
	fprintf(stderr,
		"Usage: %s [-o out] [--format=elf|bin] <file.sasm>\n"
		"  Spark-native assembler (phase 1). Not GAS.\n"
		"  Default format: relocatable ELF (.o).\n",
		argv0);
}

int main(int argc, char **argv) {
	const char *out = NULL;
	const char *in = NULL;
	sa_format_t fmt = SA_FMT_ELF_O;
	sa_unit_t u;
	int i;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "-h") == 0 ||
		    strcmp(argv[i], "--help") == 0) {
			usage(argv[0]);
			return 0;
		}
		if (strcmp(argv[i], "-o") == 0) {
			if (i + 1 >= argc) {
				usage(argv[0]);
				return 2;
			}
			out = argv[++i];
			continue;
		}
		if (strncmp(argv[i], "--format=", 9) == 0) {
			const char *f = argv[i] + 9;
			if (strcmp(f, "elf") == 0 || strcmp(f, "o") == 0)
				fmt = SA_FMT_ELF_O;
			else if (strcmp(f, "bin") == 0)
				fmt = SA_FMT_BIN;
			else {
				fprintf(stderr, "bad --format=%s\n", f);
				return 2;
			}
			continue;
		}
		if (argv[i][0] == '-') {
			fprintf(stderr, "unknown flag %s\n", argv[i]);
			usage(argv[0]);
			return 2;
		}
		if (in) {
			fprintf(stderr, "extra argument %s\n", argv[i]);
			return 2;
		}
		in = argv[i];
	}
	if (!in) {
		usage(argv[0]);
		return 2;
	}
	if (!out) {
		out = (fmt == SA_FMT_BIN) ? "a.bin" : "a.o";
	}

	if (sa_assemble_file(in, &u)) {
		fprintf(stderr, "sparkasm: %s\n", u.err);
		return 1;
	}
	if (fmt == SA_FMT_BIN) {
		if (sa_write_bin(out, &u)) {
			fprintf(stderr, "sparkasm: write bin failed\n");
			return 1;
		}
	} else if (sa_write_elf_o(out, &u)) {
		fprintf(stderr, "sparkasm: write ELF .o failed\n");
		return 1;
	}
	return 0;
}
