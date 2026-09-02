/* Shared dry ask fixtures — same strings as vm.c pick_ask_reply
 * / asm pick_ask_reply_ptr. Do not invent new reply prose. */
#ifndef SPARK_DRY_ASK_H
#define SPARK_DRY_ASK_H

const char *spark_pick_ask_reply(const char *prompt);

#endif
