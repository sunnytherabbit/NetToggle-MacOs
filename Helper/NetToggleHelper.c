/*
 * NetToggleHelper - tiny setuid-root helper for NetToggle.
 *
 * This binary must be owned by root and have the setuid bit set:
 *   chown root:wheel NetToggleHelper
 *   chmod u+s NetToggleHelper
 *
 * Usage:
 *   NetToggleHelper on <in_delay_ms> <in_plr> <out_delay_ms> <out_plr>
 *   NetToggleHelper roblox <in_delay_ms> <in_plr> <out_delay_ms> <out_plr>  (IP list on stdin)
 *   NetToggleHelper roblox-refresh <in_delay_ms> <in_plr> <out_delay_ms> <out_plr> (IP list on stdin)
 *   NetToggleHelper off
 *
 * It is intentionally small and self-contained: it does not read
 * arbitrary files or execute user-writable scripts.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <arpa/inet.h>
#include <ctype.h>
#include <errno.h>

#define PIPE_IN  65000
#define PIPE_OUT 65001

/* Default profile if no arguments are supplied. */
#define DEFAULT_DELAY "0"
#define DEFAULT_PLR   "0.90"

/* Maximum remote IPs we will accept for a target mode. */
#define MAX_IPS 256
#define IP_LINE_MAX 256

/* Stable path for the Roblox target IP table file. */
#define ROBLOX_TABLE_FILE "/tmp/nettoggle_roblox_ips"
#define ROBLOX_TABLE_NAME "nettoggle_roblox"

static int run_program_silent(const char *path, char *const argv[])
{
    int nullfd = open("/dev/null", O_WRONLY);
    if (nullfd < 0) {
        perror("open /dev/null");
        return -1;
    }

    pid_t pid = fork();
    if (pid < 0) {
        close(nullfd);
        perror("fork");
        return -1;
    }
    if (pid == 0) {
        /* Child: inherit euid 0 from setuid parent. */
        dup2(nullfd, STDOUT_FILENO);
        dup2(nullfd, STDERR_FILENO);
        close(nullfd);
        execvp(path, argv);
        perror(path);
        _exit(127);
    }

    close(nullfd);

    int status;
    if (waitpid(pid, &status, 0) < 0) {
        perror("waitpid");
        return -1;
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

static int write_rules_and_load(const char *rules)
{
    char template[] = "/tmp/nettoggle.XXXXXX";
    int fd = mkstemp(template);
    if (fd < 0) {
        perror("mkstemp");
        return -1;
    }

    size_t len = strlen(rules);
    size_t written = 0;
    while (written < len) {
        ssize_t n = write(fd, rules + written, len - written);
        if (n < 0) {
            if (errno == EINTR) continue;
            perror("write");
            close(fd);
            unlink(template);
            return -1;
        }
        written += (size_t)n;
    }
    close(fd);

    char *pfctl_argv[] = {"/sbin/pfctl", "-q", "-f", template, NULL};
    int rc = run_program_silent("/sbin/pfctl", pfctl_argv);
    unlink(template);
    return rc;
}

static int parse_profile(const char *delay_arg, const char *plr_arg,
                         long *delay_ms_out, double *plr_out)
{
    char *end;
    long delay_ms = strtol(delay_arg, &end, 10);
    if (end == delay_arg || *end != '\0' || delay_ms < 0 || delay_ms > 60000) {
        fprintf(stderr, "Invalid delay (must be 0-60000 ms): %s\n", delay_arg);
        return 1;
    }

    double plr = strtod(plr_arg, &end);
    if (end == plr_arg || *end != '\0' || plr < 0.0 || plr > 1.0) {
        fprintf(stderr, "Invalid packet loss rate (must be 0.0-1.0): %s\n", plr_arg);
        return 1;
    }

    *delay_ms_out = delay_ms;
    *plr_out = plr;
    return 0;
}

static int config_pipes(long in_delay_ms, double in_plr,
                        long out_delay_ms, double out_plr)
{
    char in_delay_str[32], in_plr_str[32];
    char out_delay_str[32], out_plr_str[32];
    snprintf(in_delay_str, sizeof(in_delay_str), "%ldms", in_delay_ms);
    snprintf(in_plr_str, sizeof(in_plr_str), "%.6f", in_plr);
    snprintf(out_delay_str, sizeof(out_delay_str), "%ldms", out_delay_ms);
    snprintf(out_plr_str, sizeof(out_plr_str), "%.6f", out_plr);

    char *dnctl_argv_in[] = {
        "/usr/sbin/dnctl", "-q", "pipe", "65000", "config",
        "delay", in_delay_str, "plr", in_plr_str, NULL
    };
    char *dnctl_argv_out[] = {
        "/usr/sbin/dnctl", "-q", "pipe", "65001", "config",
        "delay", out_delay_str, "plr", out_plr_str, NULL
    };

    if (run_program_silent("/usr/sbin/dnctl", dnctl_argv_in) != 0) {
        fprintf(stderr, "dnctl in pipe setup failed\n");
        return 1;
    }
    if (run_program_silent("/usr/sbin/dnctl", dnctl_argv_out) != 0) {
        fprintf(stderr, "dnctl out pipe setup failed\n");
        return 1;
    }

    return 0;
}

static int is_valid_ip(const char *s)
{
    char buf[INET6_ADDRSTRLEN];
    size_t len = strlen(s);
    if (len == 0 || len >= sizeof(buf)) return 0;

    /* Copy and trim whitespace. */
    const char *start = s;
    while (*start && isspace((unsigned char)*start)) start++;
    const char *end = s + len - 1;
    while (end > start && isspace((unsigned char)*end)) end--;
    size_t trimmed = end - start + 1;
    if (trimmed == 0 || trimmed >= sizeof(buf)) return 0;
    memcpy(buf, start, trimmed);
    buf[trimmed] = '\0';

    /* Reject the wildcard. */
    if (strcmp(buf, "*") == 0) return 0;

    struct in_addr addr4;
    struct in6_addr addr6;
    if (inet_pton(AF_INET, buf, &addr4) == 1) {
        /* Reject 0.0.0.0 and 127.0.0.0/8. */
        unsigned char *b = (unsigned char *)&addr4;
        if (b[0] == 0) return 0;
        if (b[0] == 127) return 0;
        return 1;
    }
    if (inet_pton(AF_INET6, buf, &addr6) == 1) {
        /* Reject loopback ::1. */
        if (memcmp(&addr6, &in6addr_loopback, sizeof(addr6)) == 0) return 0;
        return 1;
    }
    return 0;
}

static int read_ips_from_stdin(char **ips, int *count)
{
    *count = 0;
    char line[IP_LINE_MAX];
    while (fgets(line, sizeof(line), stdin) != NULL && *count < MAX_IPS) {
        /* Remove trailing newline. */
        size_t len = strlen(line);
        if (len > 0 && line[len - 1] == '\n') line[--len] = '\0';
        if (len > 0 && line[len - 1] == '\r') line[--len] = '\0';

        if (!is_valid_ip(line)) continue;

        ips[*count] = strdup(line);
        if (ips[*count] == NULL) {
            fprintf(stderr, "Out of memory\n");
            return 1;
        }
        (*count)++;
    }
    return 0;
}

static void free_ips(char **ips, int count)
{
    for (int i = 0; i < count; i++) {
        free(ips[i]);
        ips[i] = NULL;
    }
}

static int write_ips_to_table_file(char **ips, int count)
{
    /* O_NOFOLLOW prevents a symlink attack on /tmp/nettoggle_roblox_ips. */
    int fd = open(ROBLOX_TABLE_FILE,
                  O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0644);
    if (fd < 0) {
        perror("open " ROBLOX_TABLE_FILE);
        return 1;
    }

    for (int i = 0; i < count; i++) {
        size_t len = strlen(ips[i]);
        if (write(fd, ips[i], len) != (ssize_t)len ||
            write(fd, "\n", 1) != 1) {
            perror("write " ROBLOX_TABLE_FILE);
            close(fd);
            return 1;
        }
    }

    close(fd);
    return 0;
}

static int do_on(long in_delay_ms, double in_plr,
                 long out_delay_ms, double out_plr)
{
    if (config_pipes(in_delay_ms, in_plr, out_delay_ms, out_plr) != 0) return 1;

    const char *rules =
        "include \"/etc/pf.conf\"\n"
        "dummynet in all pipe 65000\n"
        "dummynet out all pipe 65001\n";

    if (write_rules_and_load(rules) != 0) {
        fprintf(stderr, "pfctl rule load failed\n");
        return 1;
    }

    return 0;
}

static int do_target(long in_delay_ms, double in_plr,
                     long out_delay_ms, double out_plr)
{
    char *ips[MAX_IPS];
    int count = 0;

    if (read_ips_from_stdin(ips, &count) != 0) {
        free_ips(ips, count);
        return 1;
    }

    if (count == 0) {
        fprintf(stderr, "No target IPs found on stdin\n");
        return 1;
    }

    if (config_pipes(in_delay_ms, in_plr, out_delay_ms, out_plr) != 0) {
        free_ips(ips, count);
        return 1;
    }

    if (write_ips_to_table_file(ips, count) != 0) {
        free_ips(ips, count);
        return 1;
    }

    /*
     * Load a dummynet ruleset that references a PF table. The table is
     * populated from a separate file so we can refresh it without flushing
     * the whole ruleset every time the Roblox IP list changes.
     */
    const char *rules =
        "include \"/etc/pf.conf\"\n"
        "table <" ROBLOX_TABLE_NAME "> persist file \"" ROBLOX_TABLE_FILE "\"\n"
        "dummynet out quick proto {tcp, udp} from any to <" ROBLOX_TABLE_NAME "> pipe 65001\n"
        "dummynet in quick proto {tcp, udp} from <" ROBLOX_TABLE_NAME "> to any pipe 65000\n";

    int rc = write_rules_and_load(rules);
    free_ips(ips, count);

    if (rc != 0) {
        fprintf(stderr, "pfctl rule load failed\n");
        return 1;
    }

    return 0;
}

static int do_target_refresh(long in_delay_ms, double in_plr,
                              long out_delay_ms, double out_plr)
{
    char *ips[MAX_IPS];
    int count = 0;

    if (read_ips_from_stdin(ips, &count) != 0) {
        free_ips(ips, count);
        return 1;
    }

    if (count == 0) {
        /* Not an error: Roblox may momentarily have no connections. */
        free_ips(ips, count);
        return 0;
    }

    if (config_pipes(in_delay_ms, in_plr, out_delay_ms, out_plr) != 0) {
        free_ips(ips, count);
        return 1;
    }

    if (write_ips_to_table_file(ips, count) != 0) {
        free_ips(ips, count);
        return 1;
    }

    /* Replace the existing table contents without flushing the ruleset. */
    char *pfctl_argv[] = {
        "/sbin/pfctl", "-q", "-t", ROBLOX_TABLE_NAME, "-T", "replace", "-f", ROBLOX_TABLE_FILE, NULL
    };
    int rc = run_program_silent("/sbin/pfctl", pfctl_argv);
    free_ips(ips, count);

    if (rc != 0) {
        fprintf(stderr, "pfctl table replace failed\n");
        return 1;
    }

    return 0;
}

static int do_off(void)
{
    /* Restore the default ruleset. */
    char *pfctl_argv[] = {"/sbin/pfctl", "-q", "-f", "/etc/pf.conf", NULL};
    (void)run_program_silent("/sbin/pfctl", pfctl_argv);

    /* Remove the persistent table and IP file. */
    char *kill_table_argv[] = {"/sbin/pfctl", "-q", "-t", ROBLOX_TABLE_NAME, "-T", "kill", NULL};
    (void)run_program_silent("/sbin/pfctl", kill_table_argv);
    (void)unlink(ROBLOX_TABLE_FILE);

    char *dnctl_argv_in[] = {"/usr/sbin/dnctl", "-q", "pipe", "65000", "delete", NULL};
    char *dnctl_argv_out[] = {"/usr/sbin/dnctl", "-q", "pipe", "65001", "delete", NULL};
    (void)run_program_silent("/usr/sbin/dnctl", dnctl_argv_in);
    (void)run_program_silent("/usr/sbin/dnctl", dnctl_argv_out);

    return 0;
}

int main(int argc, char *argv[])
{
    if (geteuid() != 0) {
        fprintf(stderr, "NetToggleHelper must be run as root (or via setuid).\n");
        return 1;
    }

    if (argc < 2) {
        fprintf(stderr, "Usage: %s on <args> | roblox <args> | roblox-refresh <args> | off\n", argv[0]);
        return 1;
    }

    int is_target = (strcmp(argv[1], "roblox") == 0);
    int is_refresh = (strcmp(argv[1], "roblox-refresh") == 0);

    if (is_refresh || is_target || strcmp(argv[1], "on") == 0) {
        const char *in_delay  = (argc > 2) ? argv[2] : DEFAULT_DELAY;
        const char *in_plr    = (argc > 3) ? argv[3] : DEFAULT_PLR;
        const char *out_delay = (argc > 4) ? argv[4] : DEFAULT_DELAY;
        const char *out_plr   = (argc > 5) ? argv[5] : DEFAULT_PLR;

        long in_delay_ms, out_delay_ms;
        double in_plr_v, out_plr_v;
        if (parse_profile(in_delay, in_plr, &in_delay_ms, &in_plr_v) != 0 ||
            parse_profile(out_delay, out_plr, &out_delay_ms, &out_plr_v) != 0) {
            return 1;
        }

        if (is_refresh) {
            return do_target_refresh(in_delay_ms, in_plr_v, out_delay_ms, out_plr_v);
        }

        if (is_target) {
            return do_target(in_delay_ms, in_plr_v, out_delay_ms, out_plr_v);
        }

        return do_on(in_delay_ms, in_plr_v, out_delay_ms, out_plr_v);
    }

    if (strcmp(argv[1], "off") == 0) {
        return do_off();
    } else {
        fprintf(stderr, "Unknown command: %s\n", argv[1]);
        return 1;
    }
}
