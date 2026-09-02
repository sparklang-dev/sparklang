/* Exact dry fixtures for embed/retrieve (LANGUAGE.md).
 * Compact JSON mirrors examples/fixtures/rag JSON — no inventing. */
#include "dry_rag.h"

#include <stddef.h>
#include <string.h>

static const char DRY_EMBED[] =
    "{\"object\":\"list\",\"model\":\"embed-rag\","
    "\"data\":[{\"object\":\"embedding\",\"index\":0,"
    "\"embedding\":[0.01,-0.02,0.03,0.0]}],"
    "\"usage\":{\"prompt_tokens\":8,\"total_tokens\":8},"
    "\"note\":\"dry-run fixture — not a live TEI vector\"}";

static const char DRY_RETRIEVE[] =
    "{\"chunks\":[{"
    "\"chunk_id\":\"docs/LANGUAGE.md#embed\","
    "\"content\":\"<<<RAG_CHUNK>>> embed text to vec "
    "<<<END_RAG_CHUNK>>>\",\"score\":0.91,"
    "\"source\":\"spark-docs\",\"title\":\"LANGUAGE.md\"}],"
    "\"by_source\":{\"spark-docs\":1},"
    "\"gateway_available\":true,\"audience\":\"operator\","
    "\"project\":\"docs\",\"backends_used\":[\"fixture\"],"
    "\"cache_hit\":false,"
    "\"crag\":{\"grade\":\"correct\",\"retried\":false},"
    "\"note\":\"dry-run fixture — gateway CRAG for operator\"}";

static const char DRY_RETRIEVE_EMPTY[] =
    "{\"chunks\":[],\"by_source\":{},"
    "\"gateway_available\":true,\"audience\":\"operator\","
    "\"project\":\"docs\",\"backends_used\":[\"fixture\"],"
    "\"cache_hit\":false,"
    "\"crag\":{\"grade\":\"incorrect\",\"retried\":false},"
    "\"note\":\"dry-run empty — no matching fixture cue\"}";

static int contains_ci(const char *hay, const char *needle)
{
  size_t nlen;
  size_t hlen;
  size_t i;
  size_t j;
  if (!hay || !needle || !needle[0])
    return 0;
  nlen = strlen(needle);
  hlen = strlen(hay);
  if (nlen > hlen)
    return 0;
  for (i = 0; i + nlen <= hlen; i++) {
    for (j = 0; j < nlen; j++) {
      char a = hay[i + j];
      char b = needle[j];
      if (a >= 'A' && a <= 'Z')
        a = (char)(a + 32);
      if (b >= 'A' && b <= 'Z')
        b = (char)(b + 32);
      if (a != b)
        break;
    }
    if (j == nlen)
      return 1;
  }
  return 0;
}

const char *spark_pick_embed(const char *text)
{
  (void)text;
  return DRY_EMBED;
}

const char *spark_pick_retrieve(const char *query)
{
  if (!query || !query[0])
    return DRY_RETRIEVE_EMPTY;
  if (contains_ci(query, "embed") || contains_ci(query, "retrieve") ||
      contains_ci(query, "dry-run") || contains_ci(query, "language") ||
      contains_ci(query, "rag") || contains_ci(query, "gateway"))
    return DRY_RETRIEVE;
  return DRY_RETRIEVE_EMPTY;
}
