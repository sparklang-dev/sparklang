/* Spark full ELF section raw dump + checkpoint/resume.
 * Streams every section to OUTDIR/<sec>.raw (any file size).
 * NOBITS → empty .raw. Resume via OUTDIR/.checkpoint (next index).
 *
 * Usage:
 *   ./spark-section-dump PATH OUTDIR [--resume]
 */
#define _GNU_SOURCE
#include <elf.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void die(const char *w) {
  fprintf(stderr, "spark-section-dump: %s: %s\n", w, strerror(errno));
  exit(1);
}

static void sanitize(char *dst, size_t dstsz, const char *src) {
  size_t j = 0;
  if (!src || !*src) {
    snprintf(dst, dstsz, "sh_unnamed");
    return;
  }
  for (size_t i = 0; src[i] && j + 1 < dstsz; i++) {
    char c = src[i];
    if (c == '/' || c == ' ')
      c = '_';
    dst[j++] = c;
  }
  dst[j] = 0;
}

static int read_ckpt(const char *dir) {
  char path[768];
  snprintf(path, sizeof path, "%s/.checkpoint", dir);
  FILE *f = fopen(path, "r");
  if (!f)
    return 0;
  int n = 0;
  if (fscanf(f, "%d", &n) != 1)
    n = 0;
  fclose(f);
  return n;
}

static void write_ckpt(const char *dir, int idx) {
  char path[768];
  snprintf(path, sizeof path, "%s/.checkpoint", dir);
  FILE *f = fopen(path, "w");
  if (!f)
    die("checkpoint write");
  fprintf(f, "%d\n", idx);
  fclose(f);
}

/* 64KiB heap stream — never a multi-MiB stack buffer (large ELF path). */
enum { COPY_CHUNK = 64 * 1024 };

static int copy_section(int infd, int outfd, off_t off, size_t sz) {
  char *buf = malloc(COPY_CHUNK);
  if (!buf)
    return -1;
  if (lseek(infd, off, SEEK_SET) < 0) {
    free(buf);
    return -1;
  }
  size_t left = sz;
  while (left) {
    size_t n = left > COPY_CHUNK ? COPY_CHUNK : left;
    ssize_t r = read(infd, buf, n);
    if (r <= 0) {
      free(buf);
      return -1;
    }
    if (write(outfd, buf, (size_t)r) != r) {
      free(buf);
      return -1;
    }
    left -= (size_t)r;
  }
  free(buf);
  return 0;
}

int main(int argc, char **argv) {
  if (argc < 3) {
    fputs("Usage: spark-section-dump PATH OUTDIR [--resume]\n",
          stderr);
    return 2;
  }
  const char *elf_path = argv[1];
  const char *outdir = argv[2];
  int resume = 0;
  for (int i = 3; i < argc; i++)
    if (!strcmp(argv[i], "--resume"))
      resume = 1;

  mkdir(outdir, 0755);

  int fd = open(elf_path, O_RDONLY);
  if (fd < 0)
    die("open elf");

  Elf64_Ehdr eh;
  if (read(fd, &eh, sizeof eh) != (ssize_t)sizeof eh)
    die("read ehdr");
  if (memcmp(eh.e_ident, "\177ELF", 4) != 0) {
    fprintf(stderr, "spark-section-dump: not ELF64\n");
    return 1;
  }
  if (eh.e_ident[EI_CLASS] != ELFCLASS64) {
    fprintf(stderr, "spark-section-dump: only ELF64\n");
    return 1;
  }

  size_t sh_bytes = (size_t)eh.e_shnum * eh.e_shentsize;
  Elf64_Shdr *sh = calloc(eh.e_shnum, sizeof(Elf64_Shdr));
  if (!sh)
    die("calloc");
  if (lseek(fd, (off_t)eh.e_shoff, SEEK_SET) < 0)
    die("lseek shoff");
  if (read(fd, sh, sh_bytes) != (ssize_t)sh_bytes)
    die("read shdrs");

  Elf64_Shdr *shstr = &sh[eh.e_shstrndx];
  char *names = malloc(shstr->sh_size + 1);
  if (!names)
    die("malloc names");
  if (lseek(fd, (off_t)shstr->sh_offset, SEEK_SET) < 0)
    die("lseek shstr");
  if (read(fd, names, shstr->sh_size) != (ssize_t)shstr->sh_size)
    die("read shstr");
  names[shstr->sh_size] = 0;

  int start = resume ? read_ckpt(outdir) : 0;
  if (start < 0)
    start = 0;

  for (int i = start; i < eh.e_shnum; i++) {
    char sn[256];
    sanitize(sn, sizeof sn, names + sh[i].sh_name);
    char path[900];
    snprintf(path, sizeof path, "%s/%s.raw", outdir, sn);

    int out = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (out < 0)
      die("open section out");

    if (sh[i].sh_type == SHT_NOBITS) {
      /* empty file = zeros at runtime */
      close(out);
    } else if (sh[i].sh_size > 0) {
      if (copy_section(fd, out, (off_t)sh[i].sh_offset,
                       (size_t)sh[i].sh_size) < 0) {
        close(out);
        die("copy section");
      }
      close(out);
    } else {
      close(out);
    }
    write_ckpt(outdir, i + 1);
  }

  /* done marker */
  write_ckpt(outdir, eh.e_shnum);
  printf("{\"op\":\"section_dump\",\"ok\":true,\"path\":\"%s\","
         "\"outdir\":\"%s\",\"sections\":%u,\"resumed_from\":%d}\n",
         elf_path, outdir, eh.e_shnum, start);
  free(names);
  free(sh);
  close(fd);
  return 0;
}
