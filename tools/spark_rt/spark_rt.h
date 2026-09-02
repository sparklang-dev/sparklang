/* Spark runtime helpers — real I/O / parse (linked into ./spark). */
#ifndef SPARK_RT_H
#define SPARK_RT_H

#include <stddef.h>

void rt_init(void);

/* Bindings (let / ->) */
int rt_let(const char *line);
int rt_bind_arrow(const char *line, const char *value, size_t vlen);
const char *rt_get_var(const char *name);
int rt_print_ident(const char *line);

/* Language ops — print to stdout; return 0 ok, non-zero fail */
int rt_ask(const char *line);
int rt_classify(const char *line);
int rt_extract(const char *line);
int rt_listen(const char *line);
int rt_speak(const char *line);
int rt_review(const char *line);
int rt_builder(const char *line);
int rt_implement(const char *line);
int rt_model(const char *line);
int rt_cuda(const char *line);
int rt_memory(const char *line);
int rt_binary(const char *line);
int rt_network(const char *line);
int rt_os(const char *line);

int rt_looks_like_field(const char *line);

#endif
