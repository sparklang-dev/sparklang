#ifndef SPARK_GROUND_OR_IDK_H
#define SPARK_GROUND_OR_IDK_H

/*
 * Ground-or-IDK for live ask. Inventable prompts without SoT
 * must not reach the gateway. Twin of
 * python/sparklang/abstain/inventable.py
 *
 * SPARK_ASK_GROUND=0  opt out
 * SPARK_ASK_SOT_OK=1  SoT already verified
 * SPARK_ASK_IDK       IDK string (default: I don't know.)
 */

int spark_looks_inventable(const char *prompt);
int spark_ground_should_idk(const char *prompt, int sot_ok);
const char *spark_idk_text(void);

#endif
