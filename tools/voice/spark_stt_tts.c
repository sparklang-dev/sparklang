/*
 * spark-stt-tts — live listen (STT) / speak (TTS) companion for Spark.
 *
 * Asm --dry-run never forks this. make test stays offline.
 *
 * Local (default, no vendor net):
 *   listen  — open WAV or capture mic (arecord); transcript via
 *             SPARK_STT_CMD, sidecar .intent.txt/.txt, or local
 *             openai-whisper (tiny.en) when importable — else fail loud
 *   speak   — built-in PCM synthesizer → real RIFF/WAVE; optional aplay
 *
 * Network vendors (OFF by default):
 *   SPARK_STT_NET=1 + SPARK_STT_URL  — POST audio, read transcript
 *   SPARK_TTS_NET=1 + SPARK_TTS_URL  — POST text, write audio/wav
 *   SPARK_SPEECH_NET=1 enables both STT and TTS net gates
 *
 * Env:
 *   SPARK_STT_URL / SPARK_TTS_URL
 *   SPARK_STT_CMD / SPARK_TTS_CMD  (shell; %i in, %o out)
 *   SPARK_STT_KEY / SPARK_TTS_KEY / OPENAI_API_KEY (Bearer, never printed)
 *   SPARK_WHISPER_MODEL (default tiny.en); SPARK_STT_WHISPER=0 disables
 *   SPARK_MIC_SECONDS (default 3)
 *   SPARK_TTS_PLAY=1 — aplay after speak
 */

#define _GNU_SOURCE
#include <arpa/inet.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define EXIT_OK 0
#define EXIT_USAGE 1
#define EXIT_GATED 2
#define EXIT_IO 3
#define EXIT_CRED 4
#define MAX_BODY (8 << 20)
#define MAX_TEXT (1 << 18)
#define RATE 16000

static void die(const char *msg, int code)
{
	fprintf(stderr, "spark-stt-tts: %s\n", msg);
	exit(code);
}

static int env_truthy(const char *name)
{
	const char *v = getenv(name);

	if (!v || !*v)
		return 0;
	if (!strcmp(v, "1") || !strcasecmp(v, "true") ||
	    !strcasecmp(v, "yes") || !strcasecmp(v, "on"))
		return 1;
	return 0;
}

static int net_stt_allowed(void)
{
	return env_truthy("SPARK_STT_NET") ||
	       env_truthy("SPARK_SPEECH_NET");
}

static int net_tts_allowed(void)
{
	return env_truthy("SPARK_TTS_NET") ||
	       env_truthy("SPARK_SPEECH_NET");
}

static char *read_all(const char *path, size_t *out_n)
{
	FILE *f = fopen(path, "rb");
	char *buf;
	long n;

	if (!f)
		return NULL;
	if (fseek(f, 0, SEEK_END) != 0) {
		fclose(f);
		return NULL;
	}
	n = ftell(f);
	if (n < 0 || n > MAX_BODY) {
		fclose(f);
		return NULL;
	}
	rewind(f);
	buf = malloc((size_t)n + 1);
	if (!buf) {
		fclose(f);
		return NULL;
	}
	if (fread(buf, 1, (size_t)n, f) != (size_t)n) {
		free(buf);
		fclose(f);
		return NULL;
	}
	buf[n] = 0;
	fclose(f);
	if (out_n)
		*out_n = (size_t)n;
	return buf;
}

static int write_all(const char *path, const void *buf, size_t n)
{
	FILE *f = fopen(path, "wb");

	if (!f)
		return -1;
	if (fwrite(buf, 1, n, f) != n) {
		fclose(f);
		return -1;
	}
	fclose(f);
	return 0;
}

static int is_riff_wav(const unsigned char *p, size_t n)
{
	return n >= 12 && !memcmp(p, "RIFF", 4) && !memcmp(p + 8, "WAVE", 4);
}

static int run_cmd(char *const argv[])
{
	pid_t pid = fork();
	int st;

	if (pid < 0)
		return -1;
	if (pid == 0) {
		execvp(argv[0], argv);
		_exit(127);
	}
	if (waitpid(pid, &st, 0) < 0)
		return -1;
	if (!WIFEXITED(st) || WEXITSTATUS(st) != 0)
		return -1;
	return 0;
}

static int expand_cmd(const char *tmpl, const char *in_path,
		      const char *out_path, char *dst, size_t dstn)
{
	size_t w = 0;
	const char *p = tmpl;

	while (*p && w + 1 < dstn) {
		if (*p == '%' && (p[1] == 'i' || p[1] == 'o')) {
			const char *rep = (p[1] == 'i') ? in_path : out_path;
			size_t rl;

			if (!rep)
				rep = "";
			rl = strlen(rep);
			if (w + rl >= dstn)
				return -1;
			memcpy(dst + w, rep, rl);
			w += rl;
			p += 2;
			continue;
		}
		dst[w++] = *p++;
	}
	dst[w] = 0;
	return 0;
}

static int run_shell(const char *cmd)
{
	pid_t pid = fork();
	int st;

	if (pid < 0)
		return -1;
	if (pid == 0) {
		execl("/bin/sh", "sh", "-c", cmd, (char *)NULL);
		_exit(127);
	}
	if (waitpid(pid, &st, 0) < 0)
		return -1;
	if (!WIFEXITED(st) || WEXITSTATUS(st) != 0)
		return -1;
	return 0;
}

/* ---------- URL / HTTP (same spirit as spark-ask-http) ---------- */

struct url_parts {
	int https;
	char host[256];
	char path[1024];
	int port;
};

static int parse_url(const char *url, struct url_parts *u)
{
	const char *p = url;

	memset(u, 0, sizeof(*u));
	u->port = 80;
	strcpy(u->path, "/");
	if (!strncmp(p, "https://", 8)) {
		u->https = 1;
		u->port = 443;
		p += 8;
	} else if (!strncmp(p, "http://", 7)) {
		p += 7;
	} else
		return -1;
	{
		size_t i = 0;
		while (*p && *p != '/' && *p != ':' && i + 1 < sizeof(u->host))
			u->host[i++] = *p++;
		u->host[i] = 0;
		if (*p == ':') {
			p++;
			u->port = atoi(p);
			while (*p && *p != '/')
				p++;
		}
		if (*p == '/') {
			strncpy(u->path, p, sizeof(u->path) - 1);
			u->path[sizeof(u->path) - 1] = 0;
		}
	}
	return u->host[0] ? 0 : -1;
}

static const char *bearer_key(const char *specific)
{
	const char *k = getenv(specific);

	if (k && *k)
		return k;
	k = getenv("OPENAI_API_KEY");
	if (k && *k)
		return k;
	k = getenv("SPARK_GATEWAY_KEY");
	if (k && *k)
		return k;
	return NULL;
}

static int http_post_raw(const char *url, const char *key,
			 const char *ctype, const void *body, size_t body_n,
			 char *resp, size_t resp_cap, size_t *resp_n)
{
	struct url_parts u;
	char header[2048];
	int hdr_n;
	int fd = -1;
	struct addrinfo hints, *ai = NULL, *rp;
	char portbuf[16];
	size_t got = 0;
	ssize_t n;
	int status = -1;

	if (parse_url(url, &u) != 0)
		die("bad URL", EXIT_USAGE);
	if (u.https) {
		/* curl for TLS — never print key */
		char tmp_in[] = "/tmp/spark-speech-in.XXXXXX";
		char tmp_out[] = "/tmp/spark-speech-out.XXXXXX";
		int ifd, ofd;
		char cmd[4096];
		char *outb;
		size_t on;

		ifd = mkstemp(tmp_in);
		ofd = mkstemp(tmp_out);
		if (ifd < 0 || ofd < 0)
			die("mkstemp", EXIT_IO);
		close(ofd);
		if (write(ifd, body, body_n) != (ssize_t)body_n) {
			close(ifd);
			die("write body temp", EXIT_IO);
		}
		close(ifd);
		if (key && *key)
			snprintf(cmd, sizeof(cmd),
				 "curl -sS -o '%s' -w '\\n__HTTP__%%{http_code}\\n' "
				 "-H 'Content-Type: %s' -H 'Authorization: Bearer %s' "
				 "--data-binary @'%s' '%s'",
				 tmp_out, ctype, key, tmp_in, url);
		else
			snprintf(cmd, sizeof(cmd),
				 "curl -sS -o '%s' -w '\\n__HTTP__%%{http_code}\\n' "
				 "-H 'Content-Type: %s' "
				 "--data-binary @'%s' '%s'",
				 tmp_out, ctype, tmp_in, url);
		if (run_shell(cmd) != 0) {
			unlink(tmp_in);
			unlink(tmp_out);
			die("curl https failed", EXIT_IO);
		}
		outb = read_all(tmp_out, &on);
		unlink(tmp_in);
		unlink(tmp_out);
		if (!outb)
			die("read curl out", EXIT_IO);
		{
			char *mark = strstr(outb, "\n__HTTP__");
			if (mark) {
				*mark = 0;
				status = atoi(mark + 9);
				on = (size_t)(mark - outb);
			}
		}
		if (status == 401) {
			free(outb);
			die("credential unavailable", EXIT_CRED);
		}
		if (status > 0 && (status < 200 || status >= 300)) {
			free(outb);
			die("HTTP error from vendor", EXIT_IO);
		}
		if (on >= resp_cap)
			on = resp_cap - 1;
		memcpy(resp, outb, on);
		resp[on] = 0;
		free(outb);
		if (resp_n)
			*resp_n = on;
		return 0;
	}

	memset(&hints, 0, sizeof(hints));
	hints.ai_socktype = SOCK_STREAM;
	snprintf(portbuf, sizeof(portbuf), "%d", u.port);
	if (getaddrinfo(u.host, portbuf, &hints, &ai) != 0)
		die("DNS failed", EXIT_IO);
	for (rp = ai; rp; rp = rp->ai_next) {
		fd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
		if (fd < 0)
			continue;
		if (connect(fd, rp->ai_addr, rp->ai_addrlen) == 0)
			break;
		close(fd);
		fd = -1;
	}
	freeaddrinfo(ai);
	if (fd < 0)
		die("connect failed", EXIT_IO);

	if (key && *key)
		hdr_n = snprintf(header, sizeof(header),
				 "POST %s HTTP/1.0\r\nHost: %s\r\n"
				 "Content-Type: %s\r\n"
				 "Authorization: Bearer %s\r\n"
				 "Content-Length: %zu\r\n"
				 "Connection: close\r\n\r\n",
				 u.path, u.host, ctype, key, body_n);
	else
		hdr_n = snprintf(header, sizeof(header),
				 "POST %s HTTP/1.0\r\nHost: %s\r\n"
				 "Content-Type: %s\r\n"
				 "Content-Length: %zu\r\n"
				 "Connection: close\r\n\r\n",
				 u.path, u.host, ctype, body_n);
	if (write(fd, header, (size_t)hdr_n) != hdr_n ||
	    write(fd, body, body_n) != (ssize_t)body_n) {
		close(fd);
		die("send failed", EXIT_IO);
	}
	while (got + 1 < resp_cap) {
		n = read(fd, resp + got, resp_cap - 1 - got);
		if (n <= 0)
			break;
		got += (size_t)n;
	}
	resp[got] = 0;
	close(fd);
	if (!strncmp(resp, "HTTP/", 5)) {
		status = atoi(strchr(resp, ' ') + 1);
		if (status == 401)
			die("credential unavailable", EXIT_CRED);
		if (status < 200 || status >= 300)
			die("HTTP error from vendor", EXIT_IO);
	}
	if (resp_n)
		*resp_n = got;
	return 0;
}

static char *body_after_headers(char *resp)
{
	char *p = strstr(resp, "\r\n\r\n");

	if (p)
		return p + 4;
	p = strstr(resp, "\n\n");
	return p ? p + 2 : resp;
}

static int extract_json_text(const char *json, char *out, size_t out_cap)
{
	const char *keys[] = { "\"text\"", "\"transcript\"",
			       "\"content\"", NULL };
	size_t k;

	for (k = 0; keys[k]; k++) {
		const char *p = strstr(json, keys[k]);
		size_t i = 0;

		if (!p)
			continue;
		p = strchr(p, ':');
		if (!p)
			continue;
		p++;
		while (*p == ' ' || *p == '\t')
			p++;
		if (*p != '"')
			continue;
		p++;
		while (*p && i + 1 < out_cap) {
			if (*p == '\\' && p[1]) {
				p++;
				if (*p == 'n')
					out[i++] = '\n';
				else
					out[i++] = *p;
				p++;
				continue;
			}
			if (*p == '"')
				break;
			out[i++] = *p++;
		}
		out[i] = 0;
		return i > 0 ? 0 : -1;
	}
	return -1;
}

/* ---------- mic / play ---------- */

static int capture_mic(const char *wav_path, int seconds)
{
	char sec[16];
	char *argv[] = {
		"arecord", "-q", "-f", "S16_LE", "-r", "16000", "-c", "1",
		"-d", sec, (char *)wav_path, NULL
	};

	snprintf(sec, sizeof(sec), "%d", seconds > 0 ? seconds : 3);
	if (run_cmd(argv) != 0)
		die("arecord mic capture failed", EXIT_IO);
	return 0;
}

static int play_wav(const char *wav_path)
{
	char *argv[] = { "aplay", "-q", (char *)wav_path, NULL };

	if (run_cmd(argv) != 0)
		die("aplay failed", EXIT_IO);
	return 0;
}

/* ---------- local TTS synthesizer (real PCM, not stub marker) ---------- */

static void write_u32_le(unsigned char *p, unsigned v)
{
	p[0] = (unsigned char)(v & 0xff);
	p[1] = (unsigned char)((v >> 8) & 0xff);
	p[2] = (unsigned char)((v >> 16) & 0xff);
	p[3] = (unsigned char)((v >> 24) & 0xff);
}

static void write_u16_le(unsigned char *p, unsigned v)
{
	p[0] = (unsigned char)(v & 0xff);
	p[1] = (unsigned char)((v >> 8) & 0xff);
}

static int synth_wav(const char *text, const char *out_path)
{
	size_t len = text ? strlen(text) : 0;
	size_t i, s;
	int samples_per_char = RATE / 8; /* 125 ms */
	size_t n_samples;
	size_t data_bytes;
	size_t file_n;
	unsigned char *buf;
	short *pcm;
	double t;

	if (len == 0)
		len = 1;
	if (len > 4096)
		len = 4096;
	n_samples = len * (size_t)samples_per_char + RATE / 10;
	data_bytes = n_samples * 2;
	file_n = 44 + data_bytes;
	buf = calloc(1, file_n);
	if (!buf)
		die("oom", EXIT_IO);
	memcpy(buf, "RIFF", 4);
	write_u32_le(buf + 4, (unsigned)(file_n - 8));
	memcpy(buf + 8, "WAVEfmt ", 8);
	write_u32_le(buf + 16, 16);
	write_u16_le(buf + 20, 1);
	write_u16_le(buf + 22, 1);
	write_u32_le(buf + 24, RATE);
	write_u32_le(buf + 28, RATE * 2);
	write_u16_le(buf + 32, 2);
	write_u16_le(buf + 34, 16);
	memcpy(buf + 36, "data", 4);
	write_u32_le(buf + 40, (unsigned)data_bytes);
	pcm = (short *)(buf + 44);

	for (i = 0; i < len; i++) {
		unsigned char c = (unsigned char)(text ? text[i] : ' ');
		double base = 220.0 + (double)(c % 48) * 12.0;
		double amp = isspace(c) ? 0.0 : 0.35;

		for (s = 0; s < (size_t)samples_per_char; s++) {
			t = (double)s / (double)RATE;
			pcm[i * (size_t)samples_per_char + s] =
			    (short)(amp * 30000.0 *
				    sin(2.0 * 3.141592653589793 * base * t));
		}
	}
	if (write_all(out_path, buf, file_n) != 0) {
		free(buf);
		die("write wav failed", EXIT_IO);
	}
	free(buf);
	return 0;
}

/* ---------- STT paths ---------- */

static int try_sidecar(const char *wav_path, char *out, size_t out_cap)
{
	char side[512];
	size_t n, base_len;
	const char *dot;
	char *txt;
	size_t tn;
	static const char *suf[] = { ".intent.txt", ".txt", ".transcript.txt",
				     NULL };
	size_t i;

	strncpy(side, wav_path, sizeof(side) - 1);
	side[sizeof(side) - 1] = 0;
	dot = strrchr(side, '.');
	if (dot && strcasecmp(dot, ".wav") == 0)
		base_len = (size_t)(dot - side);
	else
		base_len = strlen(side);
	for (i = 0; suf[i]; i++) {
		if (base_len + strlen(suf[i]) >= sizeof(side))
			continue;
		side[base_len] = 0;
		strcat(side, suf[i]);
		txt = read_all(side, &tn);
		if (!txt)
			continue;
		while (tn && (txt[tn - 1] == '\n' || txt[tn - 1] == '\r'))
			txt[--tn] = 0;
		if (tn == 0) {
			free(txt);
			continue;
		}
		if (tn >= out_cap)
			tn = out_cap - 1;
		memcpy(out, txt, tn);
		out[tn] = 0;
		free(txt);
		return 0;
	}
	(void)n;
	return -1;
}

static int stt_via_cmd(const char *wav_path, char *out, size_t out_cap)
{
	const char *tmpl = getenv("SPARK_STT_CMD");
	char cmd[4096];
	char tmp_out[] = "/tmp/spark-stt-out.XXXXXX";
	int fd;
	char *txt;
	size_t tn;

	if (!tmpl || !*tmpl)
		return -1;
	fd = mkstemp(tmp_out);
	if (fd < 0)
		return -1;
	close(fd);
	if (expand_cmd(tmpl, wav_path, tmp_out, cmd, sizeof(cmd)) != 0) {
		unlink(tmp_out);
		return -1;
	}
	if (run_shell(cmd) != 0) {
		unlink(tmp_out);
		die("SPARK_STT_CMD failed", EXIT_IO);
	}
	txt = read_all(tmp_out, &tn);
	unlink(tmp_out);
	if (!txt)
		die("STT_CMD produced no out", EXIT_IO);
	while (tn && (txt[tn - 1] == '\n' || txt[tn - 1] == '\r'))
		txt[--tn] = 0;
	if (tn >= out_cap)
		tn = out_cap - 1;
	memcpy(out, txt, tn);
	out[tn] = 0;
	free(txt);
	return 0;
}

static int stt_via_http(const char *wav_path, char *out, size_t out_cap)
{
	const char *url = getenv("SPARK_STT_URL");
	const char *key;
	unsigned char *wav;
	size_t wn, rn;
	char *resp;
	char *body;
	char text[MAX_TEXT];

	if (!net_stt_allowed())
		die("STT network off (set SPARK_STT_NET=1 or "
		    "SPARK_SPEECH_NET=1)",
		    EXIT_GATED);
	if (!url || !*url)
		die("SPARK_STT_URL unset", EXIT_GATED);
	key = bearer_key("SPARK_STT_KEY");
	wav = (unsigned char *)read_all(wav_path, &wn);
	if (!wav || !is_riff_wav(wav, wn)) {
		free(wav);
		die("listen input is not a RIFF/WAVE file", EXIT_IO);
	}
	resp = malloc(MAX_BODY);
	if (!resp) {
		free(wav);
		die("oom", EXIT_IO);
	}
	http_post_raw(url, key, "audio/wav", wav, wn, resp, MAX_BODY, &rn);
	free(wav);
	body = body_after_headers(resp);
	if (extract_json_text(body, text, sizeof(text)) != 0) {
		/* plain-text body */
		size_t i = 0;
		while (body[i] && i + 1 < sizeof(text)) {
			text[i] = body[i];
			i++;
		}
		text[i] = 0;
		while (i && (text[i - 1] == '\n' || text[i - 1] == '\r'))
			text[--i] = 0;
		if (i == 0) {
			free(resp);
			die("STT response empty", EXIT_IO);
		}
	}
	{
		size_t tn = strlen(text);
		if (tn >= out_cap)
			tn = out_cap - 1;
		memcpy(out, text, tn);
		out[tn] = 0;
	}
	free(resp);
	return 0;
}

/* Local openai-whisper (no vendor net). Empty transcript = fail. */
static int whisper_available(void)
{
	static int cached = -1;
	const char *off = getenv("SPARK_STT_WHISPER");
	int st;
	pid_t pid;

	if (off && (!strcmp(off, "0") || !strcasecmp(off, "off") ||
		    !strcasecmp(off, "false") || !strcasecmp(off, "no")))
		return 0;
	if (cached >= 0)
		return cached;
	pid = fork();
	if (pid < 0) {
		cached = 0;
		return 0;
	}
	if (pid == 0) {
		int fd = open("/dev/null", O_RDWR);

		if (fd >= 0) {
			dup2(fd, 1);
			dup2(fd, 2);
			if (fd > 2)
				close(fd);
		}
		execlp("python3", "python3", "-c", "import whisper",
		       (char *)NULL);
		_exit(127);
	}
	if (waitpid(pid, &st, 0) < 0) {
		cached = 0;
		return 0;
	}
	cached = (WIFEXITED(st) && WEXITSTATUS(st) == 0) ? 1 : 0;
	return cached;
}

static int stt_via_whisper(const char *wav_path, char *out, size_t out_cap)
{
	const char *model = getenv("SPARK_WHISPER_MODEL");
	char tmp_out[] = "/tmp/spark-whisper-XXXXXX";
	char py[512];
	char *txt;
	size_t tn;
	int fd;
	int st;
	pid_t pid;

	if (!whisper_available())
		return -1;
	if (!model || !*model)
		model = "tiny.en";
	fd = mkstemp(tmp_out);
	if (fd < 0)
		return -1;
	close(fd);
	if (setenv("SPARK_WHISPER_IN", wav_path, 1) != 0 ||
	    setenv("SPARK_WHISPER_OUT", tmp_out, 1) != 0 ||
	    setenv("SPARK_WHISPER_MODEL", model, 1) != 0) {
		unlink(tmp_out);
		return -1;
	}
	snprintf(py, sizeof(py),
		 "import os,sys,whisper\n"
		 "m=whisper.load_model(os.environ['SPARK_WHISPER_MODEL'])\n"
		 "r=m.transcribe(os.environ['SPARK_WHISPER_IN'],fp16=False)\n"
		 "t=(r.get('text') or '').strip()\n"
		 "open(os.environ['SPARK_WHISPER_OUT'],'w',"
		 "encoding='utf-8').write(t)\n"
		 "sys.exit(0 if t else 2)\n");
	pid = fork();
	if (pid < 0) {
		unlink(tmp_out);
		return -1;
	}
	if (pid == 0) {
		execlp("python3", "python3", "-c", py, (char *)NULL);
		_exit(127);
	}
	if (waitpid(pid, &st, 0) < 0) {
		unlink(tmp_out);
		return -1;
	}
	if (!WIFEXITED(st) || WEXITSTATUS(st) != 0) {
		unlink(tmp_out);
		return -1;
	}
	txt = read_all(tmp_out, &tn);
	unlink(tmp_out);
	if (!txt || tn == 0) {
		free(txt);
		return -1;
	}
	while (tn && (txt[tn - 1] == '\n' || txt[tn - 1] == '\r'))
		txt[--tn] = 0;
	if (tn == 0) {
		free(txt);
		return -1;
	}
	if (tn >= out_cap)
		tn = out_cap - 1;
	memcpy(out, txt, tn);
	out[tn] = 0;
	free(txt);
	return 0;
}

static int do_listen(const char *in_path, int use_mic, int seconds,
		     const char *out_path)
{
	char wav_tmp[] = "/tmp/spark-listen.XXXXXX.wav";
	const char *wav = in_path;
	char transcript[MAX_TEXT];
	unsigned char *raw;
	size_t rn;
	int fd;

	memset(transcript, 0, sizeof(transcript));

	if (use_mic) {
		fd = mkstemps(wav_tmp, 4);
		if (fd < 0)
			die("mkstemps mic wav", EXIT_IO);
		close(fd);
		capture_mic(wav_tmp, seconds);
		wav = wav_tmp;
	} else if (!wav || !*wav)
		die("listen needs --in WAV or --mic", EXIT_USAGE);

	raw = (unsigned char *)read_all(wav, &rn);
	if (!raw || !is_riff_wav(raw, rn)) {
		free(raw);
		die("listen: not a valid WAV (open failed or bad RIFF)",
		    EXIT_IO);
	}
	free(raw);

	/* Prefer engines in order; URL without net gate = fail closed */
	if (getenv("SPARK_STT_URL") && *getenv("SPARK_STT_URL")) {
		if (!net_stt_allowed())
			die("SPARK_STT_URL set but net gated off "
			    "(SPARK_STT_NET=1 / SPARK_SPEECH_NET=1)",
			    EXIT_GATED);
		stt_via_http(wav, transcript, sizeof(transcript));
	} else if (getenv("SPARK_STT_CMD") && *getenv("SPARK_STT_CMD")) {
		stt_via_cmd(wav, transcript, sizeof(transcript));
	} else if (try_sidecar(wav, transcript, sizeof(transcript)) == 0) {
		/* ok — local sidecar transcript next to wav */
	} else if (stt_via_whisper(wav, transcript,
				   sizeof(transcript)) == 0) {
		/* ok — local openai-whisper (offline model) */
	} else {
		die("no STT engine: set SPARK_STT_CMD, sidecar "
		    ".intent.txt, local whisper (pip openai-whisper), "
		    "or SPARK_STT_NET=1 + SPARK_STT_URL",
		    EXIT_GATED);
	}

	fputs(transcript, stdout);
	if (transcript[0] &&
	    transcript[strlen(transcript) - 1] != '\n')
		fputc('\n', stdout);
	if (out_path) {
		size_t n = strlen(transcript);
		if (write_all(out_path, transcript, n) != 0)
			die("write --out transcript", EXIT_IO);
	}
	if (use_mic)
		unlink(wav_tmp);
	return 0;
}

/* ---------- TTS paths ---------- */

static int tts_via_cmd(const char *text, const char *out_path)
{
	const char *tmpl = getenv("SPARK_TTS_CMD");
	char cmd[4096];
	char tmp_in[] = "/tmp/spark-tts-in.XXXXXX";
	int fd;

	if (!tmpl || !*tmpl)
		return -1;
	fd = mkstemp(tmp_in);
	if (fd < 0)
		return -1;
	if (write(fd, text, strlen(text)) < 0) {
		close(fd);
		return -1;
	}
	close(fd);
	if (expand_cmd(tmpl, tmp_in, out_path, cmd, sizeof(cmd)) != 0) {
		unlink(tmp_in);
		return -1;
	}
	if (run_shell(cmd) != 0) {
		unlink(tmp_in);
		die("SPARK_TTS_CMD failed", EXIT_IO);
	}
	unlink(tmp_in);
	return 0;
}

static int tts_via_http(const char *text, const char *out_path)
{
	const char *url = getenv("SPARK_TTS_URL");
	const char *key;
	char *body;
	char *resp;
	char *audio;
	size_t rn;
	size_t need;

	if (!net_tts_allowed())
		die("TTS network off (set SPARK_TTS_NET=1 or "
		    "SPARK_SPEECH_NET=1)",
		    EXIT_GATED);
	if (!url || !*url)
		die("SPARK_TTS_URL unset", EXIT_GATED);
	key = bearer_key("SPARK_TTS_KEY");
	need = strlen(text) * 2 + 64;
	body = malloc(need);
	resp = malloc(MAX_BODY);
	if (!body || !resp)
		die("oom", EXIT_IO);
	{
		/* minimal JSON; escape quotes in text */
		char *esc = malloc(strlen(text) * 2 + 8);
		size_t w = 0, i;
		if (!esc)
			die("oom", EXIT_IO);
		for (i = 0; text[i]; i++) {
			if (text[i] == '"' || text[i] == '\\')
				esc[w++] = '\\';
			esc[w++] = text[i];
		}
		esc[w] = 0;
		snprintf(body, need, "{\"text\":\"%s\"}", esc);
		free(esc);
	}
	http_post_raw(url, key, "application/json", body, strlen(body),
		      resp, MAX_BODY, &rn);
	free(body);
	audio = body_after_headers(resp);
	{
		size_t an = rn - (size_t)(audio - resp);
		if (an < 12 || !is_riff_wav((unsigned char *)audio, an)) {
			free(resp);
			die("TTS response was not audio/wav", EXIT_IO);
		}
		if (write_all(out_path, audio, an) != 0) {
			free(resp);
			die("write TTS wav", EXIT_IO);
		}
	}
	free(resp);
	return 0;
}

static int do_speak(const char *text, const char *text_file,
		    const char *out_path, int do_play)
{
	char *owned = NULL;
	const char *msg = text;
	unsigned char *chk;
	size_t cn;

	if (text_file) {
		owned = read_all(text_file, NULL);
		if (!owned)
			die("cannot read --text-file", EXIT_IO);
		msg = owned;
	}
	if (!msg)
		msg = "";
	if (!out_path || !*out_path)
		die("speak needs --out WAV", EXIT_USAGE);

	/* URL without net gate = fail closed (do not silent-fallback) */
	if (getenv("SPARK_TTS_URL") && *getenv("SPARK_TTS_URL")) {
		if (!net_tts_allowed())
			die("SPARK_TTS_URL set but net gated off "
			    "(SPARK_TTS_NET=1 / SPARK_SPEECH_NET=1)",
			    EXIT_GATED);
		tts_via_http(msg, out_path);
	} else if (getenv("SPARK_TTS_CMD") && *getenv("SPARK_TTS_CMD")) {
		tts_via_cmd(msg, out_path);
	} else {
		synth_wav(msg, out_path);
	}

	chk = (unsigned char *)read_all(out_path, &cn);
	if (!chk || !is_riff_wav(chk, cn) || cn < 44) {
		free(chk);
		die("speak produced invalid WAV", EXIT_IO);
	}
	free(chk);

	printf("%s\n", out_path);
	if (do_play || env_truthy("SPARK_TTS_PLAY"))
		play_wav(out_path);
	free(owned);
	return 0;
}

static void usage(void)
{
	fprintf(stderr,
		"usage:\n"
		"  spark-stt-tts status\n"
		"  spark-stt-tts listen (--in WAV | --mic) "
		"[--seconds N] [--out FILE]\n"
		"  spark-stt-tts speak (--text STR | --text-file F) "
		"--out WAV [--play]\n"
		"\n"
		"Network TTS/STT vendors are OFF unless "
		"SPARK_STT_NET / SPARK_TTS_NET / SPARK_SPEECH_NET=1.\n");
	exit(EXIT_USAGE);
}

static int do_status(void)
{
	printf("{\"op\":\"spark-stt-tts.status\","
	       "\"local_synth\":true,\"mic\":\"arecord\","
	       "\"play\":\"aplay\","
	       "\"stt_whisper\":%s,"
	       "\"stt_net\":%s,\"tts_net\":%s,"
	       "\"stt_url\":%s,\"tts_url\":%s,"
	       "\"stt_cmd\":%s,\"tts_cmd\":%s}\n",
	       whisper_available() ? "true" : "false",
	       net_stt_allowed() ? "true" : "false",
	       net_tts_allowed() ? "true" : "false",
	       (getenv("SPARK_STT_URL") && *getenv("SPARK_STT_URL"))
		   ? "true"
		   : "false",
	       (getenv("SPARK_TTS_URL") && *getenv("SPARK_TTS_URL"))
		   ? "true"
		   : "false",
	       (getenv("SPARK_STT_CMD") && *getenv("SPARK_STT_CMD"))
		   ? "true"
		   : "false",
	       (getenv("SPARK_TTS_CMD") && *getenv("SPARK_TTS_CMD"))
		   ? "true"
		   : "false");
	return 0;
}

int main(int argc, char **argv)
{
	const char *mode;
	const char *in_path = NULL;
	const char *out_path = NULL;
	const char *text = NULL;
	const char *text_file = NULL;
	int use_mic = 0;
	int seconds = 3;
	int do_play = 0;
	int i;
	const char *env_sec;

	if (argc < 2)
		usage();
	mode = argv[1];
	env_sec = getenv("SPARK_MIC_SECONDS");
	if (env_sec && *env_sec)
		seconds = atoi(env_sec);

	for (i = 2; i < argc; i++) {
		if (!strcmp(argv[i], "--in") && i + 1 < argc)
			in_path = argv[++i];
		else if (!strcmp(argv[i], "--out") && i + 1 < argc)
			out_path = argv[++i];
		else if (!strcmp(argv[i], "--text") && i + 1 < argc)
			text = argv[++i];
		else if (!strcmp(argv[i], "--text-file") && i + 1 < argc)
			text_file = argv[++i];
		else if (!strcmp(argv[i], "--mic"))
			use_mic = 1;
		else if (!strcmp(argv[i], "--play"))
			do_play = 1;
		else if (!strcmp(argv[i], "--seconds") && i + 1 < argc)
			seconds = atoi(argv[++i]);
		else
			usage();
	}

	if (!strcmp(mode, "status"))
		return do_status();
	if (!strcmp(mode, "listen"))
		return do_listen(in_path, use_mic, seconds, out_path);
	if (!strcmp(mode, "speak"))
		return do_speak(text, text_file, out_path, do_play);
	usage();
	return EXIT_USAGE;
}
