#ifndef SPARK_DRY_RAG_H
#define SPARK_DRY_RAG_H

/* Dry fixtures for embed / retrieve — match examples/fixtures/rag/. */

const char *spark_pick_embed(const char *text);
const char *spark_pick_retrieve(const char *query);

#endif
