/* spark-binary-probe — ELF/dynsym/objdump helper for Spark binary ops.
 * Not linked into default ./spark. Local analysis only; no exfil.
 *
 * Usage:
 *   ./spark-binary-probe --understand PATH [--focus cuda|memory|uvm|general]
 *   ./spark-binary-probe --disasm PATH --offset HEX --length N
 *   ./spark-binary-probe --elf PATH
 */
#define _GNU_SOURCE
#include <ctype.h>
#include <elf.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

static int focus_match(const char *name, const char *focus) {
  if (!focus || !strcmp(focus, "general"))
    return 1;
  if (!strcmp(focus, "cuda"))
    return (strncmp(name, "cu", 2) == 0 ||
            strncmp(name, "cuda", 4) == 0 ||
            strncmp(name, "nvml", 4) == 0);
  if (!strcmp(focus, "memory"))
    return (strstr(name, "Memory") != NULL || strstr(name, "Mem") != NULL ||
            strstr(name, "Malloc") != NULL ||
            strstr(name, "cudaFree") != NULL);
  if (!strcmp(focus, "uvm"))
    return (strstr(name, "Uvm") != NULL || strstr(name, "uvm") != NULL ||
            strstr(name, "UVM") != NULL);
  return 1;
}

static void print_elf_hdr_fields(const Elf64_Ehdr *eh) {
  printf("\"elf_class\":%u,\"elf_data\":%u,\"elf_type\":%u,"
         "\"machine\":%u,\"entry\":\"0x%llx\",\"phoff\":%llu,"
         "\"shoff\":%llu,\"phnum\":%u,\"shnum\":%u",
         eh->e_ident[EI_CLASS], eh->e_ident[EI_DATA], eh->e_type,
         eh->e_machine, (unsigned long long)eh->e_entry,
         (unsigned long long)eh->e_phoff, (unsigned long long)eh->e_shoff,
         eh->e_phnum, eh->e_shnum);
}

/* Bounds-check ELF offset+size against mapped length (no OOB). */
static int in_map(size_t map_sz, uint64_t off, uint64_t sz) {
  if (sz > map_sz || off > map_sz)
    return 0;
  return off + sz <= map_sz;
}

/* Emit "sym","sym",… only (no JSON wrapper). Used by asm understand
 * mid-stream so large ELFs never walk a 64KiB asm peek buffer. */
static int emit_exports_only(const unsigned char *p, size_t map_sz,
                             const char *focus, int max_n) {
  if (map_sz < sizeof(Elf64_Ehdr) || p[EI_CLASS] != ELFCLASS64)
    return 1;
  const Elf64_Ehdr *eh = (const Elf64_Ehdr *)p;
  if (!in_map(map_sz, eh->e_shoff,
              (uint64_t)eh->e_shnum * eh->e_shentsize))
    return 1;
  const Elf64_Shdr *sh = (const Elf64_Shdr *)(p + eh->e_shoff);
  if (eh->e_shstrndx >= eh->e_shnum)
    return 1;
  if (!in_map(map_sz, sh[eh->e_shstrndx].sh_offset,
              sh[eh->e_shstrndx].sh_size))
    return 1;
  const char *shstr = (const char *)(p + sh[eh->e_shstrndx].sh_offset);
  const Elf64_Shdr *dynsym = NULL, *dynstr = NULL;
  for (int i = 0; i < eh->e_shnum; i++) {
    const char *nm = shstr + sh[i].sh_name;
    if (!strcmp(nm, ".dynsym"))
      dynsym = &sh[i];
    if (!strcmp(nm, ".dynstr"))
      dynstr = &sh[i];
  }
  int first = 1, n = 0;
  if (dynsym && dynstr &&
      in_map(map_sz, dynsym->sh_offset, dynsym->sh_size) &&
      in_map(map_sz, dynstr->sh_offset, dynstr->sh_size)) {
    const Elf64_Sym *sym = (const Elf64_Sym *)(p + dynsym->sh_offset);
    size_t nsym = dynsym->sh_size / sizeof(Elf64_Sym);
    const char *strs = (const char *)(p + dynstr->sh_offset);
    size_t str_sz = (size_t)dynstr->sh_size;
    for (size_t i = 0; i < nsym && n < max_n; i++) {
      if (sym[i].st_shndx == SHN_UNDEF)
        continue;
      if (ELF64_ST_TYPE(sym[i].st_info) != STT_FUNC &&
          ELF64_ST_TYPE(sym[i].st_info) != STT_OBJECT)
        continue;
      if (sym[i].st_name == 0 || (size_t)sym[i].st_name >= str_sz)
        continue;
      const char *name = strs + sym[i].st_name;
      if (!focus_match(name, focus))
        continue;
      if (!first)
        putchar(',');
      first = 0;
      printf("\"%s\"", name);
      n++;
    }
  }
  fflush(stdout);
  return 0;
}

static int understand(const char *path, const char *focus, int exports_only) {
  int fd = open(path, O_RDONLY);
  if (fd < 0) {
    fprintf(stderr, "open: %s\n", strerror(errno));
    return 1;
  }
  struct stat st;
  if (fstat(fd, &st) < 0) {
    close(fd);
    return 1;
  }
  if (st.st_size < (off_t)sizeof(Elf64_Ehdr)) {
    if (!exports_only)
      printf("{\"ok\":false,\"error\":\"too small\",\"path\":\"%s\","
             "\"size\":%lld}\n",
             path, (long long)st.st_size);
    close(fd);
    return 1;
  }
  /* Prefer mmap; for huge files MAP_PRIVATE is demand-paged (no
   * 96MiB stack/heap copy). Section headers may sit at EOF. */
  void *map = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
  close(fd);
  if (map == MAP_FAILED) {
    fprintf(stderr, "mmap: %s\n", strerror(errno));
    return 1;
  }
  const unsigned char *p = map;
  size_t map_sz = (size_t)st.st_size;
  if (!(p[0] == 0x7f && p[1] == 'E' && p[2] == 'L' && p[3] == 'F')) {
    if (!exports_only)
      printf("{\"ok\":false,\"format\":\"unknown\",\"magic\":\"%02x%02x%02x%02x\","
             "\"size\":%lld,\"note\":\"not ELF — may be .zst firmware/ko;"
             " decompress before ELF parse; never invent PE imports\"}\n",
             p[0], p[1], p[2], p[3], (long long)st.st_size);
    munmap(map, map_sz);
    return exports_only ? 1 : 0;
  }
  if (p[EI_CLASS] != ELFCLASS64) {
    if (!exports_only)
      printf("{\"ok\":false,\"error\":\"only ELF64 supported here\"}\n");
    munmap(map, map_sz);
    return 1;
  }
  if (exports_only) {
    int rc = emit_exports_only(p, map_sz, focus, 40);
    munmap(map, map_sz);
    return rc;
  }
  const Elf64_Ehdr *eh = (const Elf64_Ehdr *)p;
  printf("{\"op\":\"understand\",\"ok\":true,\"path\":\"%s\",\"size\":%lld,"
         "\"focus\":\"%s\",\"machine_disasm\":\"use_spark_binary_disasm\",",
         path, (long long)st.st_size, focus ? focus : "general");
  print_elf_hdr_fields(eh);

  const Elf64_Shdr *sh = NULL;
  const char *shstr = NULL;
  if (in_map(map_sz, eh->e_shoff,
             (uint64_t)eh->e_shnum * eh->e_shentsize) &&
      eh->e_shstrndx < eh->e_shnum) {
    sh = (const Elf64_Shdr *)(p + eh->e_shoff);
    if (in_map(map_sz, sh[eh->e_shstrndx].sh_offset,
               sh[eh->e_shstrndx].sh_size))
      shstr = (const char *)(p + sh[eh->e_shstrndx].sh_offset);
  }
  const Elf64_Shdr *dynsym = NULL, *dynstr = NULL, *text = NULL;
  if (sh && shstr) {
    for (int i = 0; i < eh->e_shnum; i++) {
      const char *nm = shstr + sh[i].sh_name;
      if (!strcmp(nm, ".dynsym"))
        dynsym = &sh[i];
      if (!strcmp(nm, ".dynstr"))
        dynstr = &sh[i];
      if (!strcmp(nm, ".text"))
        text = &sh[i];
    }
  }
  if (text)
    printf(",\"text_size\":%llu", (unsigned long long)text->sh_size);
  printf(",\"exports\":[");
  int first = 1, n = 0;
  if (dynsym && dynstr &&
      in_map(map_sz, dynsym->sh_offset, dynsym->sh_size) &&
      in_map(map_sz, dynstr->sh_offset, dynstr->sh_size)) {
    const Elf64_Sym *sym = (const Elf64_Sym *)(p + dynsym->sh_offset);
    size_t nsym = dynsym->sh_size / sizeof(Elf64_Sym);
    const char *strs = (const char *)(p + dynstr->sh_offset);
    size_t str_sz = (size_t)dynstr->sh_size;
    for (size_t i = 0; i < nsym && n < 40; i++) {
      if (sym[i].st_shndx == SHN_UNDEF)
        continue;
      if (ELF64_ST_TYPE(sym[i].st_info) != STT_FUNC &&
          ELF64_ST_TYPE(sym[i].st_info) != STT_OBJECT)
        continue;
      if (sym[i].st_name == 0 || (size_t)sym[i].st_name >= str_sz)
        continue;
      const char *name = strs + sym[i].st_name;
      if (!focus_match(name, focus))
        continue;
      if (!first)
        putchar(',');
      first = 0;
      printf("\"%s\"", name);
      n++;
    }
  }
  printf("],\"export_count_capped\":%d}\n", n);
  munmap(map, map_sz);
  return 0;
}

static int run_disasm(const char *path, unsigned long long off,
                      unsigned long long len) {
  char cmd[1024];
  unsigned long long end = off + len;
  snprintf(cmd, sizeof(cmd),
           "objdump -d --start-address=0x%llx --stop-address=0x%llx %s"
           " 2>/dev/null | head -80",
           off, end, path);
  printf("{\"op\":\"disasm\",\"orchestrator\":\"objdump\",\"cmd\":\"");
  for (const char *c = cmd; *c; c++) {
    if (*c == '"' || *c == '\\')
      putchar('\\');
    putchar(*c);
  }
  printf("\",\"bytes\":\n");
  fflush(stdout);
  int rc = system(cmd);
  printf("\n,\"objdump_status\":%d}\n", rc);
  return rc == 0 ? 0 : 1;
}

int main(int argc, char **argv) {
  const char *op = NULL, *path = NULL, *focus = "general";
  unsigned long long off = 0, len = 64;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--understand") && i + 1 < argc) {
      op = "understand";
      path = argv[++i];
    } else if (!strcmp(argv[i], "--exports") && i + 1 < argc) {
      /* Asm understand mid-JSON: print "sym",… only (mmap, any size). */
      op = "exports";
      path = argv[++i];
    } else if (!strcmp(argv[i], "--elf") && i + 1 < argc) {
      op = "elf";
      path = argv[++i];
    } else if (!strcmp(argv[i], "--disasm") && i + 1 < argc) {
      op = "disasm";
      path = argv[++i];
    } else if (!strcmp(argv[i], "--focus") && i + 1 < argc) {
      focus = argv[++i];
    } else if (!strcmp(argv[i], "--offset") && i + 1 < argc) {
      off = strtoull(argv[++i], NULL, 0);
    } else if (!strcmp(argv[i], "--length") && i + 1 < argc) {
      len = strtoull(argv[++i], NULL, 0);
    } else if (!strcmp(argv[i], "--help")) {
      fprintf(stderr,
              "spark-binary-probe --understand|--exports|--elf|--disasm "
              "PATH [--focus …] [--offset] [--length]\n");
      return 0;
    }
  }
  if (!op || !path) {
    fprintf(stderr, "need --understand|--exports|--elf|--disasm PATH\n");
    return 2;
  }
  if (!strcmp(op, "disasm"))
    return run_disasm(path, off, len);
  if (!strcmp(op, "exports"))
    return understand(path, focus, 1);
  return understand(path, focus, 0);
}
