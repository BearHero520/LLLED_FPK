#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "fan/thermal_curve.h"

enum fan_channel {
    FAN_CHANNEL_CPU,
    FAN_CHANNEL_SYSTEM
};

struct fan_target {
    const char *name;
    enum fan_channel channel;
};

struct model_route {
    const char *dmi_product;
    const char *id;
    struct fan_target targets[3];
    bool requires_force;
};

static const struct model_route model_routes[] = {
    {"DX4600", "dx4600", {{"sys", FAN_CHANNEL_SYSTEM}, {NULL, 0}}, true},
    {"DX4600+", "dx4600", {{"sys", FAN_CHANNEL_SYSTEM}, {NULL, 0}}, true},
    {"DX4600 Pro", "dx4600", {{"sys", FAN_CHANNEL_SYSTEM}, {NULL, 0}}, true},
    {"DXP4800", "dxp4800", {{"sys", FAN_CHANNEL_SYSTEM}, {NULL, 0}}, true},
    {"DXP4800 Plus", "dxp4800plus", {{"cpu", FAN_CHANNEL_CPU}, {"sys", FAN_CHANNEL_SYSTEM}, {NULL, 0}}, false},
    {"DXP4800 Pro", "dxp4800plus", {{"cpu", FAN_CHANNEL_CPU}, {"sys", FAN_CHANNEL_SYSTEM}, {NULL, 0}}, false},
    {"DXP4800S", "dxp4800s", {{"sys", FAN_CHANNEL_SYSTEM}, {NULL, 0}}, true},
    /* The stock controller uses `cpu` for the CPU output and `set` (the
     * legacy ugreenctl target is `all`) for the two system fans. */
    {"DXP480T Plus", "dxp480tplus", {{"cpu", FAN_CHANNEL_CPU}, {"all", FAN_CHANNEL_SYSTEM}, {NULL, 0}}, false},
    {"DXP6800", "dxp6800", {{"cpu", FAN_CHANNEL_CPU}, {"sys", FAN_CHANNEL_SYSTEM}, {NULL, 0}}, true},
    {"DXP6800 Plus", "dxp6800plus", {{"cpu", FAN_CHANNEL_CPU}, {"sys", FAN_CHANNEL_SYSTEM}, {NULL, 0}}, true},
    {"DXP6800 Pro", "dxp6800pro", {{"cpu", FAN_CHANNEL_CPU}, {"sys", FAN_CHANNEL_SYSTEM}, {NULL, 0}}, true}
};

struct pwm_hold_state {
    unsigned int applied_pwm;
    unsigned int pending_lower_pwm;
    time_t pending_since;
    bool applied_known;
};

static volatile sig_atomic_t daemon_running = 1;

static void signal_stop(int signal_number)
{
    (void)signal_number;
    daemon_running = 0;
}

static void usage(FILE *stream)
{
    (void)fputs("Usage: ugreenctl-fand --config <file> --state <file> --ugreenctl <file>\n"
                "                      --plugin-dir <dir> [--once]\n\n"
                "Runs a software temperature curve and sends every PWM update through\n"
                "the guarded ugreenctl model plugin. It is not a hardware auto mode.\n",
                stream);
}

static int read_dmi_product(char *product, size_t product_size)
{
    static const char * const paths[] = {
        "/sys/class/dmi/id/product_name",
        "/sys/devices/virtual/dmi/id/product_name",
        NULL
    };
    const char * const *path;

    for (path = paths; *path != NULL; ++path) {
        FILE *stream = fopen(*path, "r");
        size_t length;

        if (stream == NULL) {
            continue;
        }
        if (fgets(product, (int)product_size, stream) == NULL) {
            (void)fclose(stream);
            continue;
        }
        (void)fclose(stream);
        length = strlen(product);
        while (length > 0 && (product[length - 1] == '\n' || product[length - 1] == '\r')) {
            product[--length] = '\0';
        }
        return product[0] == '\0' ? -ENODEV : 0;
    }
    return -ENOENT;
}

static const struct model_route *find_model_route(const char *product)
{
    size_t index;

    for (index = 0; index < sizeof(model_routes) / sizeof(model_routes[0]); ++index) {
        if (strcmp(model_routes[index].dmi_product, product) == 0) {
            return &model_routes[index];
        }
    }
    return NULL;
}

static const char *stock_profile_for_route(const struct model_route *route)
{
    if (strcmp(route->id, "dx4600") == 0) return "stock-4600";
    if (strcmp(route->id, "dxp4800") == 0) return "stock-4800";
    if (strcmp(route->id, "dxp4800s") == 0) return "stock-4800s";
    if (strcmp(route->id, "dxp4800plus") == 0) return "stock-4800plus";
    if (strcmp(route->id, "dxp480tplus") == 0) return "stock-480tplus";
    if (strcmp(route->id, "dxp6800") == 0) return "stock-6800";
    if (strcmp(route->id, "dxp6800pro") == 0) return "stock-6800pro";
    if (strcmp(route->id, "dxp6800plus") == 0) return "stock-6800plus";
    return NULL;
}

static int profile_matches_route(const struct ugreenctl_fan_curve_config *config,
                                 const struct model_route *route)
{
    const char *expected;

    if (strcmp(config->profile, "custom") == 0) {
        return 0;
    }
    expected = stock_profile_for_route(route);
    return expected != NULL && strcmp(config->profile, expected) == 0 ? 0 : -EINVAL;
}

static int create_parent_directory(const char *path)
{
    char directory[4096];
    char *slash;

    if (snprintf(directory, sizeof(directory), "%s", path) >= (int)sizeof(directory)) {
        return -ENAMETOOLONG;
    }
    slash = strrchr(directory, '/');
    if (slash == NULL || slash == directory) {
        return 0;
    }
    *slash = '\0';
    if (mkdir(directory, 0755) != 0 && errno != EEXIST) {
        return -errno;
    }
    return 0;
}

static unsigned int maximum_of(unsigned int left, unsigned int right)
{
    return left > right ? left : right;
}

static int maximum_applied(int cpu_pwm, int system_pwm)
{
    if (cpu_pwm < 0) return system_pwm;
    if (system_pwm < 0) return cpu_pwm;
    return cpu_pwm > system_pwm ? cpu_pwm : system_pwm;
}

static void write_state(const char *path, const char *model,
                        const struct ugreenctl_fan_curve_config *config,
                        const struct ugreenctl_thermal_snapshot *snapshot,
                        const struct ugreenctl_fan_curve_plan *plan,
                        int applied_cpu_pwm, int applied_system_pwm,
                        const char *status, const char *detail)
{
    char temporary[4096];
    FILE *stream;
    time_t now = time(NULL);
    unsigned int desired_pwm = maximum_of(plan->cpu_pwm, plan->system_pwm);
    int applied_pwm = maximum_applied(applied_cpu_pwm, applied_system_pwm);

    if (path == NULL || create_parent_directory(path) != 0 ||
        snprintf(temporary, sizeof(temporary), "%s.tmp", path) >= (int)sizeof(temporary)) {
        return;
    }
    stream = fopen(temporary, "w");
    if (stream == NULL) {
        return;
    }
    (void)fprintf(stream,
                  "timestamp=%ld\nmodel=%s\nprofile=%s\nstatus=%s\n"
                  "cpu_celsius=%d\ncpu_peak_celsius=%d\nhdd_celsius=%d\nssd_celsius=%d\n"
                  "desired_pwm=%u\napplied_pwm=%d\n"
                  "desired_cpu_pwm=%u\ndesired_system_pwm=%u\n"
                  "applied_cpu_pwm=%d\napplied_system_pwm=%d\ndetail=%s\n",
                  (long)now, model != NULL ? model : "unknown", config->profile,
                  status != NULL ? status : "unknown", snapshot->cpu_celsius,
                  snapshot->cpu_peak_celsius,
                  snapshot->hdd_celsius, snapshot->ssd_celsius, desired_pwm, applied_pwm,
                  plan->cpu_pwm, plan->system_pwm, applied_cpu_pwm, applied_system_pwm,
                  detail != NULL ? detail : "");
    if (fclose(stream) == 0) {
        (void)rename(temporary, path);
    } else {
        (void)unlink(temporary);
    }
}

static int invoke_ugreenctl(const char *binary, const char *plugin_dir,
                            bool force, const char *target, unsigned int pwm)
{
    char pwm_text[16];
    const char *argv[12];
    size_t index = 0;
    pid_t child;
    int status;

    if (snprintf(pwm_text, sizeof(pwm_text), "%u", pwm) >= (int)sizeof(pwm_text)) {
        return -EINVAL;
    }
    argv[index++] = binary;
    argv[index++] = "--plugin-dir";
    argv[index++] = plugin_dir;
    if (force) argv[index++] = "--force";
    argv[index++] = "--apply";
    argv[index++] = "fan";
    argv[index++] = "set";
    argv[index++] = target;
    argv[index++] = pwm_text;
    argv[index] = NULL;

    child = fork();
    if (child < 0) {
        return -errno;
    }
    if (child == 0) {
        execv(binary, (char * const *)argv);
        _exit(127);
    }
    if (waitpid(child, &status, 0) < 0) {
        return -errno;
    }
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        return -EIO;
    }
    return 0;
}

static int apply_pwm(const struct model_route *route, const char *binary, const char *plugin_dir,
                     bool allow_unvalidated, const char *target, unsigned int pwm)
{
    bool force = route->requires_force || allow_unvalidated;

    if (route->requires_force && !allow_unvalidated) {
        return -EPERM;
    }
    return invoke_ugreenctl(binary, plugin_dir, force, target, pwm);
}

static int acquire_daemon_lock(void)
{
    const char *path = getenv("UGREENCTL_FAN_CURVE_LOCK");
    int fd;

    if (path == NULL || path[0] == '\0') {
        path = "/run/ugreenctl-fand.lock";
    }
    fd = open(path, O_CREAT | O_CLOEXEC | O_RDWR, 0600);
    if (fd < 0) {
        return -errno;
    }
    if (flock(fd, LOCK_EX | LOCK_NB) != 0) {
        int saved = errno;
        (void)close(fd);
        return -saved;
    }
    return fd;
}

static unsigned int desired_for_target(const struct fan_target *target,
                                       const struct ugreenctl_fan_curve_plan *plan)
{
    if (target->channel == FAN_CHANNEL_CPU) return plan->cpu_pwm;
    return plan->system_pwm;
}

static unsigned int hold_lower_pwm(struct pwm_hold_state *state, unsigned int desired_pwm,
                                   unsigned int delay_seconds)
{
    time_t now;

    if (!state->applied_known || desired_pwm >= state->applied_pwm) {
        state->pending_lower_pwm = 0;
        state->pending_since = 0;
        return desired_pwm;
    }
    now = time(NULL);
    if (state->pending_lower_pwm != desired_pwm) {
        state->pending_lower_pwm = desired_pwm;
        state->pending_since = now;
    }
    if ((unsigned long)(now - state->pending_since) < delay_seconds) {
        return state->applied_pwm;
    }
    return desired_pwm;
}

static void applied_channels(const struct model_route *route,
                             const struct pwm_hold_state states[3],
                             int *cpu_pwm, int *system_pwm)
{
    size_t index;

    *cpu_pwm = -1;
    *system_pwm = -1;
    for (index = 0; index < 3 && route->targets[index].name != NULL; ++index) {
        if (!states[index].applied_known) continue;
        if (route->targets[index].channel == FAN_CHANNEL_CPU) {
            *cpu_pwm = (int)states[index].applied_pwm;
        } else {
            *system_pwm = (int)states[index].applied_pwm;
        }
    }
}

int main(int argc, char **argv)
{
    const char *config_path = NULL;
    const char *state_path = NULL;
    const char *binary = NULL;
    const char *plugin_dir = NULL;
    bool once = false;
    struct ugreenctl_fan_curve_config config;
    struct ugreenctl_thermal_snapshot snapshot = {-1, -1, -1, -1};
    struct ugreenctl_fan_curve_plan last_plan;
    struct pwm_hold_state target_states[3] = {{0}};
    const struct model_route *route;
    char product[256];
    char error[256] = {0};
    int lock_fd;
    int argument;

    for (argument = 1; argument < argc; ++argument) {
        if ((strcmp(argv[argument], "--config") == 0 || strcmp(argv[argument], "--state") == 0 ||
             strcmp(argv[argument], "--ugreenctl") == 0 || strcmp(argv[argument], "--plugin-dir") == 0) &&
            argument + 1 < argc) {
            const char *value = argv[++argument];
            if (strcmp(argv[argument - 1], "--config") == 0) config_path = value;
            else if (strcmp(argv[argument - 1], "--state") == 0) state_path = value;
            else if (strcmp(argv[argument - 1], "--ugreenctl") == 0) binary = value;
            else plugin_dir = value;
            continue;
        }
        if (strcmp(argv[argument], "--once") == 0) {
            once = true;
            continue;
        }
        usage(stderr);
        return EXIT_FAILURE;
    }
    if (config_path == NULL || state_path == NULL || binary == NULL || plugin_dir == NULL ||
        access(binary, X_OK) != 0 || access(plugin_dir, R_OK) != 0) {
        usage(stderr);
        return EXIT_FAILURE;
    }
    if (ugreenctl_fan_curve_load_config(config_path, &config, error, sizeof(error)) != 0) {
        (void)fprintf(stderr, "error: %s\n", error);
        return EXIT_FAILURE;
    }
    if (read_dmi_product(product, sizeof(product)) != 0 ||
        (route = find_model_route(product)) == NULL) {
        (void)fprintf(stderr, "error: unsupported or unverified DMI product for fan curve\n");
        return EXIT_FAILURE;
    }
    if (profile_matches_route(&config, route) != 0) {
        (void)fprintf(stderr, "error: the selected stock profile does not match the exact DMI model\n");
        return EXIT_FAILURE;
    }
    lock_fd = acquire_daemon_lock();
    if (lock_fd < 0) {
        (void)fprintf(stderr, "error: another ugreenctl fan curve daemon is already active\n");
        return EXIT_FAILURE;
    }
    last_plan.cpu_pwm = config.minimum_pwm;
    last_plan.system_pwm = config.minimum_pwm;
    (void)signal(SIGTERM, signal_stop);
    (void)signal(SIGINT, signal_stop);

    while (daemon_running) {
        struct ugreenctl_fan_curve_plan plan = {config.failsafe_pwm, config.failsafe_pwm};
        int temperature_result;
        int write_result = 0;
        int applied_cpu_pwm;
        int applied_system_pwm;
        size_t index;

        memset(error, 0, sizeof(error));
        temperature_result = ugreenctl_read_thermal_snapshot(&snapshot, error, sizeof(error));
        if (temperature_result == 0) {
            temperature_result = ugreenctl_fan_curve_evaluate_plan(&config, &snapshot, &plan,
                                                                    error, sizeof(error));
        }
        if (temperature_result != 0) {
            plan.cpu_pwm = config.failsafe_pwm;
            plan.system_pwm = config.failsafe_pwm;
        }
        last_plan = plan;
        for (index = 0; index < 3 && route->targets[index].name != NULL; ++index) {
            unsigned int target_pwm = hold_lower_pwm(&target_states[index],
                                                      desired_for_target(&route->targets[index], &plan),
                                                      config.downshift_delay_seconds);
            if (!target_states[index].applied_known || target_pwm != target_states[index].applied_pwm) {
                write_result = apply_pwm(route, binary, plugin_dir, config.allow_unvalidated_writes,
                                         route->targets[index].name, target_pwm);
                if (write_result != 0) break;
                target_states[index].applied_pwm = target_pwm;
                target_states[index].applied_known = true;
            }
        }
        applied_channels(route, target_states, &applied_cpu_pwm, &applied_system_pwm);
        if (write_result == 0) {
            write_state(state_path, route->id, &config, &snapshot, &plan,
                        applied_cpu_pwm, applied_system_pwm,
                        temperature_result == 0 ? "running" : "failsafe", error);
        } else {
            (void)snprintf(error, sizeof(error), "ugreenctl PWM write failed (%d)", write_result);
            write_state(state_path, route->id, &config, &snapshot, &plan,
                        applied_cpu_pwm, applied_system_pwm, "error", error);
        }
        if (once) {
            (void)close(lock_fd);
            return write_result == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
        }
        for (unsigned int waited = 0; daemon_running && waited < config.interval_seconds; ++waited) {
            (void)sleep(1);
        }
    }
    {
        int applied_cpu_pwm;
        int applied_system_pwm;

        applied_channels(route, target_states, &applied_cpu_pwm, &applied_system_pwm);
        write_state(state_path, route->id, &config, &snapshot, &last_plan,
                    applied_cpu_pwm, applied_system_pwm, "stopped", "daemon stopped");
    }
    (void)close(lock_fd);
    return EXIT_SUCCESS;
}
