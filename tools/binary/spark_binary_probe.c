/* spark-binary-probe — ELF/PE/dynsym/objdump helper for Spark binary ops.
 * Not linked into default ./spark. Local analysis only; no exfil.
 *
 * Usage:
 *   ./spark-binary-probe --understand PATH [--focus cuda|memory|uvm|general]
 *   ./spark-binary-probe --disasm PATH --offset HEX --length N
 *   ./spark-binary-probe --elf PATH
 *   ./spark-binary-probe --pe PATH
 *
 * --understand auto-detects by magic: ELF64 → ELF walk, MZ → PE32/PE32+
 * walk. --elf / --pe are strict and fail loud on the wrong format.
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

/* Defined below; understand() auto-detects MZ → PE walk. */
static int pe_parse(const unsigned char *p, size_t map_sz,
                    const char *path, long long fsize);

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

static int understand(const char *path, const char *focus, int exports_only,
                      int elf_mode) {
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
    /* Auto-detect by magic: MZ → real PE32/PE32+ walk.
     * --elf stays ELF-strict (no silent format swap). */
    if (!exports_only && !elf_mode && p[0] == 'M' && p[1] == 'Z') {
      int rc = pe_parse(p, map_sz, path, (long long)st.st_size);
      munmap(map, map_sz);
      return rc;
    }
    if (!exports_only)
      printf("{\"ok\":false,\"format\":\"unknown\",\"magic\":\"%02x%02x%02x%02x\","
             "\"size\":%lld,\"note\":\"not ELF/PE — may be .zst firmware/ko;"
             " decompress before parse; never invent imports\"}\n",
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
  printf("{\"op\":\"%s\",\"ok\":true,\"path\":\"%s\",\"size\":%lld,"
         "\"focus\":\"%s\",\"machine_disasm\":\"use_spark_binary_disasm\","
         "\"claim\":\"local_elf_probe_not_ghidra\",",
         elf_mode ? "elf" : "understand", path, (long long)st.st_size,
         focus ? focus : "general");
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

  /* Section index for --elf (local probe; not Ghidra-class). */
  if (elf_mode && sh && shstr) {
    printf(",\"sections\":[");
    int sfirst = 1;
    int capped = eh->e_shnum > 64 ? 64 : eh->e_shnum;
    for (int i = 0; i < capped; i++) {
      const char *nm = shstr + sh[i].sh_name;
      if (!sfirst)
        putchar(',');
      sfirst = 0;
      printf("{\"name\":\"");
      for (const char *c = nm; *c; c++) {
        if (*c == '"' || *c == '\\')
          putchar('\\');
        putchar(*c);
      }
      printf("\",\"type\":%u,\"size\":%llu,\"addr\":\"0x%llx\"}",
             sh[i].sh_type, (unsigned long long)sh[i].sh_size,
             (unsigned long long)sh[i].sh_addr);
    }
    printf("],\"section_count\":%u,\"section_cap\":%d", eh->e_shnum,
           capped);
  }

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

/* ---- PE32 / PE32+ (bounds-checked, same discipline as ELF side) ---- */

#define PE_OPT_MAGIC_32 0x10b
#define PE_OPT_MAGIC_32PLUS 0x20b
#define PE_MAX_SECTIONS 96 /* PE spec upper bound */
#define PE_MAX_DLLS 64
#define PE_MAX_THUNKS 512
#define PE_NAME_CAP 256

/* Bounded little-endian reads out of the map (memcpy: no align UB). */
static int pe_u16(const unsigned char *p, size_t sz, uint64_t off,
                  uint16_t *out) {
  if (!in_map(sz, off, 2))
    return -1;
  memcpy(out, p + off, 2);
  return 0;
}

static int pe_u32(const unsigned char *p, size_t sz, uint64_t off,
                  uint32_t *out) {
  if (!in_map(sz, off, 4))
    return -1;
  memcpy(out, p + off, 4);
  return 0;
}

static int pe_u64(const unsigned char *p, size_t sz, uint64_t off,
                  uint64_t *out) {
  if (!in_map(sz, off, 8))
    return -1;
  memcpy(out, p + off, 8);
  return 0;
}

/* Bounded C-string copy; fails on OOB or no NUL within cap. */
static int pe_cstr(const unsigned char *p, size_t sz, uint64_t off,
                   char *buf, size_t cap) {
  size_t i;
  if (off >= sz)
    return -1;
  for (i = 0; i + 1 < cap; i++) {
    if (off + i >= sz)
      return -1;
    buf[i] = (char)p[off + i];
    if (buf[i] == '\0')
      return 0;
  }
  return -1;
}

static void json_escape_print(const char *s) {
  const unsigned char *c;
  for (c = (const unsigned char *)s; *c; c++) {
    if (*c == '"' || *c == '\\') {
      putchar('\\');
      putchar(*c);
    } else if (*c < 0x20) {
      printf("\\u%04x", *c);
    } else {
      putchar(*c);
    }
  }
}

static const char *pe_machine_name(uint16_t machine) {
  switch (machine) {
  case 0x14c:
    return "i386";
  case 0x8664:
    return "x86-64";
  case 0x1c0:
    return "arm";
  case 0xaa64:
    return "arm64";
  default:
    return "unknown";
  }
}

static const char *pe_subsystem_name(uint16_t sub) {
  switch (sub) {
  case 1:
    return "native";
  case 2:
    return "windows_gui";
  case 3:
    return "windows_console";
  case 7:
    return "posix";
  case 9:
    return "windows_ce";
  case 10:
    return "efi_application";
  default:
    return "unknown";
  }
}

typedef struct {
  char name[64]; /* short 8-byte name or resolved long "/N" name */
  uint32_t vsize;
  uint32_t vaddr;
  uint32_t raw_size;
  uint32_t raw_off;
  uint32_t characteristics;
} pe_section_t;

/* Map an RVA to a file offset via the section table (or headers). */
static int pe_rva_to_off(const pe_section_t *secs, int nsec,
                         uint32_t size_of_headers, uint32_t rva,
                         uint64_t *off) {
  int i;
  if (rva < size_of_headers) {
    *off = rva;
    return 0;
  }
  for (i = 0; i < nsec; i++) {
    uint64_t span = secs[i].vsize > secs[i].raw_size ? secs[i].vsize
                                                     : secs[i].raw_size;
    if (rva >= secs[i].vaddr && (uint64_t)rva < (uint64_t)secs[i].vaddr + span) {
      *off = (uint64_t)secs[i].raw_off + (rva - secs[i].vaddr);
      return 0;
    }
  }
  return -1;
}

static int pe_fail(const char *path, const char *err) {
  printf("{\"op\":\"pe\",\"ok\":false,\"error\":\"%s\",\"path\":\"",
         err);
  json_escape_print(path);
  printf("\"}\n");
  return 1;
}

/* Walk one import descriptor's thunk table. emit=0 validates bounds
 * only (pre-pass so a truncated table can never poison stdout);
 * emit=1 prints function names (guaranteed in-bounds by pre-pass). */
static int pe_emit_thunks(const unsigned char *p, size_t map_sz,
                          const pe_section_t *secs, int nsec,
                          uint32_t size_of_headers, int is_plus,
                          uint32_t thunk_rva, int *fn_count,
                          int *ord_count, int *first, int emit) {
  uint64_t thunk_off;
  int j;
  if (pe_rva_to_off(secs, nsec, size_of_headers, thunk_rva,
                    &thunk_off) < 0)
    return -1;
  for (j = 0; j < PE_MAX_THUNKS; j++) {
    uint64_t val = 0;
    uint64_t entry_off = thunk_off + (uint64_t)j * (is_plus ? 8 : 4);
    if (is_plus) {
      if (pe_u64(p, map_sz, entry_off, &val) < 0)
        return -1;
    } else {
      uint32_t v32;
      if (pe_u32(p, map_sz, entry_off, &v32) < 0)
        return -1;
      val = v32;
    }
    if (val == 0)
      break;
    if (is_plus ? (val & 0x8000000000000000ULL)
                : (val & 0x80000000U)) {
      (*ord_count)++;
      continue;
    }
    {
      uint64_t ibn_off;
      char fname[PE_NAME_CAP];
      if (pe_rva_to_off(secs, nsec, size_of_headers, (uint32_t)val,
                        &ibn_off) < 0)
        return -1;
      /* IMAGE_IMPORT_BY_NAME: u16 hint then NUL-terminated name. */
      if (pe_cstr(p, map_sz, ibn_off + 2, fname, sizeof(fname)) < 0)
        return -1;
      if (emit) {
        if (!*first)
          putchar(',');
        *first = 0;
        printf("\"");
        json_escape_print(fname);
        printf("\"");
      }
      (*fn_count)++;
    }
  }
  if (j >= PE_MAX_THUNKS)
    return -1;
  return 0;
}

/* Validate the whole import table before any JSON is printed.
 * Returns 0 and fills counts, or -1 on truncation/corruption. */
static int pe_walk_imports(const unsigned char *p, size_t map_sz,
                           const pe_section_t *secs, int nsec,
                           uint32_t size_of_headers, int is_plus,
                           uint64_t dirs_off, uint32_t n_dirs,
                           int emit, int *dll_count, int *fn_total,
                           int *ord_total) {
  uint32_t imp_rva = 0, imp_size = 0;
  uint64_t imp_off;
  int i;
  *dll_count = 0;
  *fn_total = 0;
  *ord_total = 0;
  if (n_dirs < 2 || !in_map(map_sz, dirs_off + 8, 8))
    return 0;
  if (pe_u32(p, map_sz, dirs_off + 8, &imp_rva) < 0 ||
      pe_u32(p, map_sz, dirs_off + 12, &imp_size) < 0)
    return 0;
  if (imp_rva == 0 || imp_size == 0)
    return 0;
  if (pe_rva_to_off(secs, nsec, size_of_headers, imp_rva, &imp_off) < 0)
    return -1;
  for (i = 0; i < PE_MAX_DLLS; i++) {
    uint32_t oft, name_rva, ft, tds, fc;
    uint64_t doff = imp_off + (uint64_t)i * 20;
    char dll[PE_NAME_CAP];
    if (pe_u32(p, map_sz, doff, &oft) < 0 ||
        pe_u32(p, map_sz, doff + 4, &tds) < 0 ||
        pe_u32(p, map_sz, doff + 8, &fc) < 0 ||
        pe_u32(p, map_sz, doff + 12, &name_rva) < 0 ||
        pe_u32(p, map_sz, doff + 16, &ft) < 0)
      return -1;
    if (oft == 0 && tds == 0 && fc == 0 && name_rva == 0 && ft == 0)
      break;
    {
      uint64_t name_off;
      if (pe_rva_to_off(secs, nsec, size_of_headers, name_rva,
                        &name_off) < 0 ||
          pe_cstr(p, map_sz, name_off, dll, sizeof(dll)) < 0)
        return -1;
    }
    if (emit) {
      if (*dll_count)
        putchar(',');
      printf("{\"dll\":\"");
      json_escape_print(dll);
      printf("\",\"functions\":[");
    }
    {
      int first = 1;
      uint32_t thunk_rva = oft ? oft : ft;
      if (pe_emit_thunks(p, map_sz, secs, nsec, size_of_headers,
                         is_plus, thunk_rva, fn_total, ord_total,
                         &first, emit) < 0)
        return -1;
    }
    if (emit)
      printf("]}");
    (*dll_count)++;
  }
  if (i >= PE_MAX_DLLS)
    return -1;
  return 0;
}

/* Parse a mapped PE32/PE32+ image; print JSON. Fail loud (rc 1). */
static int pe_parse(const unsigned char *p, size_t map_sz,
                    const char *path, long long fsize) {
  uint32_t pe_off, ts = 0, ptr_sym = 0, nsyms = 0;
  uint16_t machine = 0, nsec16 = 0, size_opt = 0, chars = 0;
  uint16_t opt_magic = 0, subsystem = 0;
  uint32_t entry_rva = 0, size_of_headers = 0, n_dirs = 0;
  uint64_t image_base = 0;
  int is_plus;
  uint64_t coff_off, opt_off, sec_off;
  pe_section_t secs[PE_MAX_SECTIONS];
  int i;

  if (map_sz < 64 || p[0] != 'M' || p[1] != 'Z')
    return pe_fail(path, "bad magic: not MZ (PE)");
  if (pe_u32(p, map_sz, 0x3c, &pe_off) < 0)
    return pe_fail(path, "truncated DOS header (e_lfanew)");
  coff_off = (uint64_t)pe_off + 4;
  if (!in_map(map_sz, pe_off, 4 + 20))
    return pe_fail(path, "truncated PE signature / COFF header");
  if (!(p[pe_off] == 'P' && p[pe_off + 1] == 'E' &&
        p[pe_off + 2] == 0 && p[pe_off + 3] == 0))
    return pe_fail(path, "bad magic: missing PE signature");
  if (pe_u16(p, map_sz, coff_off, &machine) < 0 ||
      pe_u16(p, map_sz, coff_off + 2, &nsec16) < 0 ||
      pe_u32(p, map_sz, coff_off + 4, &ts) < 0 ||
      pe_u32(p, map_sz, coff_off + 8, &ptr_sym) < 0 ||
      pe_u32(p, map_sz, coff_off + 12, &nsyms) < 0 ||
      pe_u16(p, map_sz, coff_off + 16, &size_opt) < 0 ||
      pe_u16(p, map_sz, coff_off + 18, &chars) < 0)
    return pe_fail(path, "truncated COFF header");
  if (nsec16 == 0 || nsec16 > PE_MAX_SECTIONS)
    return pe_fail(path, "unsupported section count (0 or >96)");
  opt_off = coff_off + 20;
  if (!in_map(map_sz, opt_off, size_opt) || size_opt < 70)
    return pe_fail(path, "truncated optional header");
  if (pe_u16(p, map_sz, opt_off, &opt_magic) < 0)
    return pe_fail(path, "truncated optional header magic");
  if (opt_magic == PE_OPT_MAGIC_32PLUS)
    is_plus = 1;
  else if (opt_magic == PE_OPT_MAGIC_32)
    is_plus = 0;
  else
    return pe_fail(path, "unsupported optional header magic "
                         "(not PE32/PE32+)");
  if (pe_u32(p, map_sz, opt_off + 16, &entry_rva) < 0)
    return pe_fail(path, "truncated entry point");
  if (is_plus) {
    if (pe_u64(p, map_sz, opt_off + 24, &image_base) < 0)
      return pe_fail(path, "truncated image base");
  } else {
    uint32_t ib32;
    if (pe_u32(p, map_sz, opt_off + 28, &ib32) < 0)
      return pe_fail(path, "truncated image base");
    image_base = ib32;
  }
  if (pe_u32(p, map_sz, opt_off + 60, &size_of_headers) < 0 ||
      pe_u16(p, map_sz, opt_off + 68, &subsystem) < 0)
    return pe_fail(path, "truncated optional header fields");
  {
    uint64_t n_dirs_off = opt_off + (is_plus ? 108 : 92);
    uint64_t dirs_off = opt_off + (is_plus ? 112 : 96);
    if (size_opt >= (uint32_t)(is_plus ? 112 : 96) &&
        pe_u32(p, map_sz, n_dirs_off, &n_dirs) == 0) {
      /* data directories available at dirs_off */
    } else {
      n_dirs = 0;
    }
    sec_off = opt_off + size_opt;
    if (!in_map(map_sz, sec_off, (uint64_t)nsec16 * 40))
      return pe_fail(path, "truncated section table");
    for (i = 0; i < nsec16; i++) {
      uint64_t so = sec_off + (uint64_t)i * 40;
      memcpy(secs[i].name, p + so, 8);
      secs[i].name[8] = '\0';
      pe_u32(p, map_sz, so + 8, &secs[i].vsize);
      pe_u32(p, map_sz, so + 12, &secs[i].vaddr);
      pe_u32(p, map_sz, so + 16, &secs[i].raw_size);
      pe_u32(p, map_sz, so + 20, &secs[i].raw_off);
      pe_u32(p, map_sz, so + 36, &secs[i].characteristics);
      /* Long name "/N" → COFF string table at symtab end. */
      if (secs[i].name[0] == '/' && isdigit(secs[i].name[1])) {
        uint64_t strtab = (uint64_t)ptr_sym + (uint64_t)nsyms * 18;
        uint32_t str_sz = 0;
        long noff = strtol(secs[i].name + 1, NULL, 10);
        char longname[64];
        if (strtab && pe_u32(p, map_sz, strtab, &str_sz) == 0 &&
            str_sz >= 4 && in_map(map_sz, strtab, str_sz) &&
            noff >= 4 && (uint64_t)noff < str_sz &&
            pe_cstr(p, map_sz, strtab + (uint64_t)noff, longname,
                    sizeof(longname)) == 0 &&
            strlen(longname) < sizeof(secs[i].name)) {
          memcpy(secs[i].name, longname, strlen(longname) + 1);
        }
      }
    }
    /* Validate imports BEFORE any printing: a truncated table must
     * yield one clean loud error, never a partial JSON prefix. */
    {
      int vc = 0, vf = 0, vo = 0;
      if (pe_walk_imports(p, map_sz, secs, nsec16, size_of_headers,
                          is_plus, dirs_off, n_dirs, 0, &vc,
                          &vf, &vo) < 0)
        return pe_fail(path, "truncated/corrupt import table");
    }
    printf("{\"op\":\"pe\",\"ok\":true,\"format\":\"%s\",\"path\":\"",
           is_plus ? "pe32plus" : "pe32");
    json_escape_print(path);
    printf("\",\"size\":%lld,", fsize);
    printf("\"machine\":%u,\"machine_name\":\"%s\",", machine,
           pe_machine_name(machine));
    printf("\"timestamp\":%u,\"coff_characteristics\":\"0x%04x\",", ts,
           chars);
    printf("\"pe_optional_magic\":\"0x%03x\",", opt_magic);
    printf("\"entry_rva\":\"0x%x\",\"image_base\":\"0x%llx\",",
           entry_rva, (unsigned long long)image_base);
    printf("\"entry_va\":\"0x%llx\",",
           (unsigned long long)(image_base + entry_rva));
    printf("\"subsystem\":%u,\"subsystem_name\":\"%s\",", subsystem,
           pe_subsystem_name(subsystem));
    printf("\"sections\":[");
    for (i = 0; i < nsec16; i++) {
      if (i)
        putchar(',');
      printf("{\"name\":\"");
      json_escape_print(secs[i].name);
      printf("\",\"vsize\":%u,\"vaddr\":\"0x%x\",\"raw_size\":%u,"
             "\"raw_off\":%u,\"characteristics\":\"0x%08x\"}",
             secs[i].vsize, secs[i].vaddr, secs[i].raw_size,
             secs[i].raw_off, secs[i].characteristics);
    }
    {
      int dll_count = 0, fn_total = 0, ord_total = 0;
      printf("],\"section_count\":%u", nsec16);
      /* Import directory = data dir index 1. Pre-pass above
       * guarantees this emit walk stays in-bounds. */
      printf(",\"imports\":[");
      pe_walk_imports(p, map_sz, secs, nsec16, size_of_headers,
                      is_plus, dirs_off, n_dirs, 1, &dll_count,
                      &fn_total, &ord_total);
      printf("],\"import_dll_count\":%d,", dll_count);
      printf("\"import_function_count\":%d,", fn_total);
      printf("\"import_ordinal_count\":%d", ord_total);
    }
    printf(",\"claim\":\"local_pe_probe_not_ghidra\"}\n");
  }
  return 0;
}

static int run_pe(const char *path) {
  int fd = open(path, O_RDONLY);
  struct stat st;
  void *map;
  int rc;
  if (fd < 0) {
    fprintf(stderr, "open: %s\n", strerror(errno));
    return 1;
  }
  if (fstat(fd, &st) < 0) {
    close(fd);
    return 1;
  }
  if (st.st_size < 64) {
    close(fd);
    return pe_fail(path, "too small for PE (DOS header)");
  }
  map = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
  close(fd);
  if (map == MAP_FAILED) {
    fprintf(stderr, "mmap: %s\n", strerror(errno));
    return 1;
  }
  rc = pe_parse(map, (size_t)st.st_size, path, (long long)st.st_size);
  munmap(map, (size_t)st.st_size);
  return rc;
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
    } else if (!strcmp(argv[i], "--pe") && i + 1 < argc) {
      op = "pe";
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
              "spark-binary-probe --understand|--exports|--elf|--pe|"
              "--disasm PATH [--focus …] [--offset] [--length]\n");
      return 0;
    }
  }
  if (!op || !path) {
    fprintf(stderr,
            "need --understand|--exports|--elf|--pe|--disasm PATH\n");
    return 2;
  }
  if (!strcmp(op, "disasm"))
    return run_disasm(path, off, len);
  if (!strcmp(op, "pe"))
    return run_pe(path);
  if (!strcmp(op, "exports"))
    return understand(path, focus, 1, 0);
  if (!strcmp(op, "elf"))
    return understand(path, focus, 0, 1);
  return understand(path, focus, 0, 0);
}
