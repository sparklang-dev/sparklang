/*
 * spark-enc-gateway — AES-256-GCM encrypt gateway for Spark.
 *
 * Architecture (encrypt-to-model):
 *   Agent seals outbound payloads → envelope {alg,nonce,ciphertext,tag,aad}
 *   This process holds keys, opens envelopes, then calls Bifrost/model
 *   with plaintext ONLY inside this trusted boundary. Replies may be
 *   re-sealed before return to the agent.
 *
 * Crypto backends (selectable; default OpenSSL):
 *   openssl — OpenSSL EVP_aes_256_gcm (default, always preferred when
 *             AF_ALG is blacklisted / missing)
 *   af_alg  — Linux AF_ALG aead "gcm(aes)" when algif_aead is loadable;
 *             fail-loud if selected while unusable
 *
 * this host: algif_aead blocked by CVE-2026-31431
 * (/etc/modprobe.d/disable-algif_aead.conf). Probe reports blacklist
 * honestly. Never edits sysctl / modprobe / security policy.
 *
 * Never logs key bytes. No fake base64-of-plaintext.
 */

#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/if_alg.h>
#include <openssl/evp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/random.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef SOL_ALG
#define SOL_ALG 279
#endif

#define KEY_LEN 32
#define NONCE_LEN 12
#define TAG_LEN 16
#define MAX_PT (1 << 20)
#define MAX_ENV (1 << 21)
#define BACKEND_FILE "out/encrypt/backend"

/* Selected crypto backend name for envelopes / JSON ("openssl-evp" / "af_alg"). */
static const char *g_backend = "none";
/* Preference: "openssl" (default) or "af_alg". */
static const char *g_prefer = "openssl";

static void die(const char *msg)
{
	fprintf(stderr, "spark-enc-gateway: %s\n", msg);
	exit(1);
}

static void die_errno(const char *msg)
{
	fprintf(stderr, "spark-enc-gateway: %s: %s\n", msg,
		strerror(errno));
	exit(1);
}

static int hex_nibble(char c)
{
	if (c >= '0' && c <= '9')
		return c - '0';
	if (c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	if (c >= 'A' && c <= 'F')
		return c - 'A' + 10;
	return -1;
}

static size_t hex_decode(const char *hex, uint8_t *out, size_t out_cap)
{
	size_t n = 0;
	size_t i = 0;
	size_t len = strlen(hex);

	while (i + 1 < len && n < out_cap) {
		int hi = hex_nibble(hex[i]);
		int lo = hex_nibble(hex[i + 1]);
		if (hi < 0 || lo < 0)
			break;
		out[n++] = (uint8_t)((hi << 4) | lo);
		i += 2;
	}
	return n;
}

static void hex_encode(const uint8_t *in, size_t n, char *out)
{
	static const char *H = "0123456789abcdef";
	size_t i;

	for (i = 0; i < n; i++) {
		out[i * 2] = H[in[i] >> 4];
		out[i * 2 + 1] = H[in[i] & 0xf];
	}
	out[n * 2] = 0;
}

static uint8_t *read_file(const char *path, size_t *out_len)
{
	FILE *f = fopen(path, "rb");
	long n;
	uint8_t *buf;

	if (!f)
		die_errno(path);
	if (fseek(f, 0, SEEK_END) != 0)
		die("fseek");
	n = ftell(f);
	if (n < 0 || (size_t)n > MAX_ENV)
		die("file too large");
	rewind(f);
	buf = malloc((size_t)n + 1);
	if (!buf)
		die("oom");
	if (fread(buf, 1, (size_t)n, f) != (size_t)n)
		die("fread");
	buf[n] = 0;
	fclose(f);
	if (out_len)
		*out_len = (size_t)n;
	return buf;
}

static void write_file(const char *path, const void *buf, size_t n)
{
	FILE *f = fopen(path, "wb");

	if (!f)
		die_errno(path);
	if (fwrite(buf, 1, n, f) != n)
		die("fwrite");
	fclose(f);
}

/* Keys / sealed plaintext temps: owner-only (never world/group). */
static void write_secret_file(const char *path, const void *buf, size_t n)
{
	int fd;
	mode_t old = umask(0077);

	fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
	umask(old);
	if (fd < 0)
		die_errno(path);
	if (fchmod(fd, 0600) != 0) {
		close(fd);
		die_errno("fchmod");
	}
	if (write(fd, buf, n) != (ssize_t)n) {
		close(fd);
		die("write secret");
	}
	if (close(fd) != 0)
		die_errno("close secret");
}

static void ensure_key_not_world_readable(const char *path)
{
	struct stat st;

	if (stat(path, &st) != 0)
		die_errno(path);
	if (st.st_mode & 0077) {
		if (chmod(path, 0600) != 0)
			die_errno("chmod key 0600");
	}
}

static void load_key(const char *path, uint8_t key[KEY_LEN])
{
	size_t n = 0;
	uint8_t *raw;

	ensure_key_not_world_readable(path);
	raw = read_file(path, &n);

	if (n == KEY_LEN) {
		memcpy(key, raw, KEY_LEN);
	} else if (n == KEY_LEN * 2) {
		if (hex_decode((char *)raw, key, KEY_LEN) != KEY_LEN)
			die("bad key hex");
	} else {
		die("key must be 32 raw bytes or 64 hex chars");
	}
	free(raw);
}

/* ---- OpenSSL EVP AES-256-GCM ---- */

static int evp_seal(const uint8_t key[KEY_LEN], const uint8_t *nonce,
		    const uint8_t *aad, size_t aad_len, const uint8_t *pt,
		    size_t pt_len, uint8_t *ct, uint8_t tag[TAG_LEN])
{
	EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
	int len = 0, outl = 0;

	if (!ctx)
		return -1;
	if (EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL) !=
	    1)
		goto fail;
	if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, NONCE_LEN,
				NULL) != 1)
		goto fail;
	if (EVP_EncryptInit_ex(ctx, NULL, NULL, key, nonce) != 1)
		goto fail;
	if (aad_len &&
	    EVP_EncryptUpdate(ctx, NULL, &len, aad, (int)aad_len) != 1)
		goto fail;
	if (EVP_EncryptUpdate(ctx, ct, &len, pt, (int)pt_len) != 1)
		goto fail;
	outl = len;
	if (EVP_EncryptFinal_ex(ctx, ct + outl, &len) != 1)
		goto fail;
	outl += len;
	if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, TAG_LEN, tag) !=
	    1)
		goto fail;
	EVP_CIPHER_CTX_free(ctx);
	(void)outl;
	return 0;
fail:
	EVP_CIPHER_CTX_free(ctx);
	return -1;
}

static int evp_open(const uint8_t key[KEY_LEN], const uint8_t *nonce,
		    const uint8_t *aad, size_t aad_len, const uint8_t *ct,
		    size_t ct_len, const uint8_t tag[TAG_LEN], uint8_t *pt)
{
	EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
	int len = 0, outl = 0;

	if (!ctx)
		return -1;
	if (EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL) !=
	    1)
		goto fail;
	if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, NONCE_LEN,
				NULL) != 1)
		goto fail;
	if (EVP_DecryptInit_ex(ctx, NULL, NULL, key, nonce) != 1)
		goto fail;
	if (aad_len &&
	    EVP_DecryptUpdate(ctx, NULL, &len, aad, (int)aad_len) != 1)
		goto fail;
	if (EVP_DecryptUpdate(ctx, pt, &len, ct, (int)ct_len) != 1)
		goto fail;
	outl = len;
	if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, TAG_LEN,
				(void *)tag) != 1)
		goto fail;
	if (EVP_DecryptFinal_ex(ctx, pt + outl, &len) != 1)
		goto fail;
	EVP_CIPHER_CTX_free(ctx);
	return 0;
fail:
	EVP_CIPHER_CTX_free(ctx);
	return -1;
}

/* ---- AF_ALG probe (honest blacklist) + optional AEAD path ---- */

enum afalg_status {
	AFALG_OK = 0,
	AFALG_BLACKLISTED = 1,
	AFALG_UNAVAILABLE = 2,
};

struct afalg_info {
	enum afalg_status status;
	int bind_errno;
	int socket_errno;
	char blacklist_path[256];
	const char *reason;
};

static int file_mentions_algif_block(const char *path)
{
	FILE *f = fopen(path, "r");
	char line[512];
	int hit = 0;

	if (!f)
		return 0;
	while (fgets(line, sizeof(line), f)) {
		if (line[0] == '#')
			continue;
		if (!strstr(line, "algif_aead"))
			continue;
		if (strstr(line, "blacklist") ||
		    (strstr(line, "install") && strstr(line, "/bin/false"))) {
			hit = 1;
			break;
		}
	}
	fclose(f);
	return hit;
}

/*
 * Detect host policy that blocks algif_aead (CVE-2026-31431).
 * Read-only — never edits modprobe.d / sysctl / security.
 */
static int find_algif_blacklist(char *out_path, size_t out_cap)
{
	static const char *known =
		"/etc/modprobe.d/disable-algif_aead.conf";
	DIR *d;
	struct dirent *de;

	if (out_path && out_cap)
		out_path[0] = 0;
	if (file_mentions_algif_block(known)) {
		if (out_path && out_cap)
			snprintf(out_path, out_cap, "%s", known);
		return 1;
	}
	d = opendir("/etc/modprobe.d");
	if (!d)
		return 0;
	while ((de = readdir(d)) != NULL) {
		size_t n = strlen(de->d_name);
		char path[256];

		if (n < 6 || strcmp(de->d_name + n - 5, ".conf") != 0)
			continue;
		if (snprintf(path, sizeof(path), "/etc/modprobe.d/%s",
			     de->d_name) >= (int)sizeof(path))
			continue;
		if (file_mentions_algif_block(path)) {
			if (out_path && out_cap)
				snprintf(out_path, out_cap, "%s", path);
			closedir(d);
			return 1;
		}
	}
	closedir(d);
	return 0;
}

static void afalg_probe(struct afalg_info *info)
{
	int tfm;
	struct sockaddr_alg sa;
	int bl;

	memset(info, 0, sizeof(*info));
	info->status = AFALG_UNAVAILABLE;
	info->reason = "AF_ALG aead gcm(aes) unavailable";
	bl = find_algif_blacklist(info->blacklist_path,
				  sizeof(info->blacklist_path));

	tfm = socket(AF_ALG, SOCK_SEQPACKET, 0);
	if (tfm < 0) {
		info->socket_errno = errno;
		if (bl) {
			info->status = AFALG_BLACKLISTED;
			info->reason =
				"AF_ALG socket failed; algif_aead "
				"blacklisted (CVE-2026-31431)";
		} else {
			info->reason = "AF_ALG socket failed";
		}
		return;
	}
	memset(&sa, 0, sizeof(sa));
	sa.salg_family = AF_ALG;
	strncpy((char *)sa.salg_type, "aead", sizeof(sa.salg_type));
	strncpy((char *)sa.salg_name, "gcm(aes)", sizeof(sa.salg_name));
	if (bind(tfm, (struct sockaddr *)&sa, sizeof(sa)) < 0) {
		info->bind_errno = errno;
		close(tfm);
		if (bl || info->bind_errno == ENOENT) {
			info->status = AFALG_BLACKLISTED;
			if (bl)
				info->reason =
					"algif_aead blacklisted "
					"(CVE-2026-31431); OpenSSL EVP "
					"is the live backend";
			else
				info->reason =
					"aead gcm(aes) bind ENOENT "
					"(algif_aead missing or blocked)";
		} else {
			info->status = AFALG_UNAVAILABLE;
			info->reason = "aead gcm(aes) bind failed";
		}
		if (bl && !info->blacklist_path[0])
			find_algif_blacklist(info->blacklist_path,
					    sizeof(info->blacklist_path));
		return;
	}
	close(tfm);
	if (bl) {
		/* Bind worked but policy file still present — report both. */
		info->status = AFALG_OK;
		info->reason =
			"AF_ALG aead usable; blacklist conf still present "
			"(policy drift — do not auto-edit)";
		return;
	}
	info->status = AFALG_OK;
	info->reason = "AF_ALG aead gcm(aes) bind ok";
}

static int afalg_usable(void)
{
	struct afalg_info info;

	afalg_probe(&info);
	return info.status == AFALG_OK;
}

static int afalg_aead(int encrypt, const uint8_t key[KEY_LEN],
		      const uint8_t *nonce, const uint8_t *aad,
		      size_t aad_len, const uint8_t *in, size_t in_len,
		      uint8_t *out, uint8_t tag[TAG_LEN])
{
	int tfm = -1, op = -1;
	struct sockaddr_alg sa;
	struct msghdr msg;
	struct cmsghdr *cmsg;
	struct af_alg_iv *ivm;
	struct iovec iov;
	char cbuf[CMSG_SPACE(4) + CMSG_SPACE(4 + NONCE_LEN) +
		  CMSG_SPACE(4)];
	uint8_t *buf = NULL;
	uint8_t *rbuf = NULL;
	size_t buflen;
	ssize_t n;
	__u32 assoclen;
	int op_val;
	int rc = -1;

	tfm = socket(AF_ALG, SOCK_SEQPACKET, 0);
	if (tfm < 0)
		return -1;
	memset(&sa, 0, sizeof(sa));
	sa.salg_family = AF_ALG;
	strncpy((char *)sa.salg_type, "aead", sizeof(sa.salg_type));
	strncpy((char *)sa.salg_name, "gcm(aes)", sizeof(sa.salg_name));
	if (bind(tfm, (struct sockaddr *)&sa, sizeof(sa)) < 0)
		goto out;
	if (setsockopt(tfm, SOL_ALG, ALG_SET_KEY, key, KEY_LEN) < 0)
		goto out;
	if (setsockopt(tfm, SOL_ALG, ALG_SET_AEAD_AUTHSIZE, NULL,
		       TAG_LEN) < 0)
		goto out;
	op = accept(tfm, NULL, 0);
	if (op < 0)
		goto out;

	memset(cbuf, 0, sizeof(cbuf));
	memset(&msg, 0, sizeof(msg));
	msg.msg_control = cbuf;
	msg.msg_controllen = sizeof(cbuf);

	cmsg = CMSG_FIRSTHDR(&msg);
	cmsg->cmsg_level = SOL_ALG;
	cmsg->cmsg_type = ALG_SET_OP;
	cmsg->cmsg_len = CMSG_LEN(sizeof(op_val));
	op_val = encrypt ? ALG_OP_ENCRYPT : ALG_OP_DECRYPT;
	memcpy(CMSG_DATA(cmsg), &op_val, sizeof(op_val));

	cmsg = CMSG_NXTHDR(&msg, cmsg);
	cmsg->cmsg_level = SOL_ALG;
	cmsg->cmsg_type = ALG_SET_IV;
	cmsg->cmsg_len = CMSG_LEN(4 + NONCE_LEN);
	ivm = (struct af_alg_iv *)CMSG_DATA(cmsg);
	ivm->ivlen = NONCE_LEN;
	memcpy(ivm->iv, nonce, NONCE_LEN);

	cmsg = CMSG_NXTHDR(&msg, cmsg);
	cmsg->cmsg_level = SOL_ALG;
	cmsg->cmsg_type = ALG_SET_AEAD_ASSOCLEN;
	cmsg->cmsg_len = CMSG_LEN(sizeof(assoclen));
	assoclen = (__u32)aad_len;
	memcpy(CMSG_DATA(cmsg), &assoclen, sizeof(assoclen));

	if (encrypt) {
		buflen = aad_len + in_len;
		buf = malloc(buflen ? buflen : 1);
		rbuf = malloc(in_len + TAG_LEN);
		if (!buf || !rbuf)
			goto out;
		if (aad_len)
			memcpy(buf, aad, aad_len);
		if (in_len)
			memcpy(buf + aad_len, in, in_len);
		iov.iov_base = buf;
		iov.iov_len = buflen;
		msg.msg_iov = &iov;
		msg.msg_iovlen = 1;
		if (sendmsg(op, &msg, 0) < 0)
			goto out;
		n = read(op, rbuf, in_len + TAG_LEN);
		if (n != (ssize_t)(in_len + TAG_LEN))
			goto out;
		if (in_len)
			memcpy(out, rbuf, in_len);
		memcpy(tag, rbuf + in_len, TAG_LEN);
	} else {
		buflen = aad_len + in_len + TAG_LEN;
		buf = malloc(buflen);
		rbuf = malloc(in_len ? in_len : 1);
		if (!buf || !rbuf)
			goto out;
		if (aad_len)
			memcpy(buf, aad, aad_len);
		if (in_len)
			memcpy(buf + aad_len, in, in_len);
		memcpy(buf + aad_len + in_len, tag, TAG_LEN);
		iov.iov_base = buf;
		iov.iov_len = buflen;
		msg.msg_iov = &iov;
		msg.msg_iovlen = 1;
		if (sendmsg(op, &msg, 0) < 0)
			goto out;
		n = read(op, rbuf, in_len);
		if (n != (ssize_t)in_len)
			goto out;
		if (in_len)
			memcpy(out, rbuf, in_len);
	}
	rc = 0;
out:
	free(buf);
	free(rbuf);
	if (op >= 0)
		close(op);
	if (tfm >= 0)
		close(tfm);
	return rc;
}

static void require_afalg_or_die(void)
{
	struct afalg_info info;

	afalg_probe(&info);
	if (info.status == AFALG_OK)
		return;
	fprintf(stderr,
		"spark-enc-gateway: AF_ALG backend unusable: %s",
		info.reason);
	if (info.blacklist_path[0])
		fprintf(stderr, " [%s]", info.blacklist_path);
	if (info.bind_errno)
		fprintf(stderr, " (bind errno=%d %s)", info.bind_errno,
			strerror(info.bind_errno));
	fprintf(stderr,
		"\nfail-loud: refusing silent OpenSSL fallback when "
		"backend=af_alg. Stay on openssl, un-blacklist "
		"algif_aead, or wait for a kernel fix — do not ask "
		"agents to edit modprobe/sysctl.\n");
	exit(1);
}

static int gcm_seal(const uint8_t key[KEY_LEN], const uint8_t *nonce,
		    const uint8_t *aad, size_t aad_len, const uint8_t *pt,
		    size_t pt_len, uint8_t *ct, uint8_t tag[TAG_LEN])
{
	if (strcmp(g_prefer, "af_alg") == 0) {
		require_afalg_or_die();
		if (afalg_aead(1, key, nonce, aad, aad_len, pt, pt_len, ct,
			       tag) == 0) {
			g_backend = "af_alg";
			return 0;
		}
		die("AF_ALG AEAD seal failed");
	}
	if (evp_seal(key, nonce, aad, aad_len, pt, pt_len, ct, tag) == 0) {
		g_backend = "openssl-evp";
		return 0;
	}
	return -1;
}

static int gcm_open(const uint8_t key[KEY_LEN], const uint8_t *nonce,
		    const uint8_t *aad, size_t aad_len, const uint8_t *ct,
		    size_t ct_len, const uint8_t tag[TAG_LEN], uint8_t *pt)
{
	if (strcmp(g_prefer, "af_alg") == 0) {
		require_afalg_or_die();
		if (afalg_aead(0, key, nonce, aad, aad_len, ct, ct_len, pt,
			       (uint8_t *)tag) == 0) {
			g_backend = "af_alg";
			return 0;
		}
		die("AF_ALG AEAD open failed");
	}
	if (evp_open(key, nonce, aad, aad_len, ct, ct_len, tag, pt) == 0) {
		g_backend = "openssl-evp";
		return 0;
	}
	return -1;
}

static void json_escape_reason(const char *in, char *out, size_t cap)
{
	size_t o = 0;
	size_t i;

	for (i = 0; in[i] && o + 2 < cap; i++) {
		if (in[i] == '"' || in[i] == '\\') {
			out[o++] = '\\';
			out[o++] = in[i];
		} else if (in[i] == '\n') {
			if (o + 2 >= cap)
				break;
			out[o++] = '\\';
			out[o++] = 'n';
		} else {
			out[o++] = in[i];
		}
	}
	out[o] = 0;
}

static const char *status_str(enum afalg_status s)
{
	switch (s) {
	case AFALG_OK:
		return "ok";
	case AFALG_BLACKLISTED:
		return "blacklisted";
	default:
		return "unavailable";
	}
}

static void ensure_encrypt_dir(void)
{
	mkdir("out", 0755);
	mkdir("out/encrypt", 0700);
	chmod("out/encrypt", 0700);
}

static void load_prefer_from_file(void)
{
	FILE *f;
	char buf[64];
	size_t n;

	f = fopen(BACKEND_FILE, "r");
	if (!f)
		return;
	n = fread(buf, 1, sizeof(buf) - 1, f);
	fclose(f);
	if (n == 0)
		return;
	buf[n] = 0;
	while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r' ||
			 buf[n - 1] == ' '))
		buf[--n] = 0;
	if (!strcmp(buf, "openssl") || !strcmp(buf, "af_alg"))
		g_prefer = !strcmp(buf, "af_alg") ? "af_alg" : "openssl";
}

static void apply_backend_flag(const char *name)
{
	if (!name)
		return;
	if (!strcmp(name, "openssl") || !strcmp(name, "openssl-evp"))
		g_prefer = "openssl";
	else if (!strcmp(name, "af_alg") || !strcmp(name, "afalg"))
		g_prefer = "af_alg";
	else
		die("backend must be openssl or af_alg");
}

static void cmd_probe(int require_afalg)
{
	struct afalg_info info;
	char reason_esc[512];
	const char *envb = getenv("SPARK_ENC_BACKEND");
	int openssl_ok = 1;

	afalg_probe(&info);
	json_escape_reason(info.reason, reason_esc, sizeof(reason_esc));
	printf("{\"op\":\"probe\",\"openssl_evp\":%s,"
	       "\"af_alg_aead\":%s,\"af_alg_status\":\"%s\","
	       "\"af_alg_reason\":\"%s\",\"blacklist_conf\":\"%s\","
	       "\"bind_errno\":%d,\"socket_errno\":%d,"
	       "\"default_backend\":\"openssl\","
	       "\"selected_backend\":\"%s\","
	       "\"env_SPARK_ENC_BACKEND\":\"%s\","
	       "\"cve\":\"CVE-2026-31431\","
	       "\"never\":\"edit modprobe/sysctl from agents\"}\n",
	       openssl_ok ? "true" : "false",
	       info.status == AFALG_OK ? "true" : "false",
	       status_str(info.status), reason_esc,
	       info.blacklist_path[0] ? info.blacklist_path : "",
	       info.bind_errno, info.socket_errno, g_prefer,
	       envb ? envb : "");
	if (require_afalg && info.status != AFALG_OK)
		require_afalg_or_die();
}

static void cmd_backend_set(const char *name)
{
	struct afalg_info info;

	apply_backend_flag(name);
	if (!strcmp(g_prefer, "af_alg")) {
		afalg_probe(&info);
		if (info.status != AFALG_OK)
			require_afalg_or_die();
	}
	ensure_encrypt_dir();
	write_file(BACKEND_FILE, g_prefer, strlen(g_prefer));
	printf("{\"op\":\"backend\",\"backend\":\"%s\",\"ok\":true,"
	       "\"path\":\"%s\"}\n",
	       g_prefer, BACKEND_FILE);
}

/* Envelope JSON (hex fields — encoding of real ciphertext, not a stub) */

static char *json_get_hex(const char *json, const char *key, uint8_t *out,
			  size_t out_cap, size_t *out_len)
{
	char pat[64];
	const char *p;
	size_t i = 0;

	snprintf(pat, sizeof(pat), "\"%s\"", key);
	p = strstr(json, pat);
	if (!p)
		return NULL;
	p = strchr(p + strlen(pat), '"');
	if (!p)
		return NULL;
	p++;
	while (p[0] && p[1] && i < out_cap) {
		int hi = hex_nibble(p[0]);
		int lo = hex_nibble(p[1]);
		if (hi < 0 || lo < 0)
			break;
		out[i++] = (uint8_t)((hi << 4) | lo);
		p += 2;
	}
	*out_len = i;
	return (char *)p;
}

static void write_envelope(const char *path, const uint8_t *nonce,
			   const uint8_t *ct, size_t ct_len,
			   const uint8_t *tag, const uint8_t *aad,
			   size_t aad_len)
{
	char *buf;
	char *nhex, *chex, *thex, *ahex;
	size_t need;

	nhex = malloc(NONCE_LEN * 2 + 1);
	chex = malloc(ct_len * 2 + 1);
	thex = malloc(TAG_LEN * 2 + 1);
	ahex = malloc(aad_len * 2 + 1);
	if (!nhex || !chex || !thex || !ahex)
		die("oom");
	hex_encode(nonce, NONCE_LEN, nhex);
	hex_encode(ct, ct_len, chex);
	hex_encode(tag, TAG_LEN, thex);
	hex_encode(aad, aad_len, ahex);
	need = strlen(nhex) + strlen(chex) + strlen(thex) + strlen(ahex) +
	       256;
	buf = malloc(need);
	if (!buf)
		die("oom");
	snprintf(buf, need,
		 "{\"alg\":\"AES-256-GCM\",\"backend\":\"%s\","
		 "\"nonce_hex\":\"%s\",\"ciphertext_hex\":\"%s\","
		 "\"tag_hex\":\"%s\",\"aad_hex\":\"%s\"}\n",
		 g_backend, nhex, chex, thex, ahex);
	write_file(path, buf, strlen(buf));
	free(buf);
	free(nhex);
	free(chex);
	free(thex);
	free(ahex);
}

static size_t open_envelope(const char *path, const uint8_t key[KEY_LEN],
			    uint8_t *pt_out, size_t pt_cap)
{
	size_t raw_len = 0;
	char *json = (char *)read_file(path, &raw_len);
	uint8_t nonce[NONCE_LEN];
	uint8_t tag[TAG_LEN];
	uint8_t *ct;
	uint8_t *aad;
	size_t nlen = 0, tlen = 0, clen = 0, alen = 0;

	ct = malloc(MAX_PT);
	aad = malloc(4096);
	if (!ct || !aad)
		die("oom");
	if (!json_get_hex(json, "nonce_hex", nonce, NONCE_LEN, &nlen) ||
	    nlen != NONCE_LEN)
		die("envelope missing nonce");
	if (!json_get_hex(json, "tag_hex", tag, TAG_LEN, &tlen) ||
	    tlen != TAG_LEN)
		die("envelope missing tag");
	if (!json_get_hex(json, "ciphertext_hex", ct, MAX_PT, &clen))
		die("envelope missing ciphertext");
	json_get_hex(json, "aad_hex", aad, 4096, &alen);
	if (clen > pt_cap)
		die("plaintext too large");
	if (gcm_open(key, nonce, aad, alen, ct, clen, tag, pt_out) != 0)
		die("GCM open failed (bad key or tampered envelope)");
	free(json);
	free(ct);
	free(aad);
	return clen;
}

static void cmd_keygen(const char *out_path)
{
	uint8_t key[KEY_LEN];
	char hex[KEY_LEN * 2 + 1];

	if (getrandom(key, KEY_LEN, 0) != KEY_LEN)
		die_errno("getrandom");
	hex_encode(key, KEY_LEN, hex);
	write_secret_file(out_path, hex, strlen(hex));
	ensure_key_not_world_readable(out_path);
	printf("{\"op\":\"keygen\",\"path\":\"%s\",\"bytes\":%d,"
	       "\"encoding\":\"hex\",\"mode\":\"0600\"}\n",
	       out_path, KEY_LEN);
}

static void cmd_seal(const char *key_path, const char *text_path,
		     const char *text_inline, const char *out_path,
		     const char *aad_str)
{
	uint8_t key[KEY_LEN];
	uint8_t nonce[NONCE_LEN];
	uint8_t tag[TAG_LEN];
	uint8_t *pt;
	uint8_t *ct;
	size_t pt_len = 0;
	const uint8_t *aad = (const uint8_t *)(aad_str ? aad_str : "");
	size_t aad_len = aad_str ? strlen(aad_str) : 0;

	load_key(key_path, key);
	if (text_inline) {
		pt_len = strlen(text_inline);
		pt = (uint8_t *)strdup(text_inline);
	} else {
		pt = read_file(text_path, &pt_len);
	}
	ct = malloc(pt_len + 32);
	if (!pt || !ct)
		die("oom");
	if (getrandom(nonce, NONCE_LEN, 0) != NONCE_LEN)
		die_errno("getrandom nonce");
	if (gcm_seal(key, nonce, aad, aad_len, pt, pt_len, ct, tag) != 0)
		die("GCM seal failed");
	write_envelope(out_path, nonce, ct, pt_len, tag, aad, aad_len);
	printf("{\"op\":\"seal\",\"path\":\"%s\",\"pt_len\":%zu,"
	       "\"backend\":\"%s\"}\n",
	       out_path, pt_len, g_backend);
	free(pt);
	free(ct);
}

static void cmd_open(const char *key_path, const char *env_path,
		     const char *out_path)
{
	uint8_t key[KEY_LEN];
	uint8_t *pt = malloc(MAX_PT);
	size_t n;

	if (!pt)
		die("oom");
	load_key(key_path, key);
	n = open_envelope(env_path, key, pt, MAX_PT);
	write_file(out_path, pt, n);
	printf("{\"op\":\"open\",\"path\":\"%s\",\"pt_len\":%zu,"
	       "\"backend\":\"%s\"}\n",
	       out_path, n, g_backend);
	free(pt);
}

static int run_ask_http(const char *model, const char *prompt_path,
			const char *out_path)
{
	pid_t pid;
	int st;

	pid = fork();
	if (pid < 0)
		die_errno("fork");
	if (pid == 0) {
		execl("./spark-ask-http", "spark-ask-http", "--model", model,
		      "--prompt-file", prompt_path, "--out", out_path,
		      (char *)NULL);
		_exit(127);
	}
	if (waitpid(pid, &st, 0) < 0)
		die_errno("waitpid");
	if (!WIFEXITED(st) || WEXITSTATUS(st) != 0)
		return WIFEXITED(st) ? WEXITSTATUS(st) : 1;
	return 0;
}

/*
 * ask-proxy: decrypt agent envelope → plaintext in THIS process →
 * call spark-ask-http (Bifrost) → optionally re-seal reply for agent.
 */
static void cmd_ask_proxy(const char *key_path, const char *env_path,
			  const char *model, const char *out_path,
			  const char *seal_reply_path, int dry)
{
	uint8_t key[KEY_LEN];
	uint8_t *pt = malloc(MAX_PT);
	size_t n;
	char prompt_tmp[] = "/tmp/spark-enc-pt-XXXXXX";
	char reply_tmp[] = "/tmp/spark-enc-rp-XXXXXX";
	int fd;

	if (!pt)
		die("oom");
	load_key(key_path, key);
	n = open_envelope(env_path, key, pt, MAX_PT);

	fd = mkstemp(prompt_tmp);
	if (fd < 0)
		die_errno("mkstemp prompt");
	if (fchmod(fd, 0600) != 0) {
		close(fd);
		unlink(prompt_tmp);
		die_errno("fchmod prompt tmp");
	}
	if (write(fd, pt, n) != (ssize_t)n)
		die("write prompt tmp");
	close(fd);

	if (dry) {
		/* Offline: decrypt succeeded; emit dry reply, re-seal. */
		const char *dry_reply =
			"[encrypt-gateway] decrypted envelope; "
			"dry-run (no Bifrost). Model would see plaintext "
			"only inside this gateway process.";
		write_file(out_path, dry_reply, strlen(dry_reply));
		if (seal_reply_path) {
			uint8_t nonce[NONCE_LEN];
			uint8_t tag[TAG_LEN];
			uint8_t *ct;
			size_t rl = strlen(dry_reply);

			ct = malloc(rl + 32);
			if (!ct)
				die("oom");
			if (getrandom(nonce, NONCE_LEN, 0) != NONCE_LEN)
				die_errno("nonce");
			if (gcm_seal(key, nonce, (uint8_t *)"spark-reply",
				     11, (uint8_t *)dry_reply, rl, ct,
				     tag) != 0)
				die("seal reply");
			write_envelope(seal_reply_path, nonce, ct, rl, tag,
				       (uint8_t *)"spark-reply", 11);
			free(ct);
		}
		printf("{\"op\":\"ask-proxy\",\"dry\":true,"
		       "\"decrypted_pt_len\":%zu,\"backend\":\"%s\","
		       "\"out\":\"%s\"}\n",
		       n, g_backend, out_path);
		unlink(prompt_tmp);
		free(pt);
		return;
	}

	fd = mkstemp(reply_tmp);
	if (fd < 0)
		die_errno("mkstemp reply");
	close(fd);
	if (run_ask_http(model ? model : "fast", prompt_tmp, reply_tmp) !=
	    0) {
		unlink(prompt_tmp);
		unlink(reply_tmp);
		die("spark-ask-http failed (check AI_GATEWAY_URL / key)");
	}
	{
		size_t rlen = 0;
		uint8_t *reply = read_file(reply_tmp, &rlen);

		write_file(out_path, reply, rlen);
		if (seal_reply_path) {
			uint8_t nonce[NONCE_LEN];
			uint8_t tag[TAG_LEN];
			uint8_t *ct = malloc(rlen + 32);

			if (!ct)
				die("oom");
			if (getrandom(nonce, NONCE_LEN, 0) != NONCE_LEN)
				die_errno("nonce");
			if (gcm_seal(key, nonce, (uint8_t *)"spark-reply",
				     11, reply, rlen, ct, tag) != 0)
				die("seal reply");
			write_envelope(seal_reply_path, nonce, ct, rlen, tag,
				       (uint8_t *)"spark-reply", 11);
			free(ct);
		}
		printf("{\"op\":\"ask-proxy\",\"dry\":false,"
		       "\"decrypted_pt_len\":%zu,\"reply_len\":%zu,"
		       "\"backend\":\"%s\",\"out\":\"%s\"}\n",
		       n, rlen, g_backend, out_path);
		free(reply);
	}
	unlink(prompt_tmp);
	unlink(reply_tmp);
	free(pt);
}

static void cmd_self_test(void)
{
	/* NIST SP 800-38D always via OpenSSL EVP (reference vector). */
	struct afalg_info info;
	uint8_t key[KEY_LEN];
	uint8_t iv[NONCE_LEN];
	uint8_t pt[64];
	uint8_t aad[20];
	uint8_t ct_exp[60];
	uint8_t tag_exp[TAG_LEN];
	uint8_t ct[64];
	uint8_t tag[TAG_LEN];
	uint8_t pt_out[64];
	size_t pt_len, aad_len, ct_len;
	const char *saved = g_prefer;

	g_prefer = "openssl";
	pt_len = hex_decode(
		"d9313225f88406e5a55909c5aff5269a"
		"86a7a9531534f7da2e4c303d8a318a72"
		"1c3c0c95956809532fcf0e2449a6b525"
		"b16aedf5aa0de657ba637b39",
		pt, sizeof(pt));
	aad_len = hex_decode(
		"feedfacedeadbeeffeedfacedeadbeefabaddad2", aad,
		sizeof(aad));
	ct_len = hex_decode(
		"522dc1f099567d07f47f37a32a84427d"
		"643a8cdcbfe5c0c97598a2bd2555d1aa"
		"8cb08e48590dbb3da7b08b1056828838"
		"c5f61e6393ba7a0abcc9f662",
		ct_exp, sizeof(ct_exp));
	hex_decode(
		"feffe9928665731c6d6a8f9467308308"
		"feffe9928665731c6d6a8f9467308308",
		key, KEY_LEN);
	hex_decode("cafebabefacedbaddecaf888", iv, NONCE_LEN);
	hex_decode("76fc6ece0f4e1768cddf8853bb2d551b", tag_exp, TAG_LEN);

	if (pt_len != 60 || aad_len != 20 || ct_len != 60)
		die("nist fixture decode");
	if (gcm_seal(key, iv, aad, aad_len, pt, pt_len, ct, tag) != 0)
		die("self-test seal");
	if (memcmp(ct, ct_exp, ct_len) != 0)
		die("self-test CT mismatch (not real AES-GCM)");
	if (memcmp(tag, tag_exp, TAG_LEN) != 0)
		die("self-test TAG mismatch");
	if (gcm_open(key, iv, aad, aad_len, ct, ct_len, tag, pt_out) != 0)
		die("self-test open");
	if (memcmp(pt_out, pt, pt_len) != 0)
		die("self-test PT mismatch");
	afalg_probe(&info);
	printf("{\"op\":\"self-test\",\"pass\":true,\"suite\":\"NIST-"
	       "SP800-38D\",\"backend\":\"%s\",\"af_alg_aead\":%s,"
	       "\"af_alg_status\":\"%s\"}\n",
	       g_backend, afalg_usable() ? "true" : "false",
	       status_str(info.status));
	g_prefer = saved;
}

static void usage(void)
{
	fprintf(stderr,
		"usage:\n"
		"  spark-enc-gateway probe [--require af_alg]\n"
		"  spark-enc-gateway backend --set openssl|af_alg\n"
		"  spark-enc-gateway keygen --out PATH\n"
		"  spark-enc-gateway seal --key PATH "
		"(--text STR | --in PATH) --out ENV [--aad STR] "
		"[--backend openssl|af_alg]\n"
		"  spark-enc-gateway open --key PATH --envelope ENV "
		"--out PATH [--backend openssl|af_alg]\n"
		"  spark-enc-gateway ask-proxy --key PATH --envelope ENV "
		"--model ALIAS --out PATH [--seal-reply PATH] [--dry] "
		"[--backend openssl|af_alg]\n"
		"  spark-enc-gateway self-test\n"
		"Backend default: openssl. Env SPARK_ENC_BACKEND or "
		"file %s. AF_ALG fails loud if unusable "
		"(never edits modprobe/sysctl).\n",
		BACKEND_FILE);
	exit(2);
}

int main(int argc, char **argv)
{
	const char *cmd;
	const char *key = NULL, *out = NULL, *in = NULL, *text = NULL;
	const char *env = NULL, *model = NULL, *aad = NULL;
	const char *seal_reply = NULL;
	const char *backend_cli = NULL;
	const char *backend_set = NULL;
	const char *envb;
	int dry = 0;
	int require_afalg = 0;
	int i;

	if (argc < 2)
		usage();
	cmd = argv[1];
	for (i = 2; i < argc; i++) {
		if (!strcmp(argv[i], "--key") && i + 1 < argc)
			key = argv[++i];
		else if (!strcmp(argv[i], "--out") && i + 1 < argc)
			out = argv[++i];
		else if (!strcmp(argv[i], "--in") && i + 1 < argc)
			in = argv[++i];
		else if (!strcmp(argv[i], "--text") && i + 1 < argc)
			text = argv[++i];
		else if (!strcmp(argv[i], "--envelope") && i + 1 < argc)
			env = argv[++i];
		else if (!strcmp(argv[i], "--model") && i + 1 < argc)
			model = argv[++i];
		else if (!strcmp(argv[i], "--aad") && i + 1 < argc)
			aad = argv[++i];
		else if (!strcmp(argv[i], "--seal-reply") && i + 1 < argc)
			seal_reply = argv[++i];
		else if (!strcmp(argv[i], "--backend") && i + 1 < argc)
			backend_cli = argv[++i];
		else if (!strcmp(argv[i], "--set") && i + 1 < argc)
			backend_set = argv[++i];
		else if (!strcmp(argv[i], "--require") && i + 1 < argc) {
			if (!strcmp(argv[++i], "af_alg") ||
			    !strcmp(argv[i], "afalg"))
				require_afalg = 1;
			else
				die("--require expects af_alg");
		} else if (!strcmp(argv[i], "--dry"))
			dry = 1;
		else
			usage();
	}

	/* Prefer order: CLI --backend > env > file > openssl default. */
	load_prefer_from_file();
	envb = getenv("SPARK_ENC_BACKEND");
	if (envb && envb[0])
		apply_backend_flag(envb);
	if (backend_cli)
		apply_backend_flag(backend_cli);

	if (!strcmp(cmd, "probe")) {
		cmd_probe(require_afalg);
		return 0;
	}
	if (!strcmp(cmd, "backend")) {
		if (!backend_set)
			die("backend needs --set openssl|af_alg");
		cmd_backend_set(backend_set);
		return 0;
	}
	if (!strcmp(cmd, "self-test")) {
		cmd_self_test();
		return 0;
	}
	if (!strcmp(cmd, "keygen")) {
		if (!out)
			die("keygen needs --out");
		cmd_keygen(out);
		return 0;
	}
	if (!strcmp(cmd, "seal")) {
		if (!key || !out || (!text && !in))
			die("seal needs --key --out and --text|--in");
		cmd_seal(key, in, text, out, aad);
		return 0;
	}
	if (!strcmp(cmd, "open")) {
		if (!key || !env || !out)
			die("open needs --key --envelope --out");
		cmd_open(key, env, out);
		return 0;
	}
	if (!strcmp(cmd, "ask-proxy")) {
		if (!key || !env || !out)
			die("ask-proxy needs --key --envelope --out");
		cmd_ask_proxy(key, env, model, out, seal_reply, dry);
		return 0;
	}
	usage();
	return 2;
}
