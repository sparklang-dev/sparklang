/* Pack SPARK_BC bytes (encoding, not a language compiler). */
#ifndef SPARK_BC_WRITE_H
#define SPARK_BC_WRITE_H

#include "bc_read.h"

int spark_bc_write(const char *path, const SparkBc *bc);

#endif
