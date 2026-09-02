# Spark portable runtime kit — build bootstrap VM + sparkasm on macOS / Windows (Git Bash)
CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra

BOOT_SRCS = main.c vm.c engine_parse.c engine_css.c engine_layout.c \
	engine_paint.c engine_show.c engine_render.c

.PHONY: all spark-bootstrap sparkasm clean

all: spark-bootstrap sparkasm

spark-bootstrap: $(BOOT_SRCS) vm.h engine_parse.h engine_css.h \
	engine_layout.h engine_paint.h engine_show.h engine_render.h
	$(CC) $(CFLAGS) -o spark-bootstrap $(BOOT_SRCS)

sparkasm:
	$(MAKE) -C ../sparkasm

clean:
	rm -f spark-bootstrap
	$(MAKE) -C ../sparkasm clean
