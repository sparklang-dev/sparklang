/*
 * spark-engine-show — minimal X11 PutImage for Spark engine B.
 * Forked by `browser show` / `engine show` / engine render under --live.
 * Dry Spark never forks. Pipeline PPM: out/engine/pipeline.ppm.
 *
 * Usage:
 *   ./spark-engine-show --dry --ppm PATH
 *   ./spark-engine-show --ppm PATH [--hold MS]
 *   ./spark-engine-show --rgb PATH --w W --h H [--hold MS]
 *
 * --dry: validate + JSON only; never XOpenDisplay.
 * Default --hold 0: map, PutImage, XSync, exit (CI-safe).
 * Live Spark fork passes --hold 2000 (visible window).
 */
#define _GNU_SOURCE
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static void die(const char *m)
{
	fprintf(stderr, "spark-engine-show: %s\n", m);
	exit(1);
}

static unsigned char *load_ppm(const char *path, int *ow, int *oh)
{
	FILE *f = fopen(path, "rb");
	char magic[3];
	int w, h, maxv;
	size_t n;
	unsigned char *rgb;

	if (!f) {
		fprintf(stderr, "spark-engine-show: open %s: %s\n",
			path, strerror(errno));
		exit(1);
	}
	if (fscanf(f, "%2s", magic) != 1 || strcmp(magic, "P6") != 0)
		die("not P6 PPM");
	if (fscanf(f, "%d %d", &w, &h) != 2 || w < 1 || h < 1)
		die("bad PPM size");
	if (fscanf(f, "%d", &maxv) != 1 || maxv != 255)
		die("bad PPM maxval");
	fgetc(f); /* single whitespace after maxval */
	n = (size_t)w * (size_t)h * 3;
	rgb = malloc(n);
	if (!rgb)
		die("oom");
	if (fread(rgb, 1, n, f) != n)
		die("short PPM read");
	fclose(f);
	*ow = w;
	*oh = h;
	return rgb;
}

static unsigned char *load_rgb(const char *path, int w, int h)
{
	FILE *f = fopen(path, "rb");
	size_t n;
	unsigned char *rgb;

	if (!f) {
		fprintf(stderr, "spark-engine-show: open %s: %s\n",
			path, strerror(errno));
		exit(1);
	}
	if (w < 1 || h < 1)
		die("need --w --h for --rgb");
	n = (size_t)w * (size_t)h * 3;
	rgb = malloc(n);
	if (!rgb)
		die("oom");
	if (fread(rgb, 1, n, f) != n)
		die("short RGB read");
	fclose(f);
	return rgb;
}

static void usage(void)
{
	fputs(
	    "usage: spark-engine-show [--dry] --ppm PATH [--hold MS]\n"
	    "       spark-engine-show [--dry] --rgb PATH --w W --h H"
	    " [--hold MS]\n",
	    stderr);
}

static int show_x11(const unsigned char *rgb, int w, int h, int hold_ms)
{
	Display *dpy;
	Window win;
	XImage *img;
	GC gc;
	int screen;
	unsigned char *xbuf;
	int i, n = w * h;
	struct timespec ts;

	dpy = XOpenDisplay(NULL);
	if (!dpy) {
		fputs("spark-engine-show: XOpenDisplay failed"
		      " (DISPLAY unset?)\n",
		      stderr);
		return 4;
	}
	screen = DefaultScreen(dpy);
	win = XCreateSimpleWindow(dpy, RootWindow(dpy, screen), 0, 0,
				  (unsigned)w, (unsigned)h, 0,
				  BlackPixel(dpy, screen),
				  WhitePixel(dpy, screen));
	XStoreName(dpy, win, "Spark engine show");
	XSelectInput(dpy, win, ExposureMask | StructureNotifyMask);
	XMapWindow(dpy, win);
	XFlush(dpy);

	/* XImage wants 32bpp BGRA for TrueColor on typical this host. */
	xbuf = calloc((size_t)n, 4);
	if (!xbuf)
		die("oom xbuf");
	for (i = 0; i < n; i++) {
		xbuf[i * 4 + 0] = rgb[i * 3 + 2]; /* B */
		xbuf[i * 4 + 1] = rgb[i * 3 + 1]; /* G */
		xbuf[i * 4 + 2] = rgb[i * 3 + 0]; /* R */
		xbuf[i * 4 + 3] = 0xff;
	}
	img = XCreateImage(dpy, DefaultVisual(dpy, screen), 24, ZPixmap, 0,
			   (char *)xbuf, (unsigned)w, (unsigned)h, 32, 0);
	if (!img)
		die("XCreateImage");
	gc = XCreateGC(dpy, win, 0, NULL);
	/* Wait for MapNotify briefly */
	for (i = 0; i < 50; i++) {
		XEvent ev;
		if (XPending(dpy)) {
			XNextEvent(dpy, &ev);
			if (ev.type == MapNotify)
				break;
		} else {
			ts.tv_sec = 0;
			ts.tv_nsec = 10 * 1000 * 1000;
			nanosleep(&ts, NULL);
		}
	}
	/* Ultrawide WMs park new clients far-right; pin left+raise. */
	XMoveWindow(dpy, win, 120, 80);
	XRaiseWindow(dpy, win);
	XPutImage(dpy, win, gc, img, 0, 0, 0, 0, (unsigned)w, (unsigned)h);
	XSync(dpy, False);
	if (hold_ms > 0) {
		ts.tv_sec = hold_ms / 1000;
		ts.tv_nsec = (long)(hold_ms % 1000) * 1000000L;
		nanosleep(&ts, NULL);
	}
	XDestroyImage(img); /* frees xbuf */
	XFreeGC(dpy, gc);
	XDestroyWindow(dpy, win);
	XCloseDisplay(dpy);
	return 0;
}

int main(int argc, char **argv)
{
	const char *ppm = NULL;
	const char *rgb_path = NULL;
	int w = 0, h = 0, hold = 0, dry = 0;
	int i = 1;
	unsigned char *pix;
	int rc;

	while (i < argc) {
		if (strcmp(argv[i], "--help") == 0 ||
		    strcmp(argv[i], "-h") == 0) {
			usage();
			return 0;
		}
		if (strcmp(argv[i], "--dry") == 0) {
			dry = 1;
			i++;
			continue;
		}
		if (strcmp(argv[i], "--ppm") == 0 && i + 1 < argc) {
			ppm = argv[++i];
			i++;
			continue;
		}
		if (strcmp(argv[i], "--rgb") == 0 && i + 1 < argc) {
			rgb_path = argv[++i];
			i++;
			continue;
		}
		if (strcmp(argv[i], "--w") == 0 && i + 1 < argc) {
			w = atoi(argv[++i]);
			i++;
			continue;
		}
		if (strcmp(argv[i], "--h") == 0 && i + 1 < argc) {
			h = atoi(argv[++i]);
			i++;
			continue;
		}
		if (strcmp(argv[i], "--hold") == 0 && i + 1 < argc) {
			hold = atoi(argv[++i]);
			i++;
			continue;
		}
		fprintf(stderr, "unknown arg: %s\n", argv[i]);
		usage();
		return 1;
	}

	if (!ppm && !rgb_path) {
		usage();
		return 1;
	}
	if (ppm)
		pix = load_ppm(ppm, &w, &h);
	else
		pix = load_rgb(rgb_path, w, h);

	printf("{\"op\":\"engine_show\",\"ok\":true,\"dry\":%s,"
	       "\"w\":%d,\"h\":%d,\"path\":\"%s\",\"display\":%s}\n",
	       dry ? "true" : "false", w, h,
	       ppm ? ppm : rgb_path, dry ? "false" : "true");
	fflush(stdout);

	if (dry) {
		free(pix);
		return 0;
	}
	rc = show_x11(pix, w, h, hold);
	free(pix);
	return rc;
}
