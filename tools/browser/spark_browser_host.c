/*
 * spark-browser-host — optional GUI helper for Spark `browser gui --live`.
 *
 * SoT is Spark language + asm (browser/mitm ops). This C shim only
 * execs the Qt host under ../spark-browser when the .spark program
 * asks via syscall (fork_exec_wait). Dry-run never launches GUI.
 *
 * MITM protocol is Spark-owned (`mitm enable --live` →
 * ./spark-mitm-h2 serve --daemon). This host attaches only — never
 * starts the forge unless --own-mitm (debug).
 *
 * Default: QUIC ON (--enable-quic). UDP MITM = divert→quic listen.
 * Optional --disable-quic keeps TCP h2/h1 MITM only. Never
 * auto-installs CA. Never reboots.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void usage(void)
{
	fputs(
	    "usage: spark-browser-host [--url URL] "
	    "[--disable-quic|--enable-quic] [--own-mitm]\n"
	    "  Forks python3 -m spark_browser run in ../spark-browser.\n"
	    "  Default: attach to Spark MITM; QUIC ON.\n",
	    stderr);
}

int main(int argc, char **argv)
{
	const char *url = "https://example.com/";
	int disable_quic = 0;
	int own_mitm = 0;
	char *host_argv[24];
	int i = 1;
	int n = 0;
	char py[] = "python3";
	char dashm[] = "-m";
	char mod[] = "spark_browser";
	char run[] = "run";
	char urlflag[] = "--url";
	char dq[] = "--disable-quic";
	char eq[] = "--enable-quic";
	char own[] = "--own-mitm";
	char urlbuf[1024];

	while (i < argc) {
		if (strcmp(argv[i], "--help") == 0 ||
		    strcmp(argv[i], "-h") == 0) {
			usage();
			return 0;
		}
		if (strcmp(argv[i], "--url") == 0 && i + 1 < argc) {
			url = argv[++i];
			i++;
			continue;
		}
		if (strcmp(argv[i], "--disable-quic") == 0) {
			disable_quic = 1;
			i++;
			continue;
		}
		if (strcmp(argv[i], "--enable-quic") == 0) {
			disable_quic = 0;
			i++;
			continue;
		}
		if (strcmp(argv[i], "--own-mitm") == 0) {
			own_mitm = 1;
			i++;
			continue;
		}
		fprintf(stderr, "unknown arg: %s\n", argv[i]);
		usage();
		return 1;
	}

	if (strlen(url) >= sizeof(urlbuf)) {
		fputs("url too long\n", stderr);
		return 1;
	}
	memcpy(urlbuf, url, strlen(url) + 1);

	if (chdir("../spark-browser") != 0) {
		perror("chdir ../spark-browser");
		fputs(
		    "run spark-browser-host from spark/ "
		    "(cwd must see ../spark-browser)\n",
		    stderr);
		return 1;
	}

	host_argv[n++] = py;
	host_argv[n++] = dashm;
	host_argv[n++] = mod;
	host_argv[n++] = run;
	host_argv[n++] = urlflag;
	host_argv[n++] = urlbuf;
	host_argv[n++] = disable_quic ? dq : eq;
	if (own_mitm)
		host_argv[n++] = own;
	host_argv[n] = NULL;

	execvp(py, host_argv);
	perror("execvp python3 -m spark_browser");
	return 1;
}
