# host/c — SparkLang C FFI

Call the `spark` ELF from C. Dry-run is the default.

```c
#include "host/c/sparklang.h"

SparkRunResult r;
if (spark_run_path("examples/hello.spark", 0, &r) != 0)
    return 1;
fputs(r.stdout_s, stdout);
spark_run_free(&r);
```

```bash
cc -O2 -Wall -Wextra -o examples/c/host_embed \
  examples/c/host_embed.c host/c/sparklang.c
./examples/c/host_embed
make test-host-embed
```

Never `system()`. Discovery: `SPARK_BIN`, `./spark`, `PATH`.
JavaScript: `js/sparklang`. Handshake: `./spark --embed`.
