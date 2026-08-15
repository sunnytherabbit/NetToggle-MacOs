/*
 * NetToggleHelper - tiny setuid-root helper for NetToggle.
 *
 * This binary must be owned by root and have the setuid bit set:
 *   chown root:wheel NetToggleHelper
 *   chmod u+s NetToggleHelper
 *
 * Usage:
 *   NetToggleHelper on  <delay_ms> <plr>
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
#include <errno.h>

#define PIPE_IN  65000
#define PIPE_OUT 65001

/* Default profile if no arguments are supplied. */
#define DEFAULT_DELAY_MS "0"
#define DEFAULT_PLR      "0.90"

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

static int parse_profile(const char *delay_ms_arg, const char *plr_arg,
                         long *delay_ms_out, double *plr_out)
{
    char *end;
    long delay_ms = strtol(delay_ms_arg, &end, 10);
    if (end == delay_ms_arg || *end != '\0' || delay_ms < 0 || delay_ms > 10000) {
        fprintf(stderr, "Invalid delay (must be 0-10000 ms): %s\n", delay_ms_arg);
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

static int do_on(long delay_ms, double plr)
{
    char delay_str[32];
    char plr_str[32];
    snprintf(delay_str, sizeof(delay_str), "%ldms", delay_ms);
    snprintf(plr_str, sizeof(plr_str), "%.6f", plr);

    char *dnctl_argv_in[] = {
        "/usr/sbin/dnctl", "-q", "pipe", "65000", "config",
        "delay", delay_str, "plr", plr_str, NULL
    };
    char *dnctl_argv_out[] = {
        "/usr/sbin/dnctl", "-q", "pipe", "65001", "config",
        "delay", delay_str, "plr", plr_str, NULL
    };

    if (run_program_silent("/usr/sbin/dnctl", dnctl_argv_in) != 0) {
        fprintf(stderr, "dnctl in pipe setup failed\n");
        return 1;
    }
    if (run_program_silent("/usr/sbin/dnctl", dnctl_argv_out) != 0) {
        fprintf(stderr, "dnctl out pipe setup failed\n");
        return 1;
    }

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

static int do_off(void)
{
    /* Restore the default ruleset. */
    char *pfctl_argv[] = {"/sbin/pfctl", "-q", "-f", "/etc/pf.conf", NULL};
    (void)run_program_silent("/sbin/pfctl", pfctl_argv);

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
        fprintf(stderr, "Usage: %s on <delay_ms> <plr> | off\n", argv[0]);
        return 1;
    }

    if (strcmp(argv[1], "on") == 0) {
        const char *delay_arg = (argc > 2) ? argv[2] : DEFAULT_DELAY_MS;
        const char *plr_arg = (argc > 3) ? argv[3] : DEFAULT_PLR;

        long delay_ms;
        double plr;
        if (parse_profile(delay_arg, plr_arg, &delay_ms, &plr) != 0) {
            return 1;
        }
        return do_on(delay_ms, plr);
    } else if (strcmp(argv[1], "off") == 0) {
        return do_off();
    } else {
        fprintf(stderr, "Unknown command: %s\n", argv[1]);
        return 1;
    }
}
