#ifndef SPARK_DRY_OPS_H
#define SPARK_DRY_OPS_H

#include <stddef.h>

const char *spark_dry_transcript(void);
const char *spark_dry_person(void);
const char *spark_pick_review_report(const char *heuristic);
int spark_write_stub_wav(const char *path);

const char *spark_br_default_script(void);
const char *spark_br_default_url(void);
int spark_ensure_browser_dirs(void);
int spark_write_session_json(const char *script, const char *url,
                             char *json, size_t jcap);
int spark_format_browser_goto_json(const char *url, char *json, size_t jcap);
const char *spark_mitm_enable_dry_json(void);
int spark_write_mitm_json(void);

#endif
