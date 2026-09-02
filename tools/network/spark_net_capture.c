/* Spark live packet capture → classic pcap.
 * AF_PACKET SOCK_RAW on named iface. Needs CAP_NET_RAW (or root).
 *
 * Usage:
 *   ./spark-net-capture --probe
 *   ./spark-net-capture --iface lo --duration 2 \
 *       --out out/capture.pcap
 *
 * --probe: try AF_PACKET only; never claims a sniff (claimed:false).
 * Capture without CAP_NET_RAW → exit 4 + claimed:false JSON.
 *
 * Build: make spark-net
 */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <linux/if_ether.h>
#include <linux/if_packet.h>
#include <net/if.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t g_stop;

static void on_alarm(int sig) {
  (void)sig;
  g_stop = 1;
}

static void die(const char *what) {
  fprintf(stderr, "spark-net-capture: %s: %s\n", what,
          strerror(errno));
  exit(1);
}

static void write_u32_le(int fd, uint32_t v) {
  unsigned char b[4] = {v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff,
                        (v >> 24) & 0xff};
  if (write(fd, b, 4) != 4)
    die("write");
}

static void write_u16_le(int fd, uint16_t v) {
  unsigned char b[2] = {v & 0xff, (v >> 8) & 0xff};
  if (write(fd, b, 2) != 2)
    die("write");
}

static void write_pcap_hdr(int fd) {
  /* magic a1b2c3d4, v2.4, thiszone=0, sigfigs=0,
   * snaplen=65535, LINKTYPE_ETHERNET=1 */
  write_u32_le(fd, 0xa1b2c3d4u);
  write_u16_le(fd, 2);
  write_u16_le(fd, 4);
  write_u32_le(fd, 0);
  write_u32_le(fd, 0);
  write_u32_le(fd, 65535);
  write_u32_le(fd, 1);
}

/* Honest capability probe — no packets, never claimed:true. */
static int cmd_probe(void) {
  int sock = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL));
  int err = errno;
  int ok = (sock >= 0);
  if (sock >= 0)
    close(sock);
  printf("{\"op\":\"capture_probe\",\"claimed\":false,"
         "\"cap_net_raw\":%s,\"ready\":%s,\"errno\":%d,"
         "\"hint\":\"sudo setcap cap_net_raw,cap_net_admin+ep "
         "./spark-net-capture\"}\n",
         ok ? "true" : "false", ok ? "true" : "false",
         ok ? 0 : err);
  return 0;
}

static void emit_cap_miss(void) {
  fprintf(stderr,
          "spark-net-capture: CAP_NET_RAW unavailable\n");
  printf("{\"op\":\"capture\",\"claimed\":false,\"ready\":false,"
         "\"error\":\"CAP_NET_RAW unavailable\","
         "\"hint\":\"sudo setcap cap_net_raw,cap_net_admin+ep "
         "./spark-net-capture\"}\n");
}

int main(int argc, char **argv) {
  const char *iface = "lo";
  const char *out_path = "out/capture.pcap";
  int duration = 2;
  int do_probe = 0;

  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--probe"))
      do_probe = 1;
    else if (!strcmp(argv[i], "--iface") && i + 1 < argc)
      iface = argv[++i];
    else if (!strcmp(argv[i], "--duration") && i + 1 < argc)
      duration = atoi(argv[++i]);
    else if (!strcmp(argv[i], "--out") && i + 1 < argc)
      out_path = argv[++i];
    else if (!strcmp(argv[i], "--help")) {
      fputs(
          "Usage: spark-net-capture --probe\n"
          "       spark-net-capture --iface IF --duration SEC "
          "--out PATH.pcap\n"
          "Requires CAP_NET_RAW or root for live capture "
          "(setcap cap_net_raw+ep).\n"
          "CAP miss on capture → exit 4, claimed:false.\n",
          stdout);
      return 0;
    }
  }

  if (do_probe)
    return cmd_probe();

  if (duration < 1)
    duration = 1;
  if (duration > 3600)
    duration = 3600;

  int sock = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL));
  if (sock < 0) {
    if (errno == EPERM || errno == EACCES) {
      emit_cap_miss();
      return 4;
    }
    die("socket(AF_PACKET) — need CAP_NET_RAW?");
  }

  struct ifreq ifr;
  memset(&ifr, 0, sizeof ifr);
  snprintf(ifr.ifr_name, IFNAMSIZ, "%s", iface);
  if (ioctl(sock, SIOCGIFINDEX, &ifr) < 0)
    die("SIOCGIFINDEX");

  struct sockaddr_ll sll;
  memset(&sll, 0, sizeof sll);
  sll.sll_family = AF_PACKET;
  sll.sll_protocol = htons(ETH_P_ALL);
  sll.sll_ifindex = ifr.ifr_ifindex;
  if (bind(sock, (struct sockaddr *)&sll, sizeof sll) < 0)
    die("bind");

  int out = open(out_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (out < 0)
    die("open out");
  write_pcap_hdr(out);

  signal(SIGALRM, on_alarm);
  alarm((unsigned)duration);

  unsigned char buf[65536];
  unsigned long long n = 0;
  while (!g_stop) {
    ssize_t r = recvfrom(sock, buf, sizeof buf, 0, NULL, NULL);
    if (r < 0) {
      if (errno == EINTR)
        continue;
      die("recvfrom");
    }
    struct timeval tv;
    gettimeofday(&tv, NULL);
    write_u32_le(out, (uint32_t)tv.tv_sec);
    write_u32_le(out, (uint32_t)tv.tv_usec);
    write_u32_le(out, (uint32_t)r);
    write_u32_le(out, (uint32_t)r);
    if (write(out, buf, (size_t)r) != r)
      die("write pkt");
    n++;
  }

  close(out);
  close(sock);
  printf("{\"op\":\"capture\",\"claimed\":true,\"iface\":\"%s\","
         "\"duration_s\":%d,\"packets\":%llu,\"path\":\"%s\"}\n",
         iface, duration, n, out_path);
  return 0;
}
