/* Shared dry classify fixtures — same strings as vm.c pick_classify
 * / asm pick_classify_ptr. Do not invent new labels. */
#ifndef SPARK_DRY_CLASSIFY_H
#define SPARK_DRY_CLASSIFY_H

const char *spark_pick_classify(const char *text);

#endif
