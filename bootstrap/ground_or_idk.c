#include "bootstrap/ground_or_idk.h"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

static const char *inventable_markers[] = {
	"mayor of",
	"mayor",
	"who is the current",
	"who is the",
	"who was the",
	"who called",
	"who worked",
	"who won",
	"who is president",
	"price at",
	"how much",
	"how many dollars",
	"dryer start",
	"card balance",
	"right now",
	"this minute",
	"this hour",
	"serial number",
	"revenue for",
	"exact unpaid",
	"live gps",
	"badge id",
	"cash in drawer",
	"winning lottery",
	"will aapl",
	"stock price",
	"close at friday",
	"weather",
	"forecast",
	"temperature in",
	"your hours",
	"open until",
	"open at",
	"are you open",
	"phone number",
	"phone #",
	"capital of",
	"population of",
	"born in",
	"when was",
	"when did",
	"how old is",
	"latest score",
	"election result",
	NULL,
};

static const char *refuse_markers[] = {
	"ssn",
	"password",
	"api key",
	"jwt",
	"private key",
	"routing number",
	"ein",
	"cvv",
	"2fa",
	"otp",
	"wifi password",
	"door code",
	"alarm",
	"fingerprint",
	"home street",
	"cell number",
	"prescription",
	NULL,
};

static const char *safe_code[] = {
	"explain",
	"rename",
	"refactor",
	"unit test",
	"endpoint",
	"debug",
	"translate",
	"summar",
	"reply with",
	NULL,
};

static int contains_ci(const char *hay, const char *needle)
{
	size_t n, i, j;
	unsigned char a, b;

	if (!hay || !needle || !*needle)
		return 0;
	n = strlen(needle);
	for (i = 0; hay[i]; i++) {
		for (j = 0; j < n; j++) {
			a = (unsigned char)hay[i + j];
			b = (unsigned char)needle[j];
			if (!a)
				return 0;
			if (tolower(a) != tolower(b))
				break;
		}
		if (j == n)
			return 1;
	}
	return 0;
}

static int looks_price(const char *s)
{
	const char *p;

	if (!s)
		return 0;
	p = strchr(s, '$');
	if (p) {
		p++;
		while (*p == ' ' || *p == '\t')
			p++;
		if (isdigit((unsigned char)*p))
			return 1;
	}
	for (p = s; *p; p++) {
		if (isdigit((unsigned char)*p) && p[1] == '.' &&
		    isdigit((unsigned char)p[2]) &&
		    isdigit((unsigned char)p[3]))
			return 1;
	}
	return 0;
}

static int looks_phone(const char *s)
{
	int digits = 0;
	const char *p;

	if (!s)
		return 0;
	for (p = s; *p; p++) {
		if (isdigit((unsigned char)*p))
			digits++;
		else if (digits > 0 && digits < 10 &&
			 *p != '-' && *p != '.' && *p != ' ' &&
			 *p != '(' && *p != ')')
			digits = 0;
		if (digits >= 10)
			return 1;
	}
	return 0;
}

static const char *find_ci(const char *hay, const char *needle)
{
	size_t n, i, j;

	if (!hay || !needle || !*needle)
		return NULL;
	n = strlen(needle);
	for (i = 0; hay[i]; i++) {
		for (j = 0; j < n; j++) {
			if (!hay[i + j])
				return NULL;
			if (tolower((unsigned char)hay[i + j]) !=
			    tolower((unsigned char)needle[j]))
				break;
		}
		if (j == n)
			return hay + i;
	}
	return NULL;
}

static int is_closed_math(const char *s)
{
	const char *hit, *p;
	int skip;

	if (!s)
		return 0;
	hit = find_ci(s, "what is");
	skip = 7;
	if (!hit) {
		hit = find_ci(s, "what's");
		skip = 6;
	}
	if (!hit)
		return 0;
	p = hit + skip;
	while (*p == ' ' || *p == '\t')
		p++;
	if (!isdigit((unsigned char)*p))
		return 0;
	while (isdigit((unsigned char)*p))
		p++;
	while (*p == ' ')
		p++;
	if (*p != '+' && *p != '-' && *p != '*' &&
	    *p != '/' && *p != 'x')
		return 0;
	p++;
	while (*p == ' ')
		p++;
	return isdigit((unsigned char)*p) ? 1 : 0;
}

static int is_safe_code(const char *s)
{
	int i;

	if (!s)
		return 0;
	if (strcmp(s, "ping") == 0 || strcmp(s, "pong") == 0)
		return 1;
	for (i = 0; safe_code[i]; i++) {
		if (contains_ci(s, safe_code[i]))
			return 1;
	}
	return 0;
}

int spark_looks_inventable(const char *prompt)
{
	int i;

	if (!prompt || !*prompt)
		return 0;
	for (i = 0; refuse_markers[i]; i++) {
		if (contains_ci(prompt, refuse_markers[i]))
			return 1;
	}
	if (looks_price(prompt) || looks_phone(prompt))
		return 1;
	if (is_closed_math(prompt))
		return 0;
	for (i = 0; inventable_markers[i]; i++) {
		if (contains_ci(prompt, inventable_markers[i]))
			return 1;
	}
	if (is_safe_code(prompt))
		return 0;
	return 0;
}

int spark_ground_should_idk(const char *prompt, int sot_ok)
{
	const char *env;

	env = getenv("SPARK_ASK_GROUND");
	if (env && strcmp(env, "0") == 0)
		return 0;
	if (sot_ok)
		return 0;
	env = getenv("SPARK_ASK_SOT_OK");
	if (env && strcmp(env, "1") == 0)
		return 0;
	return spark_looks_inventable(prompt);
}

const char *spark_idk_text(void)
{
	const char *env;

	env = getenv("SPARK_ASK_IDK");
	if (env && *env)
		return env;
	return "I don't know.";
}
